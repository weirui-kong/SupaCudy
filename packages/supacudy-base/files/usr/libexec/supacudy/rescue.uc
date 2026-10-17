// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rescue mode: when nobody could get an address from the router (its LAN
// DHCP is off, e.g. in access point mode, and no other DHCP server answers)
// or nobody could even connect (no access point up and no cable plugged
// in), bring up a way in: an extra address with its own DHCP server, an
// open "SupaCudy-Rescue" network, and a blinking LED.
//
// The same watcher keeps DNS working when AdGuard Home, the router's DNS
// on port 53, has stopped: a plain forwarder to dnsmasq (port 5353) takes
// its place, and AdGuard Home is retried every few minutes.
//
// Everything is runtime only: nothing is written to /etc/config, so the
// next boot starts from the user's settings and checks again. Called every
// 30 s by rescue-watch; "stop" tears rescue mode down.
//
//   ucode /usr/libexec/supacudy/rescue.uc [stop]

'use strict';

import { cursor } from 'uci';
import { readfile, writefile, readlink, lsdir, unlink, mkdir, popen } from 'fs';
import * as nl80211 from 'nl80211';

const RUN = '/var/run/supacudy';
const STATE = `${RUN}/rescue.json`;
const DNSMASQ_PID = `${RUN}/rescue-dnsmasq.pid`;
const HOSTAPD_PID = `${RUN}/rescue-hostapd.pid`;
const HOSTAPD_CONF = `${RUN}/rescue-hostapd.conf`;
const PROBE_RESULT = `${RUN}/dhcp-server`;
const BRIDGE = 'br-lan';
const VIF = 'sc-rescue';
const SSID = 'SupaCudy-Rescue';
// Consecutive 30 s checks before acting: a reboot of the main router or a
// cable being swapped should not trigger it.
const DHCP_MISSES = 2;
const WIFI_MISSES = 3;
const CLEAR_TICKS = 2;
const BOOT_GRACE_S = 120;
const NL80211_IFTYPE_AP = 3;
const DNS_PID = `${RUN}/dns-fallback.pid`;
const ADGUARD_PID = '/run/adguardhome.pid';
const DNS_MISSES = 2;
// Ticks (of 30 s) between attempts to bring AdGuard Home back.
const DNS_RETRY_TICKS = 10;

function sh(cmd) {
	const p = popen(`${cmd} 2>&1`);
	if (!p)
		return { code: -1, out: '' };
	const out = p.read('all') ?? '';
	return { code: p.close(), out };
}

function load() {
	try {
		return json(readfile(STATE) ?? '{}');
	} catch {
		return {};
	}
}

function save(s) {
	mkdir(RUN);
	writefile(STATE, sprintf('%J', s));
}

function uptime() {
	return +split(readfile('/proc/uptime') ?? '0', ' ')[0];
}

function pid_of(file) {
	const p = trim(readfile(file) ?? '');
	return match(p, /^[0-9]+$/) ? p : null;
}

function alive(file) {
	const p = pid_of(file);
	return p != null && readfile(`/proc/${p}/stat`) != null;
}

// Our own DHCP server is paused while probing so only others can answer.
function dhcp_server_found(rescue_running) {
	const own = rescue_running ? pid_of(DNSMASQ_PID) : null;
	unlink(PROBE_RESULT);
	if (own)
		sh(`kill -STOP ${own}`);
	sh(`udhcpc -i ${BRIDGE} -n -q -f -t 2 -T 2 -s /usr/libexec/supacudy/dhcp-probe`);
	if (own)
		sh(`kill -CONT ${own}`);
	return trim(readfile(PROBE_RESULT) ?? '') != '';
}

function lan_dhcp_off(cur) {
	return cur.get('dhcp', 'lan', 'ignore') == '1';
}

function user_ap_up() {
	for (let i in nl80211.request(nl80211.const.NL80211_CMD_GET_INTERFACE, nl80211.const.NLM_F_DUMP) ?? [])
		if (i.iftype == NL80211_IFTYPE_AP && i.ifname != VIF && trim(readfile(`/sys/class/net/${i.ifname}/operstate`) ?? '') == 'up')
			return true;
	return false;
}

// A cable in any wired LAN port (wireless members of the bridge excluded).
function lan_cable() {
	for (let port in lsdir(`/sys/class/net/${BRIDGE}/brif`) ?? []) {
		if (readlink(`/sys/class/net/${port}/phy80211`))
			continue;
		if (trim(readfile(`/sys/class/net/${port}/carrier`) ?? '0') == '1')
			return true;
	}
	return false;
}

// First of 192.168.200.0/24, 192.168.201.0/24, ... not used on the router.
function rescue_subnet() {
	const used = {};
	for (let l in split(sh('ip -4 -o addr show').out, '\n')) {
		const m = match(l, /inet 192\.168\.([0-9]+)\./);
		if (m)
			used[m[1]] = true;
	}
	for (let n = 200; n < 255; n++)
		if (!used[`${n}`])
			return `192.168.${n}`;
	return null;
}

function start_dhcp(s) {
	const net = rescue_subnet();
	if (!net)
		return false;
	const addr = `${net}.1`;
	sh(`ip addr add ${addr}/24 dev ${BRIDGE} label ${BRIDGE}:rescue`);
	// Its own instance, bound only to the bridge, next to the system's.
	sh(`dnsmasq --conf-file=/dev/null --port=0 --bind-interfaces --interface=${BRIDGE} --except-interface=lo ` +
		`--dhcp-range=${net}.100,${net}.199,255.255.255.0,2m --dhcp-option=3,${addr} --dhcp-option=6,${addr} ` +
		`--dhcp-leasefile=${RUN}/rescue.leases --pid-file=${DNSMASQ_PID}`);
	s.dhcp = { address: addr };
	return true;
}

function stop_dhcp(s) {
	const p = pid_of(DNSMASQ_PID);
	if (p)
		sh(`kill ${p}`);
	unlink(DNSMASQ_PID);
	if (s.dhcp?.address && match(s.dhcp.address, /^192\.168\.[0-9]+\.1$/))
		sh(`ip addr del ${s.dhcp.address}/24 dev ${BRIDGE}`);
	delete s.dhcp;
}

// A 2.4 GHz radio reaches furthest; use the channel it is already on, if any.
function rescue_radio() {
	const busy = {};
	for (let i in nl80211.request(nl80211.const.NL80211_CMD_GET_INTERFACE, nl80211.const.NLM_F_DUMP) ?? [])
		if (i.wiphy_freq)
			busy[i.wiphy] = i.wiphy_freq;
	let best = null;
	for (let w in nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, nl80211.const.NLM_F_DUMP, { split_wiphy_dump: true }) ?? []) {
		if (!w.wiphy_name || best?.name == w.wiphy_name)
			continue;
		for (let b in w.wiphy_bands ?? [])
			for (let f in b?.freqs ?? [])
				if (f.freq >= 2412 && f.freq <= 2472 && !f.disabled && !f.no_ir && !best)
					best = { name: w.wiphy_name, index: w.wiphy, freq: f.freq };
	}
	if (best && busy[best.index])
		best.freq = busy[best.index];
	return best;
}

function start_wifi(s) {
	const radio = rescue_radio();
	if (!radio)
		return false;
	const channel = (radio.freq - 2407) / 5;
	nl80211.request(nl80211.const.NL80211_CMD_NEW_INTERFACE, 0, { wiphy: radio.index, ifname: VIF, iftype: NL80211_IFTYPE_AP });
	writefile(HOSTAPD_CONF, join('\n', [
		`interface=${VIF}`, `bridge=${BRIDGE}`, 'driver=nl80211', `ssid=${SSID}`, 'hw_mode=g',
		`channel=${channel}`, 'ieee80211n=1', 'wmm_enabled=1', ''
	]));
	sh(`hostapd -B -P ${HOSTAPD_PID} ${HOSTAPD_CONF}`);
	s.wifi = { ssid: SSID, radio: radio.name };
	return true;
}

function stop_wifi(s) {
	const p = pid_of(HOSTAPD_PID);
	if (p)
		sh(`kill ${p}`);
	unlink(HOSTAPD_PID);
	nl80211.request(nl80211.const.NL80211_CMD_DEL_INTERFACE, 0, { dev: VIF });
	delete s.wifi;
}

// OpenWrt names the status LED in the device tree (alias led-running).
function status_led() {
	const path = trim(readfile('/proc/device-tree/aliases/led-running') ?? '', '\0\n');
	const label = path ? trim(readfile(`/proc/device-tree${path}/label`) ?? '', '\0\n') : '';
	if (label && readfile(`/sys/class/leds/${label}/trigger`) != null)
		return label;
	return (lsdir('/sys/class/leds') ?? [])[0];
}

function led_blink(s) {
	const led = status_led();
	if (!led || !match(led, /^[A-Za-z0-9:_.-]+$/))
		return;
	const m = match(readfile(`/sys/class/leds/${led}/trigger`) ?? '', /\[([^\]]+)\]/);
	s.led = { name: led, trigger: m ? m[1] : 'none' };
	writefile(`/sys/class/leds/${led}/trigger`, 'timer');
	writefile(`/sys/class/leds/${led}/delay_on`, '150');
	writefile(`/sys/class/leds/${led}/delay_off`, '150');
}

function led_restore(s) {
	if (s.led?.name)
		writefile(`/sys/class/leds/${s.led.name}/trigger`, s.led.trigger);
	delete s.led;
}

function adguard_wanted(cur) {
	return cur.get('supacudy', 'adguard', 'enabled') == '1' && readfile('/usr/bin/AdGuardHome', 1) != null;
}

function start_dns_fallback(s) {
	sh(`dnsmasq --conf-file=/dev/null --port=53 --no-resolv --server=127.0.0.1#5353 --pid-file=${DNS_PID}`);
	s.dns_fallback = alive(DNS_PID);
	s.dns_retry = 0;
}

function stop_dns_fallback(s) {
	const p = pid_of(DNS_PID);
	if (p)
		sh(`kill ${p}`);
	unlink(DNS_PID);
	delete s.dns_fallback;
}

function dns_tick(cur, s) {
	if (!adguard_wanted(cur)) {
		stop_dns_fallback(s);
		s.dns_misses = 0;
		return;
	}
	if (s.dns_fallback) {
		// Port 53 has to be free for AdGuard Home to start again.
		if (++s.dns_retry >= DNS_RETRY_TICKS) {
			stop_dns_fallback(s);
			sh('/etc/init.d/adguardhome restart');
			// Give it two checks to start before judging it again.
			s.dns_misses = -2;
		}
		return;
	}
	s.dns_misses = alive(ADGUARD_PID) ? 0 : (s.dns_misses ?? 0) + 1;
	if (s.dns_misses >= DNS_MISSES)
		start_dns_fallback(s);
}

function stop_all(s) {
	stop_wifi(s);
	stop_dhcp(s);
	led_restore(s);
	s.active = false;
	delete s.since;
}

function tick() {
	const cur = cursor();
	const s = load();
	s.dhcp_misses ??= 0;
	s.wifi_misses ??= 0;
	s.clear ??= 0;

	const dhcp_needed = lan_dhcp_off(cur) && !dhcp_server_found(alive(DNSMASQ_PID));
	const wifi_needed = uptime() >= BOOT_GRACE_S && !user_ap_up() && !lan_cable();
	s.dhcp_misses = dhcp_needed ? s.dhcp_misses + 1 : 0;
	s.wifi_misses = wifi_needed ? s.wifi_misses + 1 : 0;

	if (s.dhcp_misses >= DHCP_MISSES && !s.dhcp)
		start_dhcp(s);
	if (s.wifi_misses >= WIFI_MISSES && !s.wifi)
		start_wifi(s);

	dns_tick(cur, s);

	// Leave once nothing has needed it for a while.
	if (s.dhcp || s.wifi) {
		s.clear = (!dhcp_needed && !wifi_needed) ? s.clear + 1 : 0;
		if (s.clear >= CLEAR_TICKS) {
			stop_all(s);
			s.clear = 0;
		} else if (!s.active) {
			s.active = true;
			s.since = time();
			led_blink(s);
		}
	}
	save(s);
}

if (ARGV[0] == 'stop') {
	const s = load();
	stop_all(s);
	stop_dns_fallback(s);
	save(s);
} else {
	tick();
}
