// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// LAN addressing, the DHCP pool and DHCP reservations.

'use strict';

import {
	INVALID, NOT_FOUND, ubus, uci, run_later, fail, normalize_mac,
	ipv4_to_int, int_to_ipv4, parse_netmask, prefix_to_mask, subnet, overlaps, is_private, uci_bool
} from 'supacudy.util';

const LEASETIME = /^(\d+[mhd]|infinite)$/;

function dhcp_section(cur, network) {
	let found = null;
	cur.foreach('dhcp', 'dhcp', (s) => {
		if (s.interface == network && !found)
			found = s['.name'];
	});
	return found;
}

function network_subnet(cur, name) {
	const ip = cur.get('network', name, 'ipaddr');
	const mask = cur.get('network', name, 'netmask') ?? '255.255.255.0';
	if (type(ip) == 'array')
		return null;
	if (ip && index(ip, '/') > 0) {
		const parts = split(ip, '/');
		return subnet(parts[0], +parts[1]);
	}
	return ip ? subnet(ip, parse_netmask(mask)) : null;
}

// Subnets the LAN must not overlap: other local networks and the WAN side.
function other_subnets(cur, exclude) {
	const out = [];
	const dump = ubus().call('network.interface', 'dump') ?? { interface: [] };
	for (let iface in dump.interface) {
		if (iface.interface == exclude)
			continue;
		for (let a in iface['ipv4-address'] ?? []) {
			const net = subnet(a.address, a.mask);
			if (net)
				push(out, { name: iface.interface, net });
		}
	}
	cur.foreach('network', 'interface', (s) => {
		if (s['.name'] == exclude || s.proto != 'static')
			return;
		const net = network_subnet(cur, s['.name']);
		if (net && !length(filter(out, (o) => o.name == s['.name'])))
			push(out, { name: s['.name'], net });
	});
	return out;
}

function reservations(cur) {
	const out = [];
	cur.foreach('dhcp', 'host', (s) => {
		const macs = type(s.mac) == 'array' ? s.mac : split(s.mac ?? '', ' ');
		const mac = normalize_mac(macs[0]);
		if (mac && s.ip)
			push(out, { id: s['.name'], mac, ip: s.ip, name: s.name ?? null });
	});
	return out;
}

function lan_get(network) {
	const cur = uci();
	const net = network_subnet(cur, network);
	if (!net)
		return null;
	const dhcp = dhcp_section(cur, network);
	const opt = (name) => dhcp ? cur.get('dhcp', dhcp, name) : null;
	const start = +(opt('start') ?? 100);
	const limit = +(opt('limit') ?? 150);

	return {
		ipaddr: int_to_ipv4(net.address),
		netmask: int_to_ipv4(prefix_to_mask(net.prefix)),
		prefix: net.prefix,
		dhcp: {
			enabled: dhcp != null && !uci_bool(opt('ignore'), false),
			start,
			limit,
			leasetime: opt('leasetime') ?? '12h',
			first: int_to_ipv4(net.network + start),
			last: int_to_ipv4(net.network + start + limit - 1)
		},
		reservations: network == 'lan' ? reservations(cur) : []
	};
}

function validate_lan(cur, network, args) {
	const prefix = parse_netmask(args.netmask);
	const net = subnet(args.ipaddr, prefix);
	if (!net || prefix < 16 || prefix > 30)
		return 'invalid_subnet';
	if (net.address == net.network || net.address == net.broadcast)
		return 'invalid_address';
	if (!is_private(net))
		return 'not_private';
	for (let other in other_subnets(cur, network))
		if (overlaps(net, other.net))
			return { reason: 'subnet_conflict', with: other.name };

	const first = net.network + args.start;
	const last = first + args.limit - 1;
	if (args.start < 1 || args.limit < 1 || last >= net.broadcast)
		return 'pool_out_of_range';
	if (!match(args.leasetime, LEASETIME))
		return 'invalid_leasetime';
	return null;
}

function lan_set(req, network) {
	const a = req.args;
	if (type(a.ipaddr) != 'string' || type(a.netmask) != 'string' || type(a.dhcp_enabled) != 'bool' ||
	    type(a.start) != 'int' || type(a.limit) != 'int' || type(a.leasetime) != 'string')
		return req.error(INVALID);

	const cur = uci();
	if (!cur.get('network', network))
		return req.error(NOT_FOUND);
	const problem = validate_lan(cur, network, a);
	if (problem)
		return type(problem) == 'object' ? fail(problem.reason, { with: problem.with }) : fail(problem);

	const before = lan_get(network);
	cur.set('network', network, 'ipaddr', a.ipaddr);
	cur.set('network', network, 'netmask', int_to_ipv4(prefix_to_mask(parse_netmask(a.netmask))));
	let dhcp = dhcp_section(cur, network);
	if (!dhcp) {
		dhcp = network;
		cur.set('dhcp', dhcp, 'dhcp');
		cur.set('dhcp', dhcp, 'interface', network);
	}
	cur.set('dhcp', dhcp, 'start', `${a.start}`);
	cur.set('dhcp', dhcp, 'limit', `${a.limit}`);
	cur.set('dhcp', dhcp, 'leasetime', a.leasetime);
	if (a.dhcp_enabled)
		cur.delete('dhcp', dhcp, 'ignore');
	else
		cur.set('dhcp', dhcp, 'ignore', '1');
	cur.commit('network');
	cur.commit('dhcp');

	const moved = before.ipaddr != a.ipaddr;
	run_later('/etc/init.d/network reload; /etc/init.d/dnsmasq restart', 1);
	return { applied: true, address_changed: moved, ipaddr: a.ipaddr };
}

function reservation_set(req) {
	const mac = normalize_mac(req.args.mac);
	const ip = req.args.ip;
	const name = trim(req.args.name ?? '');
	if (!mac || ipv4_to_int(ip) == null || length(name) > 63 || (name != '' && !match(name, /^[A-Za-z0-9][A-Za-z0-9-]*$/)))
		return req.error(INVALID);

	const cur = uci();
	const lan = network_subnet(cur, 'lan');
	const n = ipv4_to_int(ip);
	if (!lan || n <= lan.network || n >= lan.broadcast)
		return fail('outside_lan');
	if (n == lan.address)
		return fail('router_address');

	let existing = null;
	for (let r in reservations(cur)) {
		if (r.mac == mac)
			existing = r.id;
		else if (r.ip == ip)
			return fail('ip_taken', { by: r.mac });
	}

	const section = existing ?? cur.add('dhcp', 'host');
	cur.set('dhcp', section, 'mac', mac);
	cur.set('dhcp', section, 'ip', ip);
	if (name != '')
		cur.set('dhcp', section, 'name', name);
	else
		cur.delete('dhcp', section, 'name');
	cur.commit('dhcp');
	run_later('/etc/init.d/dnsmasq reload', 1);
	return { mac, ip, name: name || null };
}

function reservation_delete(req) {
	const mac = normalize_mac(req.args.mac);
	if (!mac)
		return req.error(INVALID);

	const cur = uci();
	let found = null;
	for (let r in reservations(cur))
		if (r.mac == mac)
			found = r.id;
	if (!found)
		return req.error(NOT_FOUND);
	cur.delete('dhcp', found);
	cur.commit('dhcp');
	run_later('/etc/init.d/dnsmasq reload', 1);
	return { mac, deleted: true };
}

const LAN_ARGS = { ipaddr: '', netmask: '', dhcp_enabled: false, start: 0, limit: 0, leasetime: '' };

const methods = {
	lan_get: {
		call: function(req) {
			return lan_get('lan') ?? req.error(NOT_FOUND);
		}
	},
	lan_set: {
		args: LAN_ARGS,
		call: function(req) {
			return lan_set(req, 'lan');
		}
	},
	reservation_set: {
		args: { mac: '', ip: '', name: '' },
		call: reservation_set
	},
	reservation_delete: {
		args: { mac: '' },
		call: reservation_delete
	}
};

export { methods, lan_get, lan_set, network_subnet, other_subnets, LAN_ARGS };
