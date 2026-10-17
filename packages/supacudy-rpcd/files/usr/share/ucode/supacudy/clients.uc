// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Connected devices: who is on the network, how, and with which policy.

'use strict';

import { readfile } from 'fs';
import * as rtnl from 'rtnl';
import * as nl80211 from 'nl80211';
import {
	INVALID, ubus, uci, run, uptime, normalize_mac, is_random_mac
} from 'supacudy.util';

const TYPES = [
	'phone', 'tablet', 'laptop', 'desktop', 'tv', 'camera', 'printer',
	'speaker', 'watch', 'game', 'appliance', 'gateway', 'nas', 'other'
];
const MAX_LIMIT_KBPS = 1000000;

// Neighbour states that mean the device answered recently (linux/neighbour.h).
const NUD_ONLINE = rtnl.const.NUD_REACHABLE | rtnl.const.NUD_STALE |
	rtnl.const.NUD_DELAY | rtnl.const.NUD_PROBE;

function section_name(mac) {
	return 'c_' + replace(mac, ':', '');
}

function leases() {
	const path = uci().get_first('dhcp', 'dnsmasq', 'leasefile') ?? '/tmp/dhcp.leases';
	const out = {};
	for (let line in split(readfile(path) ?? '', '\n')) {
		const f = split(line, ' ');
		const mac = normalize_mac(f[1]);
		if (length(f) < 4 || !mac)
			continue;
		out[mac] = { ip: f[2], hostname: f[3] == '*' ? null : f[3], expires: +f[0] };
	}
	return out;
}

// Networks whose devices count as clients: the ones our DHCP serves (LAN,
// guest). Excludes the WAN side and anything without a pool.
function client_networks() {
	const served = {};
	uci().foreach('dhcp', 'dhcp', (s) => {
		if (s.interface && s.ignore != '1' && s.interface != 'wan')
			served[s.interface] = true;
	});

	const out = {};
	const status = ubus().call('network.interface', 'dump') ?? { interface: [] };
	for (let iface in status.interface)
		if (iface.l3_device && served[iface.interface])
			out[iface.l3_device] = iface.interface;
	return out;
}

function neighbours(networks) {
	const out = {};
	const dump = rtnl.request(rtnl.const.RTM_GETNEIGH, rtnl.const.NLM_F_DUMP, { family: rtnl.const.AF_INET }) ?? [];
	for (let n in dump) {
		const mac = normalize_mac(n.lladdr);
		const network = networks[n.dev];
		if (!mac || !network)
			continue;
		const online = (n.state & NUD_ONLINE) != 0;
		if (!out[mac] || online)
			out[mac] = { ip: n.dst, network, online };
	}
	return out;
}

function wireless_stations() {
	const out = {};
	const radios = ubus().call('network.wireless', 'status') ?? {};
	for (let name, radio in radios) {
		for (let iface in radio.interfaces ?? []) {
			if (iface.config?.mode != 'ap' || !iface.ifname)
				continue;
			// Straight from the kernel: the iwinfo ubus object lives in rpcd
			// itself, so calling it from this plugin would deadlock.
			const list = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION,
				nl80211.const.NLM_F_DUMP, { dev: iface.ifname }) ?? [];
			for (let sta in list) {
				const mac = normalize_mac(sta.mac);
				if (mac)
					out[mac] = {
						band: radio.config?.band ?? null,
						network: iface.config?.network?.[0] ?? 'lan',
						signal: sta.sta_info?.signal ?? null
					};
			}
		}
	}
	return out;
}

function counters() {
	const out = { up: {}, down: {} };
	const r = run('nft -j list table bridge supacudy_acct');
	if (r.code != 0)
		return out;
	const doc = json(r.out);
	for (let item in doc?.nftables ?? []) {
		const set = item.set;
		if (!set || !(set.name in out))
			continue;
		for (let e in set.elem ?? []) {
			const mac = normalize_mac(e.elem?.val);
			if (mac)
				out[set.name][mac] = e.elem?.counter?.bytes ?? 0;
		}
	}
	return out;
}

function reservations() {
	const out = {};
	uci().foreach('dhcp', 'host', (s) => {
		for (let m in (type(s.mac) == 'array' ? s.mac : split(s.mac ?? '', ' '))) {
			const mac = normalize_mac(m);
			if (mac && s.ip)
				out[mac] = s.ip;
		}
	});
	return out;
}

function settings() {
	const out = {};
	uci().foreach('supacudy', 'client', (s) => {
		const mac = normalize_mac(s.mac);
		if (mac)
			out[mac] = s;
	});
	return out;
}

function hidden_set() {
	const out = {};
	for (let mac in uci().get('supacudy', 'main', 'hidden') ?? [])
		out[mac] = true;
	return out;
}

function list() {
	const lease = leases();
	const neigh = neighbours(client_networks());
	const wifi = wireless_stations();
	const bytes = counters();
	const reserved = reservations();
	const conf = settings();
	const hidden = hidden_set();

	const macs = {};
	for (let source in [lease, neigh, wifi, conf])
		for (let mac in source)
			macs[mac] = true;

	const out = [];
	const unhide = [];
	for (let mac in macs) {
		const s = conf[mac] ?? {};
		const sta = wifi[mac];
		const n = neigh[mac];
		const online = !!sta || !!n?.online;

		if (hidden[mac]) {
			if (!online)
				continue;
			push(unhide, mac);
		}

		push(out, {
			mac,
			ip: n?.ip ?? lease[mac]?.ip ?? null,
			hostname: lease[mac]?.hostname ?? null,
			name: s.name ?? null,
			type: s.type ?? null,
			online,
			connection: sta ? 'wifi' : (n || lease[mac] ? 'wired' : null),
			band: sta?.band ?? null,
			network: sta?.network ?? n?.network ?? 'lan',
			signal: sta?.signal ?? null,
			random_mac: is_random_mac(mac),
			blocked: s.blocked == '1',
			up_limit: +(s.up_limit ?? 0) || 0,
			down_limit: +(s.down_limit ?? 0) || 0,
			tx_bytes: bytes.up[mac] ?? 0,
			rx_bytes: bytes.down[mac] ?? 0,
			reserved_ip: reserved[mac] ?? null
		});
	}

	// A hidden device that comes back is shown again from now on.
	if (length(unhide)) {
		const cur = uci();
		cur.set('supacudy', 'main', 'hidden', filter(keys(hidden), (m) => !(m in unhide)));
		cur.commit('supacudy');
	}

	return { clients: out, time: uptime() };
}

function ensure_section(cur, mac) {
	const name = section_name(mac);
	if (!cur.get('supacudy', name)) {
		cur.set('supacudy', name, 'client');
		cur.set('supacudy', name, 'mac', mac);
	}
	return name;
}

function apply_policy() {
	run('/etc/init.d/supacudy reload');
}

const methods = {
	clients_list: {
		call: function() {
			return list();
		}
	},

	client_set: {
		args: { mac: '', name: '', type: '' },
		call: function(req) {
			const mac = normalize_mac(req.args.mac);
			const name = trim(req.args.name ?? '');
			const kind = req.args.type ?? '';
			if (!mac || length(name) > 64 || match(name, /[[:cntrl:]]/) || (kind != '' && !(kind in TYPES)))
				return req.error(INVALID);

			const cur = uci();
			const section = ensure_section(cur, mac);
			if (name == '')
				cur.delete('supacudy', section, 'name');
			else
				cur.set('supacudy', section, 'name', name);
			if (kind == '')
				cur.delete('supacudy', section, 'type');
			else
				cur.set('supacudy', section, 'type', kind);
			cur.commit('supacudy');
			return { mac, name: name || null, type: kind || null };
		}
	},

	client_block: {
		args: { mac: '', blocked: false },
		call: function(req) {
			const mac = normalize_mac(req.args.mac);
			if (!mac || type(req.args.blocked) != 'bool')
				return req.error(INVALID);

			const cur = uci();
			const section = ensure_section(cur, mac);
			cur.set('supacudy', section, 'blocked', req.args.blocked ? '1' : '0');
			cur.commit('supacudy');
			apply_policy();
			return { mac, blocked: req.args.blocked };
		}
	},

	client_limit: {
		args: { mac: '', up: 0, down: 0 },
		call: function(req) {
			const mac = normalize_mac(req.args.mac);
			const up = req.args.up;
			const down = req.args.down;
			if (!mac || type(up) != 'int' || type(down) != 'int' ||
			    up < 0 || down < 0 || up > MAX_LIMIT_KBPS || down > MAX_LIMIT_KBPS)
				return req.error(INVALID);

			const cur = uci();
			const section = ensure_section(cur, mac);
			cur.set('supacudy', section, 'up_limit', `${up}`);
			cur.set('supacudy', section, 'down_limit', `${down}`);
			cur.commit('supacudy');
			apply_policy();
			return { mac, up_limit: up, down_limit: down };
		}
	},

	clients_forget_offline: {
		call: function() {
			const current = list().clients;
			const cur = uci();
			const hidden = hidden_set();
			let count = 0;
			for (let c in current) {
				if (c.online)
					continue;
				hidden[c.mac] = true;
				count++;
				// Keep settings that still matter if the device returns.
				if (!c.blocked && !c.up_limit && !c.down_limit)
					cur.delete('supacudy', section_name(c.mac));
			}
			cur.set('supacudy', 'main', 'hidden', keys(hidden));
			cur.commit('supacudy');
			return { forgotten: count };
		}
	},

	clients_reset_counters: {
		call: function() {
			run('nft reset set bridge supacudy_acct up');
			run('nft reset set bridge supacudy_acct down');
			return { reset: true };
		}
	}
};

export { methods, TYPES };
