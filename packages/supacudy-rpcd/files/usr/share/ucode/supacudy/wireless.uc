// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Wi-Fi radios, the main network on each radio and the guest networks.

'use strict';

import { dns_option } from 'supacudy.adguard';
import { glob } from 'fs';
import * as nl80211 from 'nl80211';
import {
	INVALID, NOT_FOUND, uci, run, run_later, fail, subnet, overlaps, int_to_ipv4
} from 'supacudy.util';
import { network_subnet, other_subnets } from 'supacudy.lan';

const ENCRYPTIONS = ['sae-mixed', 'psk2', 'sae', 'psk-mixed', 'none'];
const TX_STEPS = { max: 0, high: 3, medium: 6, low: 10 };
const BAND_RANGES = {
	'2g': [2400, 2500],
	'5g': [5100, 5900],
	'6g': [5925, 7125]
};

function supported_encryptions() {
	const sae = run('hostapd -vsae').code == 0;
	return filter(ENCRYPTIONS, (e) => sae || !match(e, /^sae/));
}

// OpenWrt names a radio by its device path; dual-band chips expose one
// phy per band under the same path, addressed as "path+1".
function phy_for(path) {
	if (!path)
		return null;
	const m = match(path, /^(.*)\+(\d+)$/);
	const base = m ? m[1] : path;
	const index = m ? +m[2] : 0;
	const phys = sort(map(glob(`/sys/devices/${base}/ieee80211/*`) ?? [], (p) => replace(p, /.*\//, '')));
	return phys[index] ?? null;
}

function freq_to_channel(freq) {
	if (freq == 2484)
		return 14;
	if (freq >= 2412 && freq <= 2472)
		return (freq - 2407) / 5;
	if (freq >= 5955 && freq <= 7115)
		return (freq - 5950) / 5;
	if (freq >= 5000 && freq <= 5900)
		return (freq - 5000) / 5;
	return null;
}

function capabilities(phy, band) {
	const out = { channels: [], powers: {}, he: false, vht: false, vht160: false };
	if (!phy)
		return out;
	const wiphys = nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, nl80211.const.NLM_F_DUMP, { split_wiphy_dump: true }) ?? [];
	const range = BAND_RANGES[band];
	for (let w in wiphys) {
		if (w.wiphy_name != phy)
			continue;
		out.index = w.wiphy;
		for (let b in w.wiphy_bands ?? []) {
			if (!b?.freqs?.[0] || b.freqs[0].freq < range[0] || b.freqs[0].freq > range[1])
				continue;
			out.he ||= length(b.iftype_data ?? []) > 0;
			out.vht ||= !!b.vht_capa;
			out.vht160 ||= !!b.vht_capa && ((b.vht_capa >> 2) & 3) != 0;
			// "no_ir" channels (radar or regulatory) cannot be used to start a network.
			for (let f in b.freqs) {
				if (f.disabled || f.no_ir)
					continue;
				const ch = freq_to_channel(f.freq);
				if (ch != null && !(ch in out.channels))
					push(out.channels, ch);
				if (f.max_tx_power)
					out.powers[ch] = f.max_tx_power / 100;
			}
		}
	}
	return out;
}

// Channel blocks a wide channel must fit in, by the first channel of each.
const BLOCKS_40 = [36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157];
const BLOCKS_80 = [36, 52, 100, 116, 132, 149];
const BLOCKS_160 = [36, 100];
const BLOCKS = { '40': BLOCKS_40, '80': BLOCKS_80, '160': BLOCKS_160 };

function has_block(channels, starts, count) {
	for (let first in starts) {
		let complete = true;
		for (let i = 0; i < count; i++)
			if (!((first + i * 4) in channels))
				complete = false;
		if (complete)
			return true;
	}
	return false;
}

// A wide channel needs every channel of its block, which some regulatory
// domains allow on one block only (CN: 160 MHz on 36-64, not on 149).
function width_fits(band, channels, channel, width) {
	if (width == 20 || band == '2g')
		return true;
	const count = width / 20;
	for (let first in BLOCKS[`${width}`] ?? []) {
		const inside = channel == 'auto' || (channel >= first && channel < first + 4 * count);
		if (inside && has_block(channels, [ first ], count))
			return true;
	}
	return false;
}

// Limits differ per channel (CN: 23 dBm on 36-48, 33 dBm on 149-165); with
// automatic channel selection the lowest one applies.
function channel_power(caps, channel) {
	const limit = caps.powers[channel];
	if (limit != null)
		return limit;
	const all = values(caps.powers);
	return length(all) ? min(...all) : 20;
}

// Only widths that can actually be used with the channels the regulatory
// domain allows here.
function widths_for(band, caps) {
	if (band == '2g')
		return length(caps.channels) >= 5 ? [20, 40] : [20];
	const out = [20];
	if (length(caps.channels) >= 2)
		push(out, 40);
	if ((caps.vht || caps.he) && has_block(caps.channels, BLOCKS_80, 4))
		push(out, 80);
	if (caps.vht160 && has_block(caps.channels, BLOCKS_160, 8))
		push(out, 160);
	return out;
}

function htmode_prefix(band, caps) {
	if (caps.he)
		return 'HE';
	return band == '2g' ? 'HT' : (caps.vht ? 'VHT' : 'HT');
}

function width_of(htmode) {
	const m = match(htmode ?? '', /(\d+)$/);
	return m ? +m[1] : 20;
}

function distance(a, b) {
	return a > b ? a - b : b - a;
}

function txpower_level(value, max_power) {
	if (value == null || value == '')
		return 'max';
	const step = max_power - +value;
	let best = 'max';
	for (let name, s in TX_STEPS)
		if (distance(step, s) < distance(step, TX_STEPS[best]))
			best = name;
	return best;
}

function iface_for(cur, radio, network, mode) {
	let found = null;
	cur.foreach('wireless', 'wifi-iface', (s) => {
		if (found || s.device != radio || (s.mode ?? 'ap') != mode)
			return;
		const nets = type(s.network) == 'array' ? s.network : split(s.network ?? '', ' ');
		if (network == null ? !('guest' in nets) : (network in nets))
			found = s['.name'];
	});
	return found;
}

function network_view(cur, section) {
	if (!section)
		return null;
	const s = cur.get_all('wireless', section);
	return {
		enabled: s.disabled != '1',
		ssid: s.ssid ?? '',
		encryption: (s.encryption ?? 'none') in ENCRYPTIONS ? s.encryption : 'psk2',
		key: s.key ?? '',
		hidden: s.hidden == '1'
	};
}

function radio_locked(cur, radio) {
	let locked = null;
	cur.foreach('wireless', 'wifi-iface', (s) => {
		if (s.device == radio && s.mode == 'sta' && s.disabled != '1')
			locked = 'repeater';
	});
	return locked;
}

// A station on the radio makes it follow the upstream channel, so the
// configured one is not what the radio actually uses.
function operating_channel(index) {
	if (index == null)
		return null;
	for (let i in nl80211.request(nl80211.const.NL80211_CMD_GET_INTERFACE, nl80211.const.NLM_F_DUMP) ?? [])
		if (i.wiphy == index && i.wiphy_freq)
			return freq_to_channel(i.wiphy_freq);
	return null;
}

function radio_view(cur, s, encryptions) {
	const band = s.band ?? (s.hwmode == '11a' ? '5g' : '2g');
	const caps = capabilities(phy_for(s.path), band);
	const main = iface_for(cur, s['.name'], null, 'ap');
	const guest = iface_for(cur, s['.name'], 'guest', 'ap');
	const locked = radio_locked(cur, s['.name']);
	return {
		name: s['.name'],
		band,
		enabled: s.disabled != '1',
		channel: (locked ? operating_channel(caps.index) : null) ??
			((s.channel == null || s.channel == 'auto') ? 'auto' : +s.channel),
		channels: caps.channels,
		width: width_of(s.htmode),
		widths: widths_for(band, caps),
		txpower: txpower_level(s.txpower, channel_power(caps, +s.channel)),
		locked,
		encryptions,
		main: network_view(cur, main) ?? { enabled: false, ssid: '', encryption: 'psk2', key: '', hidden: false },
		guest: network_view(cur, guest)
	};
}

function wifi_get() {
	const cur = uci();
	const encryptions = supported_encryptions();
	const radios = [];
	cur.foreach('wireless', 'wifi-device', (s) => {
		// Config can outlive the hardware (a removed USB adapter, or the
		// emulator's radios that were moved away); only list real radios.
		if (phy_for(s.path))
			push(radios, radio_view(cur, s, encryptions));
	});
	const guest = network_subnet(cur, 'guest');
	return {
		radios: sort(radios, (a, b) => a.band < b.band ? -1 : (a.band > b.band ? 1 : 0)),
		guest_subnet: guest ? `${int_to_ipv4(guest.network)}/${guest.prefix}` : null
	};
}

function validate_network(a, encryptions) {
	if (type(a.ssid) != 'string' || type(a.key) != 'string' || type(a.hidden) != 'bool' || type(a.enabled) != 'bool' ||
	    !(a.encryption in ENCRYPTIONS))
		return 'invalid';
	if (!(a.encryption in encryptions))
		return 'encryption_unsupported';
	if (length(a.ssid) < 1 || length(a.ssid) > 32)
		return 'ssid_length';
	if (a.encryption != 'none' && (length(a.key) < 8 || length(a.key) > 63 || !match(a.key, /^[ -~]+$/)))
		return 'key_invalid';
	return null;
}

function write_network(cur, section, a) {
	cur.set('wireless', section, 'ssid', a.ssid);
	cur.set('wireless', section, 'encryption', a.encryption);
	if (a.encryption == 'none')
		cur.delete('wireless', section, 'key');
	else
		cur.set('wireless', section, 'key', a.key);
	cur.set('wireless', section, 'hidden', a.hidden ? '1' : '0');
	// WPA3-only and mixed modes need management frame protection.
	if (a.encryption == 'sae')
		cur.set('wireless', section, 'ieee80211w', '2');
	else if (a.encryption == 'sae-mixed')
		cur.set('wireless', section, 'ieee80211w', '1');
	else
		cur.delete('wireless', section, 'ieee80211w');
}

function wifi_set(req) {
	const a = req.args;
	const cur = uci();
	const radio = cur.get_all('wireless', a.radio ?? '');
	if (!radio || radio['.type'] != 'wifi-device')
		return req.error(NOT_FOUND);
	if (type(a.channel) != 'string' || type(a.width) != 'int' || !(a.txpower in keys(TX_STEPS)))
		return req.error(INVALID);
	const encryptions = supported_encryptions();
	const problem = a.enabled ? validate_network(a, encryptions) : (type(a.enabled) == 'bool' ? null : 'invalid');
	if (problem == 'invalid')
		return req.error(INVALID);
	if (problem)
		return fail(problem);

	const view = radio_view(cur, radio, encryptions);
	const channel = a.channel == 'auto' ? 'auto' : +a.channel;
	const locked = view.locked != null;
	if (!locked && channel != 'auto' && !(channel in view.channels))
		return fail('channel_unavailable');
	if (!locked && (!(a.width in view.widths) || !width_fits(view.band, view.channels, channel, a.width)))
		return fail('width_unavailable');

	cur.set('wireless', a.radio, 'disabled', a.enabled ? '0' : '1');
	if (!locked) {
		cur.set('wireless', a.radio, 'channel', `${channel}`);
		const caps = capabilities(phy_for(radio.path), view.band);
		cur.set('wireless', a.radio, 'htmode', htmode_prefix(view.band, caps) + a.width);
	}
	if (a.txpower == 'max')
		cur.delete('wireless', a.radio, 'txpower');
	else
		cur.set('wireless', a.radio, 'txpower', `${int(channel_power(capabilities(phy_for(radio.path), view.band), locked ? view.channel : channel) - TX_STEPS[a.txpower])}`);

	let main = iface_for(cur, a.radio, null, 'ap');
	if (!main) {
		main = `default_${a.radio}`;
		cur.set('wireless', main, 'wifi-iface');
		cur.set('wireless', main, 'device', a.radio);
		cur.set('wireless', main, 'network', 'lan');
		cur.set('wireless', main, 'mode', 'ap');
	}
	if (a.enabled) {
		cur.set('wireless', main, 'disabled', '0');
		write_network(cur, main, a);
	}
	cur.commit('wireless');
	run_later('wifi reload', 1);
	return { applied: true };
}

// Picks a /24 for the guest network next to the LAN (192.168.1.0 -> .2.0),
// skipping anything already in use.
function choose_guest_subnet(cur) {
	const lan = network_subnet(cur, 'lan');
	const used = map(other_subnets(cur, 'guest'), (o) => o.net);
	const base = lan ? (lan.network >> 8) & 0xffffff : 0xc0a801;
	for (let i = 1; i < 255; i++) {
		const candidate = subnet(int_to_ipv4(((base + i) << 8) | 1), 24);
		if (candidate && !length(filter(used, (u) => overlaps(u, candidate))))
			return candidate;
	}
	return null;
}

function ensure_guest_network(cur) {
	if (cur.get('network', 'guest'))
		return network_subnet(cur, 'guest');

	const net = choose_guest_subnet(cur);
	if (!net)
		return null;

	cur.set('network', 'guest_dev', 'device');
	cur.set('network', 'guest_dev', 'name', 'br-guest');
	cur.set('network', 'guest_dev', 'type', 'bridge');
	cur.set('network', 'guest_dev', 'bridge_empty', '1');
	cur.set('network', 'guest', 'interface');
	cur.set('network', 'guest', 'device', 'br-guest');
	cur.set('network', 'guest', 'proto', 'static');
	cur.set('network', 'guest', 'ipaddr', int_to_ipv4(net.network + 1));
	cur.set('network', 'guest', 'netmask', '255.255.255.0');

	cur.set('dhcp', 'guest', 'dhcp');
	cur.set('dhcp', 'guest', 'interface', 'guest');
	cur.set('dhcp', 'guest', 'start', '100');
	cur.set('dhcp', 'guest', 'limit', '150');
	cur.set('dhcp', 'guest', 'leasetime', '2h');
	dns_option(cur, 'guest');

	// Guests get the internet and the router's DHCP/DNS, nothing else.
	cur.set('firewall', 'guest_zone', 'zone');
	cur.set('firewall', 'guest_zone', 'name', 'guest');
	cur.set('firewall', 'guest_zone', 'network', ['guest']);
	cur.set('firewall', 'guest_zone', 'input', 'REJECT');
	cur.set('firewall', 'guest_zone', 'output', 'ACCEPT');
	cur.set('firewall', 'guest_zone', 'forward', 'REJECT');
	cur.set('firewall', 'guest_wan', 'forwarding');
	cur.set('firewall', 'guest_wan', 'src', 'guest');
	cur.set('firewall', 'guest_wan', 'dest', 'wan');
	cur.set('firewall', 'guest_dhcp', 'rule');
	cur.set('firewall', 'guest_dhcp', 'name', 'Allow-Guest-DHCP');
	cur.set('firewall', 'guest_dhcp', 'src', 'guest');
	cur.set('firewall', 'guest_dhcp', 'proto', 'udp');
	cur.set('firewall', 'guest_dhcp', 'dest_port', '67-68');
	cur.set('firewall', 'guest_dhcp', 'target', 'ACCEPT');
	cur.set('firewall', 'guest_dns', 'rule');
	cur.set('firewall', 'guest_dns', 'name', 'Allow-Guest-DNS');
	cur.set('firewall', 'guest_dns', 'src', 'guest');
	cur.set('firewall', 'guest_dns', 'proto', 'tcp udp');
	cur.set('firewall', 'guest_dns', 'dest_port', '53');
	cur.set('firewall', 'guest_dns', 'target', 'ACCEPT');

	cur.commit('network');
	cur.commit('dhcp');
	cur.commit('firewall');
	return net;
}

function guest_set(req) {
	const a = req.args;
	const cur = uci();
	const radio = cur.get_all('wireless', a.radio ?? '');
	if (!radio || radio['.type'] != 'wifi-device')
		return req.error(NOT_FOUND);
	if (type(a.enabled) != 'bool')
		return req.error(INVALID);
	if (a.enabled) {
		const problem = validate_network(a, supported_encryptions());
		if (problem == 'invalid')
			return req.error(INVALID);
		if (problem)
			return fail(problem);
	}

	let section = iface_for(cur, a.radio, 'guest', 'ap');
	if (!section && !a.enabled)
		return { applied: true, subnet: null };

	const net = ensure_guest_network(cur);
	if (!net)
		return fail('no_free_subnet');

	if (!section) {
		section = `guest_${a.radio}`;
		cur.set('wireless', section, 'wifi-iface');
		cur.set('wireless', section, 'device', a.radio);
		cur.set('wireless', section, 'network', 'guest');
		cur.set('wireless', section, 'mode', 'ap');
		cur.set('wireless', section, 'isolate', '1');
	}
	cur.set('wireless', section, 'disabled', a.enabled ? '0' : '1');
	if (a.enabled)
		write_network(cur, section, a);
	cur.commit('wireless');

	run_later('/etc/init.d/network reload; /etc/init.d/firewall reload; /etc/init.d/dnsmasq reload; wifi reload', 1);
	return { applied: true, subnet: `${int_to_ipv4(net.network)}/${net.prefix}` };
}

const NETWORK_ARGS = { radio: '', enabled: false, ssid: '', encryption: '', key: '', hidden: false };

const methods = {
	wifi_get: {
		call: wifi_get
	},
	wifi_set: {
		args: { ...NETWORK_ARGS, channel: '', width: 0, txpower: '' },
		call: wifi_set
	},
	guest_set: {
		args: NETWORK_ARGS,
		call: guest_set
	}
};

export { methods };
