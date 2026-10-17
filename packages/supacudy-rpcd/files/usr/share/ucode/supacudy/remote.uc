// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Remote access through Tailscale: reach the router (and, if shared, the
// LAN) from anywhere without opening ports. Signing in and approving the
// shared LAN happen on Tailscale's side.
//
// tailscale0 gets its own firewall zone: input is accepted so the router's
// pages work remotely, and forwarding to the LAN only while the LAN is
// shared, as a subnet router (Tailscale masquerades that traffic itself).

'use strict';

import { access, popen } from 'fs';
import { INVALID, uci, run, run_later, fail, subnet, parse_netmask, int_to_ipv4 } from 'supacudy.util';

const TS_ZONE = 'supacudy_ts';
const TS_FORWARD = 'supacudy_ts_lan';
const TS_DEVICE = 'tailscale0';

function lan_cidr(cur) {
	const net = subnet(cur.get('network', 'lan', 'ipaddr'), parse_netmask(cur.get('network', 'lan', 'netmask') ?? '255.255.255.0'));
	return net ? `${int_to_ipv4(net.network)}/${net.prefix}` : null;
}

function json_of(cmd) {
	const p = popen(`${cmd} 2>/dev/null`);
	const out = p ? p.read('all') : null;
	p?.close();
	try {
		return out ? json(out) : null;
	} catch {
		return null;
	}
}

// Zone names are limited to 11 characters by fw4.
function set_zone(cur, section, name, device, forward_section, share) {
	if (!cur.get('firewall', section)) {
		cur.set('firewall', section, 'zone');
		cur.set('firewall', section, 'name', name);
		cur.set('firewall', section, 'device', [ device ]);
		cur.set('firewall', section, 'input', 'ACCEPT');
		cur.set('firewall', section, 'output', 'ACCEPT');
		cur.set('firewall', section, 'forward', 'REJECT');
	}
	if (share) {
		cur.set('firewall', forward_section, 'forwarding');
		cur.set('firewall', forward_section, 'src', name);
		cur.set('firewall', forward_section, 'dest', 'lan');
	} else if (cur.get('firewall', forward_section)) {
		cur.delete('firewall', forward_section);
	}
}

function drop_zone(cur, section, forward_section) {
	for (let s in [ section, forward_section ])
		if (cur.get('firewall', s))
			cur.delete('firewall', s);
}

function ensure_section(cur) {
	if (!cur.get('supacudy', 'remote'))
		cur.set('supacudy', 'remote', 'remote');
}

function ts_installed() {
	return access('/usr/sbin/tailscale', 'x') ?? false;
}

function ts_enabled(cur) {
	return cur.get('supacudy', 'remote', 'tailscale') == '1';
}

function tailscale_status(cur) {
	const on = ts_enabled(cur) && ts_installed();
	const st = on ? json_of('tailscale status --json --peers=false') : null;
	return {
		installed: ts_installed(),
		enabled: ts_enabled(cur),
		share_lan: cur.get('supacudy', 'remote', 'tailscale_share') == '1',
		// NeedsLogin, Starting, Running, Stopped, NoState; null while
		// tailscaled does not answer.
		state: st?.BackendState ?? null,
		login_url: st?.AuthURL || null,
		addresses: st?.Self?.TailscaleIPs ?? [],
		name: st?.Self?.HostName ?? null,
		tailnet: st?.CurrentTailnet?.Name ?? null,
		lan: lan_cidr(cur)
	};
}

// Options are fixed strings or the LAN subnet the router derived itself.
function ts_up_command(cur) {
	const share = cur.get('supacudy', 'remote', 'tailscale_share') == '1';
	const routes = share ? lan_cidr(cur) : null;
	return `tailscale up --reset --accept-dns=false --accept-routes=false --advertise-routes=${routes ?? ''} --timeout=0s`;
}

function tailscale_set(req) {
	const a = req.args;
	if (type(a.enabled) != 'bool' || type(a.share_lan) != 'bool')
		return req.error(INVALID);
	if (a.enabled && !ts_installed())
		return fail('tailscale_missing');
	const cur = uci();
	ensure_section(cur);
	cur.set('supacudy', 'remote', 'tailscale', a.enabled ? '1' : '0');
	cur.set('supacudy', 'remote', 'tailscale_share', a.share_lan ? '1' : '0');
	if (a.enabled)
		set_zone(cur, TS_ZONE, 'tailscale', TS_DEVICE, TS_FORWARD, a.share_lan);
	else
		drop_zone(cur, TS_ZONE, TS_FORWARD);
	cur.commit('supacudy');
	cur.commit('firewall');
	// "up" waits for a sign-in that may never come, so it goes last; the
	// link it asks for shows up in the status meanwhile.
	run_later(a.enabled
		? `/etc/init.d/firewall reload; /etc/init.d/tailscale enable; /etc/init.d/tailscale start; sleep 2; ${ts_up_command(cur)}`
		: '/etc/init.d/tailscale stop; /etc/init.d/tailscale disable; /etc/init.d/firewall reload', 1);
	return { applied: true };
}

function tailscale_logout(req) {
	if (!ts_enabled(uci()) || !ts_installed())
		return fail('tailscale_not_running');
	run('tailscale logout');
	run_later(ts_up_command(uci()), 1);
	return { applied: true };
}

const methods = {
	tailscale_get: { call: () => tailscale_status(uci()) },
	tailscale_set: { args: { enabled: false, share_lan: false }, call: tailscale_set },
	tailscale_logout: { call: tailscale_logout }
};

export { methods };
