// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Ways to reach the internet: the Ethernet WAN and the Wi-Fi repeater.

'use strict';

import { readfile, readlink, lsdir } from 'fs';
import * as nl80211 from 'nl80211';
import {
	INVALID, NOT_FOUND, ubus, uci, run, run_later, fail, uptime,
	ipv4_to_int, int_to_ipv4, parse_netmask, prefix_to_mask, subnet
} from 'supacudy.util';

const PROTOS = ['dhcp', 'static', 'pppoe'];
const STA_ENCRYPTIONS = ['none', 'psk2', 'psk-mixed', 'sae', 'sae-mixed', 'owe'];
const SCAN_WAIT_MS = 3000;
const BAND_OF = (freq) => freq < 3000 ? '2g' : (freq < 5925 ? '5g' : '6g');

function channel_of(freq) {
	if (freq == 2484)
		return 14;
	if (freq < 3000)
		return (freq - 2407) / 5;
	return (freq - (freq >= 5955 ? 5950 : 5000)) / 5;
}

function iface_status(name) {
	return ubus().call(`network.interface.${name}`, 'status');
}

function carrier(dev) {
	const c = readfile(`/sys/class/net/${dev}/carrier`);
	return c ? trim(c) == '1' : false;
}

function address_info(st) {
	if (!st?.up)
		return { ipaddr: null, gateway: null, dns: [] };
	const addr = st['ipv4-address']?.[0];
	let gateway = null;
	for (let r in st.route ?? [])
		if (r.target == '0.0.0.0' && r.mask == 0)
			gateway = r.nexthop;
	return {
		ipaddr: addr ? `${addr.address}/${addr.mask}` : null,
		gateway,
		dns: st['dns-server'] ?? []
	};
}

function default_route_iface() {
	const dump = ubus().call('network.interface', 'dump') ?? { interface: [] };
	let best = null;
	for (let i in dump.interface)
		for (let r in i.route ?? [])
			if (r.target == '0.0.0.0' && r.mask == 0 && i.up && (best == null || (i.metric ?? 0) < best.metric))
				best = { name: i.interface, metric: i.metric ?? 0 };
	return best?.name;
}

// One quick probe; a router behind a captive portal answers ping but not
// HTTP, which the UI will treat separately later.
function internet_reachable() {
	return run('ping -c1 -W2 1.1.1.1 >/dev/null || ping -c1 -W2 8.8.8.8 >/dev/null').code == 0;
}

function sta_iface(cur) {
	return cur.get('wireless', 'wwan') ? 'wwan' : null;
}

function sta_ifname() {
	const radios = ubus().call('network.wireless', 'status') ?? {};
	for (let name, radio in radios)
		for (let i in radio.interfaces ?? [])
			if (i.section == 'wwan' && i.ifname)
				return i.ifname;
	return null;
}

function sta_link(ifname) {
	if (!ifname)
		return null;
	const st = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: ifname })?.[0];
	if (!st)
		return null;
	return { bssid: st.mac, signal: st.sta_info?.signal ?? null };
}

function saved_networks(cur) {
	const out = [];
	cur.foreach('supacudy', 'repeater', (s) => {
		if (s.ssid)
			push(out, { id: s['.name'], ssid: s.ssid, encryption: s.encryption ?? 'none', key: s.key ?? '', last_used: +(s.last_used ?? 0) });
	});
	return sort(out, (a, b) => b.last_used - a.last_used);
}

function lan_bridge(cur) {
	let name = null;
	cur.foreach('network', 'device', (d) => {
		if (d.name == 'br-lan')
			name ??= d['.name'];
	});
	return name;
}

function wan_as_lan(cur) {
	return cur.get('supacudy', 'main', 'wan_port') != null;
}

// With the repeater or a phone as the uplink, the WAN port is more useful
// as another LAN port. The port name is remembered to undo it.
function wan_port_set(req) {
	if (type(req.args.as_lan) != 'bool')
		return req.error(INVALID);
	const cur = uci();
	const bridge = lan_bridge(cur);
	if (!bridge)
		return req.error(NOT_FOUND);
	const ports_of = () => {
		const p = cur.get('network', bridge, 'ports');
		return type(p) == 'array' ? p : (p ? [ p ] : []);
	};
	if (req.args.as_lan == wan_as_lan(cur))
		return { applied: true };
	if (cur.get('supacudy', 'netmode', 'mode') == 'ap')
		return fail('ap_mode');
	if (req.args.as_lan) {
		const port = cur.get('network', 'wan', 'device');
		if (!port || match(port, /^(br-|pppoe-)/))
			return fail('wan_not_configured');
		cur.set('supacudy', 'main', 'wan_port', port);
		cur.set('network', bridge, 'ports', uniq([ ...ports_of(), port ]));
		for (let iface in [ 'wan', 'wan6' ])
			if (cur.get('network', iface))
				cur.set('network', iface, 'disabled', '1');
	} else {
		const port = cur.get('supacudy', 'main', 'wan_port');
		const rest = filter(ports_of(), (p) => p != port);
		if (length(rest))
			cur.set('network', bridge, 'ports', rest);
		else
			cur.delete('network', bridge, 'ports');
		cur.delete('supacudy', 'main', 'wan_port');
		for (let iface in [ 'wan', 'wan6' ])
			if (cur.get('network', iface))
				cur.delete('network', iface, 'disabled');
	}
	cur.commit('network');
	cur.commit('supacudy');
	run_later('/etc/init.d/network reload', 1);
	return { applied: true };
}

function wan_view(cur) {
	const s = cur.get_all('network', 'wan') ?? {};
	const dns = s.dns;
	return {
		proto: s.proto ?? 'dhcp',
		device: s.device ?? null,
		ipaddr: s.ipaddr ?? '',
		netmask: s.netmask ?? '255.255.255.0',
		gateway: s.gateway ?? '',
		dns: type(dns) == 'array' ? dns : (dns ? split(dns, ' ') : []),
		as_lan: wan_as_lan(cur),
		username: s.username ?? '',
		// The password never leaves the router; an empty one on save keeps it.
		has_password: !!s.password,
		service: s.service ?? ''
	};
}

// Drivers of the USB network devices phones create when sharing their
// connection: Android (RNDIS, CDC Ethernet/NCM) and iPhone (ipheth).
const TETHER_DRIVERS = [ 'rndis_host', 'cdc_ether', 'cdc_ncm', 'ipheth' ];

function tether_device() {
	for (let dev in lsdir('/sys/class/net') ?? []) {
		const driver = readlink(`/sys/class/net/${dev}/device/driver`);
		if (driver && (split(driver, '/')[-1] in TETHER_DRIVERS))
			return dev;
	}
	return null;
}

function tethering_status(cur) {
	const st = iface_status('tethering');
	const dev = tether_device();
	return {
		enabled: cur.get('supacudy', 'tethering', 'enabled') == '1',
		available: dev != null,
		device: dev,
		up: st?.up ?? false,
		uptime: st?.uptime ?? 0,
		...address_info(st)
	};
}

function wan_zone(cur) {
	let zone = null;
	cur.foreach('firewall', 'zone', (z) => {
		if (z.name == 'wan')
			zone ??= z['.name'];
	});
	return zone;
}

function tethering_set(req) {
	if (type(req.args.enabled) != 'bool')
		return req.error(INVALID);
	const cur = uci();
	if (!cur.get('supacudy', 'tethering'))
		cur.set('supacudy', 'tethering', 'tethering');
	cur.set('supacudy', 'tethering', 'enabled', req.args.enabled ? '1' : '0');
	const zone = wan_zone(cur);
	const networks = zone ? cur.get('firewall', zone, 'network') ?? [] : [];
	const list = type(networks) == 'array' ? networks : split(networks, ' ');
	if (req.args.enabled) {
		cur.set('network', 'tethering', 'interface');
		cur.set('network', 'tethering', 'proto', 'dhcp');
		// After Ethernet (0) and the repeater (20): the phone is the fallback.
		cur.set('network', 'tethering', 'metric', '30');
		const dev = tether_device();
		if (dev)
			cur.set('network', 'tethering', 'device', dev);
		if (zone && !('tethering' in list))
			cur.set('firewall', zone, 'network', [ ...list, 'tethering' ]);
	} else {
		cur.delete('network', 'tethering');
		if (zone && ('tethering' in list))
			cur.set('firewall', zone, 'network', filter(list, (n) => n != 'tethering'));
	}
	cur.commit('supacudy');
	cur.commit('network');
	cur.commit('firewall');
	run_later('/etc/init.d/network reload; /etc/init.d/firewall reload', 1);
	return { applied: true };
}

function status() {
	const cur = uci();
	const wan = iface_status('wan');
	const wwan = iface_status('wwan');
	const wan_conf = wan_view(cur);
	const dev = wan?.l3_device ?? wan_conf.device;
	const repeater_conf = sta_iface(cur) ? cur.get_all('wireless', 'wwan') : null;
	const link = sta_link(sta_ifname());
	const radio = repeater_conf ? cur.get_all('wireless', repeater_conf.device) : null;

	return {
		active: default_route_iface(),
		internet: internet_reachable(),
		ethernet: {
			configured: cur.get('network', 'wan') != null,
			carrier: dev ? carrier(replace(dev, /^pppoe-/, '')) || (wan?.up ?? false) : false,
			up: wan?.up ?? false,
			proto: wan_conf.proto,
			uptime: wan?.uptime ?? 0,
			...address_info(wan)
		},
		repeater: {
			configured: repeater_conf != null,
			enabled: repeater_conf != null && repeater_conf.disabled != '1',
			ssid: repeater_conf?.ssid ?? null,
			band: radio?.band ?? null,
			connected: link != null,
			bssid: link?.bssid ?? null,
			signal: link?.signal ?? null,
			up: wwan?.up ?? false,
			uptime: wwan?.uptime ?? 0,
			...address_info(wwan)
		},
		tethering: tethering_status(cur),
		time: uptime()
	};
}

function validate_ipv4_list(list) {
	for (let ip in list)
		if (ipv4_to_int(ip) == null)
			return false;
	return true;
}

function wan_set(req) {
	const a = req.args;
	if (!(a.proto in PROTOS) || type(a.dns) != 'array' || !validate_ipv4_list(a.dns) || length(a.dns) > 4)
		return req.error(INVALID);
	const cur = uci();
	if (!cur.get('network', 'wan'))
		return req.error(NOT_FOUND);

	if (a.proto == 'static') {
		const prefix = parse_netmask(a.netmask);
		const net = subnet(a.ipaddr, prefix);
		const gw = ipv4_to_int(a.gateway);
		if (!net || prefix < 8 || prefix > 30 || net.address == net.network || net.address == net.broadcast)
			return fail('invalid_address');
		if (gw == null || gw <= net.network || gw >= net.broadcast || gw == net.address)
			return fail('gateway_outside');
		const lan = subnet(cur.get('network', 'lan', 'ipaddr'), parse_netmask(cur.get('network', 'lan', 'netmask') ?? '24'));
		if (lan && net.network <= lan.broadcast && lan.network <= net.broadcast)
			return fail('subnet_conflict', { with: 'lan' });
	}
	if (a.proto == 'pppoe' && (length(a.username) < 1 || length(a.username) > 128 || length(a.password) > 128 ||
	    match(a.username, /[[:cntrl:]]/) || match(a.password, /[[:cntrl:]]/)))
		return fail('pppoe_credentials');

	const old_password = cur.get('network', 'wan', 'proto') == 'pppoe' ? cur.get('network', 'wan', 'password') : null;
	for (let o in ['ipaddr', 'netmask', 'gateway', 'username', 'password', 'service'])
		cur.delete('network', 'wan', o);
	cur.set('network', 'wan', 'proto', a.proto);
	if (a.proto == 'static') {
		cur.set('network', 'wan', 'ipaddr', a.ipaddr);
		cur.set('network', 'wan', 'netmask', int_to_ipv4(prefix_to_mask(parse_netmask(a.netmask))));
		cur.set('network', 'wan', 'gateway', a.gateway);
	} else if (a.proto == 'pppoe') {
		cur.set('network', 'wan', 'username', a.username);
		cur.set('network', 'wan', 'password', a.password != '' ? a.password : (old_password ?? ''));
	}
	if (length(a.dns)) {
		cur.set('network', 'wan', 'dns', a.dns);
		cur.set('network', 'wan', 'peerdns', '0');
	} else {
		cur.delete('network', 'wan', 'dns');
		cur.delete('network', 'wan', 'peerdns');
	}
	cur.commit('network');
	run_later('ifup wan', 1);
	return { applied: true };
}

function encryption_of(bss) {
	let akms = [];
	let wpa1 = false;
	for (let ie in bss.information_elements ?? []) {
		if (ie.type == 48 && length(ie.data) >= 8) {
			// RSN: version(2) group(4) pairwise count(2) suites(4n) akm count(2) suites(4n)
			const pc = ord(ie.data, 6) | (ord(ie.data, 7) << 8);
			const ak_off = 8 + 4 * pc;
			const ac = ord(ie.data, ak_off) | (ord(ie.data, ak_off + 1) << 8);
			for (let i = 0; i < ac; i++)
				push(akms, ord(ie.data, ak_off + 2 + 4 * i + 3));
		}
		if (ie.type == 221 && substr(ie.data, 0, 4) == '\x00\x50\xf2\x01')
			wpa1 = true;
	}
	const has = (n) => n in akms;
	if (has(1) || has(5))
		return 'enterprise';
	if (has(8) && (has(2) || has(6)))
		return 'sae-mixed';
	if (has(8))
		return 'sae';
	if (has(18))
		return 'owe';
	if (has(2) || has(6))
		return wpa1 ? 'psk-mixed' : 'psk2';
	if (wpa1)
		return 'psk-mixed';
	return (bss.capability & 0x10) ? 'wep' : 'none';
}

function ssid_of(bss) {
	for (let ie in bss.information_elements ?? [])
		if (ie.type == 0)
			return ie.data;
	return '';
}

function scan_devices() {
	const out = [];
	const radios = ubus().call('network.wireless', 'status') ?? {};
	for (let name, radio in radios) {
		const dev = radio.interfaces?.[0]?.ifname;
		if (dev && radio.up)
			push(out, dev);
	}
	return out;
}

function repeater_scan() {
	const devices = scan_devices();
	for (let dev in devices)
		nl80211.request(nl80211.const.NL80211_CMD_TRIGGER_SCAN, 0, { dev });
	sleep(SCAN_WAIT_MS);

	const cur = uci();
	const saved = {};
	for (let s in saved_networks(cur))
		saved[s.ssid] = true;
	const own = {};
	cur.foreach('wireless', 'wifi-iface', (s) => {
		if (s.mode == 'ap' && s.ssid)
			own[s.ssid] = true;
	});
	// Also by address: a network renamed or removed a moment ago still sits
	// in the kernel's scan cache under its old name.
	for (let i in nl80211.request(nl80211.const.NL80211_CMD_GET_INTERFACE, nl80211.const.NLM_F_DUMP) ?? [])
		if (i.mac)
			own[lc(i.mac)] = true;
	const current = cur.get('wireless', 'wwan', 'ssid');

	const seen = {};
	const out = [];
	for (let dev in devices) {
		for (let r in nl80211.request(nl80211.const.NL80211_CMD_GET_SCAN, nl80211.const.NLM_F_DUMP, { dev }) ?? []) {
			const bss = r.bss;
			const ssid = ssid_of(bss);
			// Hidden networks and the router's own networks are not offered.
			if (!bss?.bssid || seen[bss.bssid] || ssid == '' || own[ssid] || own[lc(bss.bssid)])
				continue;
			// Cached from an earlier scan: the network may be gone.
			if (bss.seen_ms_ago != null && bss.seen_ms_ago > SCAN_WAIT_MS + 2000)
				continue;
			seen[bss.bssid] = true;
			push(out, {
				ssid,
				bssid: bss.bssid,
				band: BAND_OF(bss.frequency),
				channel: channel_of(bss.frequency),
				signal: bss.signal_mbm != null ? int(bss.signal_mbm / 100) : null,
				encryption: encryption_of(bss),
				saved: !!saved[ssid],
				current: ssid == current
			});
		}
	}
	return { networks: sort(out, (a, b) => (b.signal ?? -999) - (a.signal ?? -999)) };
}

function radio_for_band(cur, band) {
	let found = null;
	let fallback = null;
	cur.foreach('wireless', 'wifi-device', (s) => {
		if (s.disabled == '1')
			return;
		fallback ??= s['.name'];
		if (!found && s.band == band)
			found = s['.name'];
	});
	return found ?? fallback;
}

function ensure_wwan(cur) {
	if (!cur.get('network', 'wwan')) {
		cur.set('network', 'wwan', 'interface');
		cur.set('network', 'wwan', 'proto', 'dhcp');
		// Ethernet stays preferred while both are up.
		cur.set('network', 'wwan', 'metric', '20');
	}
	cur.foreach('firewall', 'zone', (z) => {
		if (z.name != 'wan')
			return;
		const nets = type(z.network) == 'array' ? z.network : split(z.network ?? '', ' ');
		if (!('wwan' in nets))
			cur.set('firewall', z['.name'], 'network', [...nets, 'wwan']);
	});
}

function remember(cur, ssid, encryption, key) {
	let section = null;
	cur.foreach('supacudy', 'repeater', (s) => {
		if (s.ssid == ssid)
			section = s['.name'];
	});
	section ??= cur.add('supacudy', 'repeater');
	cur.set('supacudy', section, 'ssid', ssid);
	cur.set('supacudy', section, 'encryption', encryption);
	if (encryption == 'none' || encryption == 'owe')
		cur.delete('supacudy', section, 'key');
	else
		cur.set('supacudy', section, 'key', key);
	cur.set('supacudy', section, 'last_used', `${time()}`);
}

// Joining takes a while (wifi reload, scan, auth, DHCP); without a grace
// period the tick would treat a fresh join as a lost network. The emulator
// tests shorten it through supacudy.main.repeater_grace.
const SWITCH_GRACE = 60;

function switch_grace(cur) {
	const g = +(cur.get('supacudy', 'main', 'repeater_grace') ?? SWITCH_GRACE);
	return g >= 5 && g <= 600 ? g : SWITCH_GRACE;
}
let last_change = 0;
let down_since = null;

function connect(cur, ssid, encryption, key, band, bssid) {
	last_change = uptime();
	down_since = null;
	const radio = radio_for_band(cur, band);
	if (!radio)
		return 'no_radio';
	ensure_wwan(cur);
	if (!cur.get('wireless', 'wwan'))
		cur.set('wireless', 'wwan', 'wifi-iface');
	cur.set('wireless', 'wwan', 'device', radio);
	cur.set('wireless', 'wwan', 'mode', 'sta');
	cur.set('wireless', 'wwan', 'network', 'wwan');
	cur.set('wireless', 'wwan', 'ssid', ssid);
	cur.set('wireless', 'wwan', 'encryption', encryption);
	if (encryption == 'none' || encryption == 'owe')
		cur.delete('wireless', 'wwan', 'key');
	else
		cur.set('wireless', 'wwan', 'key', key);
	if (bssid)
		cur.set('wireless', 'wwan', 'bssid', bssid);
	else
		cur.delete('wireless', 'wwan', 'bssid');
	cur.set('wireless', 'wwan', 'disabled', '0');
	if (cur.get('supacudy', 'main', 'repeater_20mhz') == '1' && cur.get('wireless', radio, 'band') == '2g')
		cur.set('wireless', radio, 'htmode', replace(cur.get('wireless', radio, 'htmode') ?? 'HT20', /\d+$/, '20'));
	return null;
}

function repeater_connect(req) {
	const a = req.args;
	if (type(a.ssid) != 'string' || length(a.ssid) < 1 || length(a.ssid) > 32 || !(a.encryption in STA_ENCRYPTIONS) ||
	    type(a.key) != 'string' || type(a.save) != 'bool' || !(a.band in ['2g', '5g', '6g', '']) ||
	    (a.bssid != '' && !match(a.bssid, /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/)))
		return req.error(INVALID);

	const cur = uci();
	let key = a.key;
	// Reconnecting to a saved network without retyping its password.
	if (key == '' && a.encryption != 'none' && a.encryption != 'owe')
		for (let s in saved_networks(cur))
			if (s.ssid == a.ssid)
				key = s.key;
	if (a.encryption != 'none' && a.encryption != 'owe' && (length(key) < 8 || length(key) > 63))
		return fail('key_invalid');

	const problem = connect(cur, a.ssid, a.encryption, key, a.band, lc(a.bssid));
	if (problem)
		return fail(problem);
	if (a.save)
		remember(cur, a.ssid, a.encryption, key);
	cur.commit('wireless');
	cur.commit('network');
	cur.commit('firewall');
	cur.commit('supacudy');
	run_later('/etc/init.d/network reload; /etc/init.d/firewall reload; wifi reload', 1);
	return { applied: true };
}

function repeater_disconnect() {
	const cur = uci();
	if (!cur.get('wireless', 'wwan'))
		return { applied: true };
	cur.set('wireless', 'wwan', 'disabled', '1');
	cur.commit('wireless');
	run_later('wifi reload', 1);
	return { applied: true };
}

function repeater_saved() {
	const cur = uci();
	return {
		networks: map(saved_networks(cur), (s) => ({ ssid: s.ssid, encryption: s.encryption, last_used: s.last_used })),
		auto_switch: cur.get('supacudy', 'main', 'repeater_auto_switch') != '0',
		force_20mhz: cur.get('supacudy', 'main', 'repeater_20mhz') == '1'
	};
}

function repeater_forget(req) {
	if (type(req.args.ssid) != 'string')
		return req.error(INVALID);
	const cur = uci();
	let found = null;
	for (let s in saved_networks(cur))
		if (s.ssid == req.args.ssid)
			found = s.id;
	if (!found)
		return req.error(NOT_FOUND);
	cur.delete('supacudy', found);
	cur.commit('supacudy');
	return { forgotten: true };
}

function repeater_options(req) {
	const a = req.args;
	if (type(a.auto_switch) != 'bool' || type(a.force_20mhz) != 'bool')
		return req.error(INVALID);
	const cur = uci();
	cur.set('supacudy', 'main', 'repeater_auto_switch', a.auto_switch ? '1' : '0');
	cur.set('supacudy', 'main', 'repeater_20mhz', a.force_20mhz ? '1' : '0');
	cur.commit('supacudy');
	return { auto_switch: a.auto_switch, force_20mhz: a.force_20mhz };
}

// Called periodically by the supacudy-repeater service: when the repeater
// has lost its network, switch to the strongest other saved network in range.
function repeater_tick() {
	const cur = uci();
	if (cur.get('supacudy', 'main', 'repeater_auto_switch') == '0' || !cur.get('wireless', 'wwan') ||
	    cur.get('wireless', 'wwan', 'disabled') == '1')
		return { action: 'idle' };
	if (sta_link(sta_ifname())) {
		down_since = null;
		return { action: 'connected' };
	}
	const now = uptime();
	if (down_since == null)
		down_since = now;
	const grace = switch_grace(cur);
	if (now - last_change < grace || now - down_since < grace)
		return { action: 'waiting' };

	const saved = {};
	for (let s in saved_networks(cur))
		saved[s.ssid] = s;
	const current = cur.get('wireless', 'wwan', 'ssid');
	for (let n in repeater_scan().networks) {
		if (!saved[n.ssid] || n.ssid == current)
			continue;
		const s = saved[n.ssid];
		connect(cur, s.ssid, s.encryption, s.key, n.band, '');
		remember(cur, s.ssid, s.encryption, s.key);
		cur.commit('wireless');
		cur.commit('network');
		cur.commit('firewall');
		cur.commit('supacudy');
		run_later('wifi reload', 0);
		return { action: 'switched', ssid: s.ssid };
	}
	return { action: 'waiting' };
}

const methods = {
	internet_status: { call: status },
	wan_get: {
		call: function() {
			return wan_view(uci());
		}
	},
	wan_set: {
		args: { proto: '', ipaddr: '', netmask: '', gateway: '', dns: [], username: '', password: '' },
		call: wan_set
	},
	repeater_scan: { call: repeater_scan },
	repeater_connect: {
		args: { ssid: '', bssid: '', encryption: '', key: '', band: '', save: false },
		call: repeater_connect
	},
	repeater_disconnect: { call: repeater_disconnect },
	repeater_saved: { call: repeater_saved },
	repeater_forget: {
		args: { ssid: '' },
		call: repeater_forget
	},
	repeater_options: {
		args: { auto_switch: false, force_20mhz: false },
		call: repeater_options
	},
	repeater_tick: { call: repeater_tick },
	tethering_set: { args: { enabled: false }, call: tethering_set },
	wan_port_set: { args: { as_lan: false }, call: wan_port_set }
};

export { methods, status };
