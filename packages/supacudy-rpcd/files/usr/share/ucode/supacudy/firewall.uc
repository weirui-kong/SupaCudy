// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Inbound access from the internet: port forwards (fw4 "redirect" sections,
// including ones made in LuCI), a DMZ host, and ports opened on the router
// itself (fw4 "rule" sections that this module names sc_open_*); and flow
// offloading, which moves established connections out of the CPU's path.

'use strict';

import { INVALID, NOT_FOUND, uci, run_later, fail, subnet, parse_netmask, ipv4_to_int } from 'supacudy.util';

const PROTOS = [ 'tcp', 'udp', 'tcp udp' ];
const DMZ = 'sc_dmz';
const OPEN_PREFIX = 'sc_open_';
const FORWARD_PREFIX = 'sc_fwd_';
const RULES_MAX = 64;

function proto_of(v) {
	const list = type(v) == 'array' ? v : split(v ?? 'tcp udp', /[ ,]+/);
	const tcp = 'tcp' in list || 'tcpudp' in list;
	const udp = 'udp' in list || 'tcpudp' in list;
	return tcp && udp ? 'tcp udp' : (udp ? 'udp' : 'tcp');
}

// Returns [first, last] or null for "443" / "8000-8010".
function port_range(s) {
	const m = type(s) == 'string' ? match(trim(s), /^(\d{1,5})(-(\d{1,5}))?$/) : null;
	if (!m)
		return null;
	const a = +m[1], b = m[3] ? +m[3] : a;
	return a >= 1 && b <= 65535 && a <= b ? [ a, b ] : null;
}

function overlap(p, q) {
	return p && q && p[0] <= q[1] && q[0] <= p[1];
}

function shares_proto(a, b) {
	return a == b || a == 'tcp udp' || b == 'tcp udp';
}

function lan_net(cur) {
	return subnet(cur.get('network', 'lan', 'ipaddr'), parse_netmask(cur.get('network', 'lan', 'netmask') ?? '255.255.255.0'));
}

function on_lan(cur, ip) {
	const net = lan_net(cur);
	const n = ipv4_to_int(ip);
	return net != null && n != null && n > net.network && n < net.broadcast && n != net.address;
}

function forwards(cur) {
	const out = [];
	cur.foreach('firewall', 'redirect', (s) => {
		if (s['.name'] == DMZ || (s.target && s.target != 'DNAT') || s.src != 'wan' || !s.dest_ip || !s.src_dport)
			return;
		push(out, {
			id: s['.name'],
			name: s.name ?? s['.name'],
			proto: proto_of(s.proto),
			external_port: s.src_dport,
			internal_ip: s.dest_ip,
			internal_port: s.dest_port && s.dest_port != s.src_dport ? s.dest_port : '',
			enabled: s.enabled != '0'
		});
	});
	return out;
}

function open_ports(cur) {
	const out = [];
	cur.foreach('firewall', 'rule', (s) => {
		if (substr(s['.name'], 0, length(OPEN_PREFIX)) != OPEN_PREFIX)
			return;
		push(out, { id: s['.name'], name: s.name ?? s['.name'], proto: proto_of(s.proto), port: s.dest_port ?? '', enabled: s.enabled != '0' });
	});
	return out;
}

function defaults_section(cur) {
	let name = null;
	cur.foreach('firewall', 'defaults', (s) => {
		name ??= s['.name'];
	});
	return name;
}

function offload_mode(cur) {
	const d = defaults_section(cur);
	if (!d || cur.get('firewall', d, 'flow_offloading') != '1')
		return 'off';
	return cur.get('firewall', d, 'flow_offloading_hw') == '1' ? 'hardware' : 'software';
}

// MT7981 offloads in hardware (PPE/WED); per-device rate limits and traffic
// counters then miss offloaded packets, which the UI explains.
function offload_set(req) {
	const mode = req.args.mode;
	if (!(mode in [ 'off', 'software', 'hardware' ]))
		return req.error(INVALID);
	const cur = uci();
	const d = defaults_section(cur);
	if (!d)
		return req.error(NOT_FOUND);
	cur.set('firewall', d, 'flow_offloading', mode == 'off' ? '0' : '1');
	cur.set('firewall', d, 'flow_offloading_hw', mode == 'hardware' ? '1' : '0');
	cur.commit('firewall');
	run_later('/etc/init.d/firewall reload', 1);
	return { applied: true };
}

function firewall_get() {
	const cur = uci();
	const net = lan_net(cur);
	return {
		forwards: forwards(cur),
		open_ports: open_ports(cur),
		dmz: { enabled: cur.get('firewall', DMZ) != null && cur.get('firewall', DMZ, 'enabled') != '0', ip: cur.get('firewall', DMZ, 'dest_ip') ?? '' },
		lan: { ipaddr: cur.get('network', 'lan', 'ipaddr'), prefix: net?.prefix ?? 24 },
		offload: offload_mode(cur)
	};
}

// An external port can only lead to one place, whether a forward or the router.
function clashes(cur, id, proto, range) {
	for (let f in forwards(cur))
		if (f.id != id && f.enabled && shares_proto(f.proto, proto) && overlap(port_range(f.external_port), range))
			return true;
	for (let o in open_ports(cur))
		if (o.id != id && o.enabled && shares_proto(o.proto, proto) && overlap(port_range(o.port), range))
			return true;
	return false;
}

function free_name(cur, prefix) {
	for (let i = 1; ; i++)
		if (!cur.get('firewall', `${prefix}${i}`))
			return `${prefix}${i}`;
}

// fw4 applies redirects in order, so the catch-all DMZ goes last.
function dmz_last(cur) {
	if (!cur.get('firewall', DMZ))
		return;
	let sections = 0;
	cur.foreach('firewall', null, () => sections++);
	cur.reorder('firewall', DMZ, sections - 1);
}

function commit(cur) {
	dmz_last(cur);
	cur.commit('firewall');
	run_later('/etc/init.d/firewall reload', 1);
}

function valid_name(s) {
	return type(s) == 'string' && length(s) >= 1 && length(s) <= 64 && !match(s, /[[:cntrl:]'"]/);
}

function forward_set(req) {
	const a = req.args;
	if (type(a.id) != 'string' || !valid_name(a.name) || !(a.proto in PROTOS) || type(a.enabled) != 'bool' ||
	    type(a.internal_ip) != 'string' || type(a.internal_port) != 'string')
		return req.error(INVALID);
	const ext = port_range(a.external_port);
	const int = a.internal_port == '' ? ext : port_range(a.internal_port);
	if (!ext || !int || int[1] - int[0] != ext[1] - ext[0])
		return req.error(INVALID);
	const cur = uci();
	if (a.id != '' && cur.get('firewall', a.id) != 'redirect')
		return req.error(NOT_FOUND);
	if (!on_lan(cur, a.internal_ip))
		return fail('not_lan');
	if (a.enabled && clashes(cur, a.id, a.proto, ext))
		return fail('port_in_use');
	if (a.id == '' && length(forwards(cur)) >= RULES_MAX)
		return fail('too_many_rules');

	const id = a.id != '' ? a.id : free_name(cur, FORWARD_PREFIX);
	cur.set('firewall', id, 'redirect');
	cur.set('firewall', id, 'name', a.name);
	cur.set('firewall', id, 'target', 'DNAT');
	cur.set('firewall', id, 'src', 'wan');
	cur.set('firewall', id, 'dest', 'lan');
	cur.set('firewall', id, 'proto', a.proto);
	cur.set('firewall', id, 'src_dport', trim(a.external_port));
	cur.set('firewall', id, 'dest_ip', a.internal_ip);
	if (a.internal_port != '')
		cur.set('firewall', id, 'dest_port', trim(a.internal_port));
	else
		cur.delete('firewall', id, 'dest_port');
	cur.set('firewall', id, 'enabled', a.enabled ? '1' : '0');
	commit(cur);
	return { id };
}

function delete_section(req, kind, check) {
	const id = req.args.id;
	if (type(id) != 'string')
		return req.error(INVALID);
	const cur = uci();
	if (cur.get('firewall', id) != kind || !check(id))
		return req.error(NOT_FOUND);
	cur.delete('firewall', id);
	commit(cur);
	return { deleted: true };
}

function open_port_set(req) {
	const a = req.args;
	if (type(a.id) != 'string' || !valid_name(a.name) || !(a.proto in PROTOS) || type(a.enabled) != 'bool')
		return req.error(INVALID);
	const range = port_range(a.port);
	if (!range)
		return req.error(INVALID);
	const cur = uci();
	if (a.id != '' && (substr(a.id, 0, length(OPEN_PREFIX)) != OPEN_PREFIX || cur.get('firewall', a.id) != 'rule'))
		return req.error(NOT_FOUND);
	if (a.enabled && clashes(cur, a.id, a.proto, range))
		return fail('port_in_use');
	if (a.id == '' && length(open_ports(cur)) >= RULES_MAX)
		return fail('too_many_rules');
	const id = a.id != '' ? a.id : free_name(cur, OPEN_PREFIX);
	cur.set('firewall', id, 'rule');
	cur.set('firewall', id, 'name', a.name);
	cur.set('firewall', id, 'src', 'wan');
	cur.set('firewall', id, 'proto', a.proto);
	cur.set('firewall', id, 'dest_port', trim(a.port));
	cur.set('firewall', id, 'target', 'ACCEPT');
	cur.set('firewall', id, 'enabled', a.enabled ? '1' : '0');
	commit(cur);
	return { id };
}

function dmz_set(req) {
	const a = req.args;
	if (type(a.enabled) != 'bool' || type(a.ip) != 'string')
		return req.error(INVALID);
	const cur = uci();
	if (!a.enabled) {
		if (cur.get('firewall', DMZ))
			cur.delete('firewall', DMZ);
		commit(cur);
		return { applied: true };
	}
	if (!on_lan(cur, a.ip))
		return fail('not_lan');
	cur.set('firewall', DMZ, 'redirect');
	cur.set('firewall', DMZ, 'name', 'SupaCudy DMZ');
	cur.set('firewall', DMZ, 'target', 'DNAT');
	cur.set('firewall', DMZ, 'src', 'wan');
	cur.set('firewall', DMZ, 'dest', 'lan');
	cur.set('firewall', DMZ, 'proto', 'all');
	cur.set('firewall', DMZ, 'dest_ip', a.ip);
	cur.set('firewall', DMZ, 'enabled', '1');
	commit(cur);
	return { applied: true };
}

const FORWARD_ARGS = { id: '', name: '', proto: '', external_port: '', internal_ip: '', internal_port: '', enabled: false };

// The router's own services seen from the internet side. Both rules are
// created on first boot (90-supacudy in supacudy-base): the web UI open,
// SSH closed. A missing rule counts as closed.
const WAN_ACCESS = {
	webui: { section: 'supacudy_wan_webui', name: 'SupaCudy: web UI from the WAN', ports: '80 443' },
	ssh: { section: 'supacudy_wan_ssh', name: 'SupaCudy: SSH from the WAN', ports: '22' }
};

function wan_access_get() {
	const cur = uci();
	const out = {};
	for (let k, v in WAN_ACCESS)
		out[k] = cur.get('firewall', v.section) == 'rule' && cur.get('firewall', v.section, 'enabled') != '0';
	return out;
}

function wan_access_set(req) {
	const a = req.args;
	if (type(a.webui) != 'bool' || type(a.ssh) != 'bool')
		return req.error(INVALID);
	const cur = uci();
	for (let k, v in WAN_ACCESS) {
		cur.set('firewall', v.section, 'rule');
		cur.set('firewall', v.section, 'name', v.name);
		cur.set('firewall', v.section, 'src', 'wan');
		cur.set('firewall', v.section, 'proto', 'tcp');
		cur.set('firewall', v.section, 'dest_port', v.ports);
		cur.set('firewall', v.section, 'target', 'ACCEPT');
		cur.set('firewall', v.section, 'enabled', a[k] ? '1' : '0');
	}
	cur.commit('firewall');
	run_later('/etc/init.d/firewall reload', 1);
	return { applied: true };
}

const methods = {
	wan_access_get: { call: wan_access_get },
	wan_access_set: { args: { webui: false, ssh: false }, call: wan_access_set },
	firewall_get: { call: firewall_get },
	forward_set: { args: FORWARD_ARGS, call: forward_set },
	forward_delete: { args: { id: '' }, call: (req) => delete_section(req, 'redirect', (id) => id != DMZ) },
	open_port_set: { args: { id: '', name: '', proto: '', port: '', enabled: false }, call: open_port_set },
	open_port_delete: {
		args: { id: '' },
		call: (req) => delete_section(req, 'rule', (id) => substr(id, 0, length(OPEN_PREFIX)) == OPEN_PREFIX)
	},
	dmz_set: { args: { enabled: false, ip: '' }, call: dmz_set },
	offload_set: { args: { mode: '' }, call: offload_set }
};

export { methods };
