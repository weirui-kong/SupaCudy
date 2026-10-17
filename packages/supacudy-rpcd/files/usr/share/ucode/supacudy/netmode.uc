// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Network mode. "router" is the default: NAT, firewall and DHCP. "ap" turns
// the router into an access point behind another router: the WAN port joins
// the LAN bridge, the DHCP server stops and the LAN takes a fixed address in
// the main router's network. The previous LAN settings are kept to undo it.

'use strict';

import { INVALID, NOT_FOUND, ubus, uci, run_later, fail, subnet, parse_netmask, ipv4_to_int, int_to_ipv4 } from 'supacudy.util';

const SAVED = 'netmode';
const KEEP = [ 'ipaddr', 'netmask', 'gateway', 'dns' ];

function lan_bridge(cur) {
	let name = null;
	cur.foreach('network', 'device', (d) => {
		if (d.name == 'br-lan')
			name ??= d['.name'];
	});
	return name;
}

function ports(cur, bridge) {
	const p = cur.get('network', bridge, 'ports');
	return type(p) == 'array' ? p : (p ? [ p ] : []);
}

function mode(cur) {
	return cur.get('supacudy', SAVED, 'mode') == 'ap' ? 'ap' : 'router';
}

// What the WAN currently gets from the main router, as a starting point.
function upstream() {
	const st = ubus().call('network.interface', 'status', { interface: 'wan' });
	const a = st?.['ipv4-address']?.[0];
	const gw = filter(st?.route ?? [], (r) => r.target == '0.0.0.0')[0]?.nexthop;
	return a ? { ipaddr: a.address, prefix: a.mask, gateway: gw ?? null, dns: st?.['dns-server'] ?? [] } : null;
}

function netmode_get() {
	const cur = uci();
	return {
		mode: mode(cur),
		lan: {
			ipaddr: cur.get('network', 'lan', 'ipaddr'),
			netmask: cur.get('network', 'lan', 'netmask') ?? '255.255.255.0',
			gateway: cur.get('network', 'lan', 'gateway') ?? null
		},
		upstream: upstream()
	};
}

function netmode_set(req) {
	const a = req.args;
	if (!(a.mode in [ 'router', 'ap' ]))
		return req.error(INVALID);
	const cur = uci();
	if (a.mode == mode(cur))
		return { applied: true };
	const bridge = lan_bridge(cur);
	if (!bridge)
		return req.error(NOT_FOUND);
	if (!cur.get('supacudy', SAVED))
		cur.set('supacudy', SAVED, 'netmode');

	if (a.mode == 'ap') {
		if (cur.get('supacudy', 'main', 'wan_port'))
			return fail('wan_as_lan_on');
		const prefix = parse_netmask(a.netmask);
		const net = subnet(a.ipaddr, prefix);
		const gw = ipv4_to_int(a.gateway);
		if (type(a.dns) != 'array' || length(a.dns) > 2 || length(filter(a.dns, (d) => ipv4_to_int(d) == null)))
			return req.error(INVALID);
		if (!net || prefix < 8 || prefix > 30 || net.address == net.network || net.address == net.broadcast)
			return fail('invalid_address');
		if (gw == null || gw <= net.network || gw >= net.broadcast || gw == net.address)
			return fail('gateway_outside');
		const port = cur.get('network', 'wan', 'device');
		if (!port)
			return fail('wan_not_configured');
		for (let k in KEEP) {
			const v = cur.get('network', 'lan', k);
			if (v != null)
				cur.set('supacudy', SAVED, `lan_${k}`, v);
		}
		cur.set('supacudy', SAVED, 'dhcp_ignore', cur.get('dhcp', 'lan', 'ignore') ?? '0');
		cur.set('supacudy', SAVED, 'wan_port', port);
		cur.set('supacudy', SAVED, 'mode', 'ap');
		cur.set('network', 'lan', 'ipaddr', a.ipaddr);
		cur.set('network', 'lan', 'netmask', int_to_ipv4((0xffffffff << (32 - prefix)) & 0xffffffff));
		cur.set('network', 'lan', 'gateway', a.gateway);
		if (length(a.dns))
			cur.set('network', 'lan', 'dns', a.dns);
		else
			cur.set('network', 'lan', 'dns', [ a.gateway ]);
		cur.set('network', bridge, 'ports', uniq([ ...ports(cur, bridge), port ]));
		for (let iface in [ 'wan', 'wan6' ])
			if (cur.get('network', iface))
				cur.set('network', iface, 'disabled', '1');
		cur.set('dhcp', 'lan', 'ignore', '1');
	} else {
		const port = cur.get('supacudy', SAVED, 'wan_port');
		for (let k in KEEP) {
			const v = cur.get('supacudy', SAVED, `lan_${k}`);
			if (v != null)
				cur.set('network', 'lan', k, v);
			else
				cur.delete('network', 'lan', k);
		}
		const rest = filter(ports(cur, bridge), (p) => p != port);
		if (length(rest))
			cur.set('network', bridge, 'ports', rest);
		else
			cur.delete('network', bridge, 'ports');
		for (let iface in [ 'wan', 'wan6' ])
			if (cur.get('network', iface))
				cur.delete('network', iface, 'disabled');
		if (cur.get('supacudy', SAVED, 'dhcp_ignore') == '1')
			cur.set('dhcp', 'lan', 'ignore', '1');
		else
			cur.delete('dhcp', 'lan', 'ignore');
		cur.delete('supacudy', SAVED);
	}
	cur.commit('network');
	cur.commit('dhcp');
	cur.commit('supacudy');
	// The reply must leave before the address it was sent from goes away.
	run_later('/etc/init.d/network restart; /etc/init.d/dnsmasq restart', 2);
	return { applied: true };
}

const methods = {
	netmode_get: { call: netmode_get },
	netmode_set: { args: { mode: '', ipaddr: '', netmask: '', gateway: '', dns: [] }, call: netmode_set }
};

export { methods };
