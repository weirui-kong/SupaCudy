// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Login protection: an address with supacudy.guard.attempts failed logins
// within guard.window minutes cannot reach the router's management (SSH,
// web UI, LuCI, AdGuard Home) for guard.ban minutes. Forwarding, DNS and
// DHCP stay open to it. Failures are read from the log: dropbear, LuCI,
// AdGuard Home and the SupaCudy login CGI all name the address.
//
//   ucode login-guard.uc        set up the firewall table, then follow the log
//   ucode login-guard.uc stop   remove the table, lifting every ban
//
// The settings are read again for every login event, so changing them
// takes effect without a restart and keeps the current bans.

'use strict';

import { popen } from 'fs';
import { cursor } from 'uci';

const TABLE = 'supacudy_guard';
const ADGUARD_PORT = 3000;
const LIMITS = { attempts: [ 1, 20, 3 ], window: [ 1, 1440, 30 ], ban: [ 1, 10080, 120 ] };

// [ pattern, kind ]; the address is the last capture.
const EVENTS = [
	[ /dropbear\[[0-9]+\]: Bad password attempt for .* from \[?([0-9A-Fa-f:.]+?)\]?:[0-9]+$/, 'fail' ],
	[ /dropbear\[[0-9]+\]: Login attempt for nonexistent user from \[?([0-9A-Fa-f:.]+?)\]?:[0-9]+$/, 'fail' ],
	[ /luci: failed login on .* for .* from ([0-9A-Fa-f:.]+)$/, 'fail' ],
	[ /AdGuardHome\[[0-9]+\]: .*\/control\/login: from ip ([0-9A-Fa-f:.]+): invalid username or password/, 'fail' ],
	[ /supacudy-login: failed login from ([0-9A-Fa-f:.]+)$/, 'fail' ],
	[ /dropbear\[[0-9]+\]: (Password|Pubkey) auth succeeded for .* from \[?([0-9A-Fa-f:.]+?)\]?:[0-9]+$/, 'ok' ],
	[ /AdGuardHome\[[0-9]+\]: .*successfully logged in from ip ([0-9A-Fa-f:.]+)/, 'ok' ],
	[ /supacudy-login: login from ([0-9A-Fa-f:.]+)$/, 'ok' ]
];

function bounded(cur, name) {
	const range = LIMITS[name];
	const v = +(cur.get('supacudy', 'guard', name) ?? range[2]);
	return v >= range[0] && v <= range[1] && v == int(v) ? v : range[2];
}

function settings() {
	const cur = cursor();
	return {
		// On unless turned off: upgrades without the section are protected too.
		enabled: cur.get('supacudy', 'guard', 'enabled') != '0',
		attempts: bounded(cur, 'attempts'),
		window: bounded(cur, 'window'),
		ban: bounded(cur, 'ban')
	};
}

function port_of(listen) {
	const m = match(`${listen}`, /:([0-9]+)$/);
	return m ? +m[1] : null;
}

function management_ports() {
	const cur = cursor();
	const ports = { [ADGUARD_PORT]: true };
	cur.foreach('dropbear', 'dropbear', (s) => {
		ports[+(s.Port ?? 22)] = true;
	});
	for (let opt in [ 'listen_http', 'listen_https' ]) {
		let list = cur.get('uhttpd', 'main', opt) ?? [];
		for (let l in type(list) == 'array' ? list : [ list ]) {
			const p = port_of(l);
			if (p)
				ports[p] = true;
		}
	}
	return sort(filter(map(keys(ports), (p) => +p), (p) => p > 0 && p < 65536));
}

function nft_script(text) {
	const p = popen('nft -f - 2>/dev/null', 'w');
	if (!p)
		return false;
	p.write(text);
	return p.close() == 0;
}

function table_exists() {
	return system(`nft list table inet ${TABLE} >/dev/null 2>&1`, 2000) == 0;
}

// The sets survive a restart of the service. Reject rather than drop: a locked-out browser fails at once instead of
// hanging.
function setup() {
	const ports = join(', ', management_ports());
	let text = '';
	if (!table_exists())
		text += `table inet ${TABLE} {
	set ban4 { type ipv4_addr; flags timeout; }
	set ban6 { type ipv6_addr; flags timeout; }
	chain input { type filter hook input priority filter - 5; policy accept; }
}
`;
	text += `flush chain inet ${TABLE} input
add rule inet ${TABLE} input tcp dport { ${ports} } ip saddr @ban4 counter reject with tcp reset
add rule inet ${TABLE} input tcp dport { ${ports} } ip6 saddr @ban6 counter reject with tcp reset
`;
	return nft_script(text);
}

function teardown() {
	if (table_exists())
		system([ 'nft', 'delete', 'table', 'inet', TABLE ], 5000);
}

function is_ip4(s) {
	const m = match(s, /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/);
	return m != null && +m[1] <= 255 && +m[2] <= 255 && +m[3] <= 255 && +m[4] <= 255;
}

function is_ip6(s) {
	return length(s) <= 45 && match(s, /^[0-9A-Fa-f:]+$/) != null && index(s, ':') >= 0;
}

// Local tools and scripts log in from here; they are never banned.
function exempt(ip) {
	return ip == '127.0.0.1' || ip == '::1';
}

function normalize(ip) {
	const mapped = match(ip, /^::ffff:([0-9.]+)$/);
	return lc(mapped ? mapped[1] : ip);
}

function ban(ip, minutes) {
	const set = is_ip4(ip) ? 'ban4' : 'ban6';
	system([ 'nft', 'add', 'element', 'inet', TABLE, set, `{ ${ip} timeout ${minutes}m }` ], 5000);
	system([ 'logger', '-p', 'authpriv.warn', '-t', 'supacudy-guard', `banned ${ip} for ${minutes} min` ]);
}

function follow() {
	if (!settings().enabled) {
		teardown();
		return;
	}
	setup();
	const started = time();
	const failures = {};
	// -t adds the epoch time: lines from before this start are history. Not
	// filtered with -e, which takes a basic regex without alternation.
	const log = popen('logread -f -t', 'r');
	for (let line = log.read('line'); length(line); line = log.read('line')) {
		const at = match(line, /\[([0-9]+)\.[0-9]+\]/);
		if (!at || +at[1] < started)
			continue;
		for (let ev in EVENTS) {
			const m = match(trim(line), ev[0]);
			if (!m)
				continue;
			const ip = normalize(m[length(m) - 1]);
			if (!(is_ip4(ip) || is_ip6(ip)) || exempt(ip))
				break;
			const conf = settings();
			if (ev[1] == 'ok') {
				delete failures[ip];
				break;
			}
			const now = time();
			failures[ip] = filter([ ...(failures[ip] ?? []), now ], (t) => now - t < conf.window * 60);
			if (length(failures[ip]) >= conf.attempts) {
				ban(ip, conf.ban);
				delete failures[ip];
			}
			break;
		}
	}
	log.close();
}

switch (ARGV[0]) {
case 'stop':
	teardown();
	break;
default:
	follow();
}
