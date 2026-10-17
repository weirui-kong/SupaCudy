// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Applies per-client policy from /etc/config/supacudy to nftables:
//   - bridge supacudy_acct: per-MAC byte counters, created once and never
//     regenerated so the counters survive policy changes
//   - inet supacudy_block: drops routed traffic from blocked clients
//   - bridge supacudy_limit: per-MAC upload/download rate limits
//   - inet supacudy_vpnroute: marks traffic that uses the VPN when not all
//     does (chosen devices, destinations in @vpn_dst, and in @vpn_dns the
//     addresses dnsmasq learns for chosen domains); netifd routes marked packets
//     through the VPN's table, and the kill switch drops them elsewhere
//
//   ucode /usr/libexec/supacudy/policy.uc

'use strict';

import { cursor } from 'uci';
import { popen, writefile } from 'fs';

const MAC = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/;
const SCRIPT = '/tmp/supacudy-policy.nft';

function nft_ok(cmd) {
	const p = popen(cmd);
	if (!p)
		return false;
	p.read('all');
	return p.close() == 0;
}

// Unicast only: broadcast and multicast frames would otherwise add bogus
// elements such as ff:ff:ff:ff:ff:ff.
const ACCT = `
table bridge supacudy_acct {
	set up { type ether_addr; flags dynamic; counter; size 4096; }
	set down { type ether_addr; flags dynamic; counter; size 4096; }
	chain pre {
		type filter hook prerouting priority -5; policy accept;
		ether saddr and 01:00:00:00:00:00 == 00:00:00:00:00:00 update @up { ether saddr }
	}
	chain post {
		type filter hook postrouting priority -5; policy accept;
		ether daddr and 01:00:00:00:00:00 == 00:00:00:00:00:00 update @down { ether daddr }
	}
}
`;

function clients() {
	const out = [];
	const uci = cursor();

	uci.foreach('supacudy', 'client', (s) => {
		const mac = lc(s.mac ?? '');
		if (!match(mac, MAC))
			return;
		push(out, {
			mac,
			blocked: s.blocked == '1',
			up: +(s.up_limit ?? 0) || 0,
			down: +(s.down_limit ?? 0) || 0
		});
	});

	return out;
}

// Must match the mark in vpn.uc's routing rule.
const VPN_MARK = '0x100';
const PRIVATE = '{ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }';

function vpn_policy() {
	const uci = cursor();
	const raw = uci.get('supacudy', 'vpn', 'devices');
	const devices = filter(map(type(raw) == 'array' ? raw : (raw ? [ raw ] : []), lc), (m) => match(m, MAC));
	const routes = uci.get('supacudy', 'vpn', 'routes');
	const cidrs = filter(type(routes) == 'array' ? routes : (routes ? [ routes ] : []),
		(r) => match(r, /^\d{1,3}(\.\d{1,3}){3}(\/\d{1,2})?$/));
	return {
		on: !!uci.get('supacudy', 'vpn', 'active') && uci.get('supacudy', 'vpn', 'route_mode') == 'selected',
		devices,
		cidrs,
		kill: uci.get('supacudy', 'vpn', 'kill_switch') == '1',
		allow_lan: uci.get('supacudy', 'vpn', 'allow_lan') != '0'
	};
}

// Addresses dnsmasq learns for VPN websites go to @vpn_dns, which is kept
// across reloads: devices and AdGuard Home cache their answers, so a set
// emptied here would stay empty until those expire. vpn.uc empties it when
// the list of websites changes.
function vpn_script(v) {
	const T = 'inet supacudy_vpnroute';
	if (!v.on)
		return `table ${T}\ndelete table ${T}\n`;
	let s = `add table ${T}\n`;
	s += `add set ${T} vpn_dns { type ipv4_addr; flags interval; }\n`;
	s += `add set ${T} vpn_macs { type ether_addr; }\nflush set ${T} vpn_macs\n`;
	if (length(v.devices))
		s += `add element ${T} vpn_macs { ${join(', ', v.devices)} }\n`;
	s += `add set ${T} vpn_dst { type ipv4_addr; flags interval; }\nflush set ${T} vpn_dst\n`;
	if (length(v.cidrs))
		s += `add element ${T} vpn_dst { ${join(', ', v.cidrs)} }\n`;
	s += `add chain ${T} pre { type filter hook prerouting priority mangle; policy accept; }\nflush chain ${T} pre\n`;
	s += `add rule ${T} pre iifname "br-lan" ether saddr @vpn_macs meta mark set meta mark | ${VPN_MARK}\n`;
	s += `add rule ${T} pre iifname "br-lan" ip daddr @vpn_dst counter meta mark set meta mark | ${VPN_MARK}\n`;
	s += `add rule ${T} pre iifname "br-lan" ip daddr @vpn_dns counter meta mark set meta mark | ${VPN_MARK}\n`;
	s += `add chain ${T} forward { type filter hook forward priority -3; policy accept; }\nflush chain ${T} forward\n`;
	// Marked IPv6 is not routed into the tunnel (its table is IPv4 only),
	// so the chosen devices' IPv6 is dropped instead of leaking.
	s += `add rule ${T} forward iifname "br-lan" ether saddr @vpn_macs meta nfproto ipv6 oifname != { "vpn", "br-lan" } counter drop\n`;
	if (v.kill)
		s += `add rule ${T} forward meta mark & ${VPN_MARK} == ${VPN_MARK} oifname != { "vpn", "br-lan" } ` +
			(v.allow_lan ? `ip daddr != ${PRIVATE} ` : '') + 'counter drop\n';
	return s;
}

function policy_script(list) {
	const blocked = filter(list, (c) => c.blocked);
	const limited = filter(list, (c) => c.up > 0 || c.down > 0);
	let s = 'table inet supacudy_block\ndelete table inet supacudy_block\n';
	s += 'table bridge supacudy_limit\ndelete table bridge supacudy_limit\n';

	s += 'table inet supacudy_block {\n';
	s += '\tset blocked { type ether_addr; ';
	if (length(blocked))
		s += `elements = { ${join(', ', map(blocked, (c) => c.mac))} }; `;
	s += '}\n';
	s += '\tchain forward {\n\t\ttype filter hook forward priority -4; policy accept;\n';
	s += '\t\tether saddr @blocked counter drop\n\t}\n}\n';

	s += 'table bridge supacudy_limit {\n';
	s += '\tchain pre {\n\t\ttype filter hook prerouting priority -4; policy accept;\n';
	for (let c in limited)
		if (c.up > 0)
			s += `\t\tether saddr ${c.mac} limit rate over ${c.up} kbytes/second drop\n`;
	s += '\t}\n';
	s += '\tchain post {\n\t\ttype filter hook postrouting priority -4; policy accept;\n';
	for (let c in limited)
		if (c.down > 0)
			s += `\t\tether daddr ${c.mac} limit rate over ${c.down} kbytes/second drop\n`;
	s += '\t}\n}\n';

	return s;
}

if (!nft_ok('nft list table bridge supacudy_acct >/dev/null 2>&1')) {
	writefile(SCRIPT, ACCT);
	if (!nft_ok(`nft -f ${SCRIPT} 2>&1`)) {
		warn('supacudy: could not create the accounting table\n');
		exit(1);
	}
}

writefile(SCRIPT, policy_script(clients()) + vpn_script(vpn_policy()));
if (!nft_ok(`nft -f ${SCRIPT} 2>&1`)) {
	warn('supacudy: could not apply the client policy\n');
	exit(1);
}

exit(0);
