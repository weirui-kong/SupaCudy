// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Uplink failover: of the uplinks that are connected (Ethernet WAN, repeater,
// USB tethering), use the highest-priority one whose internet works, for
// IPv4 and IPv6 separately. One check per run; failover-watch runs it every
// TICK_S seconds and the UI reads the state it writes.
//
// "Works" means one of the probe targets answers a ping sent through that
// uplink. Switching never bounces an interface:
//   - our own default routes (metric ROUTE_METRIC, below netifd's base
//     metrics but above a VPN's) point at the chosen uplinks
//   - IPv6 on the LAN follows the chosen uplink: its delegated prefix when it
//     has one, otherwise the ULA prefix with NAT66 on that uplink; with no
//     working IPv6 the router stops advertising itself as IPv6 gateway
//   - optionally, connections that went out through the old uplink are
//     deleted so devices reconnect at once
// The two LAN settings this changes (lan.ip6class, dhcp lan.ra_lifetime) are
// recorded in ORIG and restored when the uplinks are back to normal or the
// watcher stops.
//
//   ucode failover.uc          one check
//   ucode failover.uc stop     undo every change

'use strict';

import { cursor } from 'uci';
import { readfile, writefile, unlink, mkdir, popen } from 'fs';
import { connect } from 'ubus';

const RUN = '/var/run/supacudy';
const STATE = `${RUN}/failover.json`;
const ORIG = '/etc/supacudy/failover-orig.json';
const NAT66 = 'supacudy_nat66';
const ROUTE_METRIC = 5;
const ROUTE_PROTO = 99;
const TICK_S = 10;
// Working uplinks not in use are checked every STANDBY_TICKS ticks to save
// data on metered connections; everything else every tick.
const STANDBY_TICKS = 3;
const FAIL_PROBES = 3;
const RECOVER_PROBES = 5;

const UPLINKS = {
	wired: { v4: 'wan', v6: 'wan6' },
	repeater: { v4: 'wwan', v6: 'wwan6' },
	tethering: { v4: 'tethering', v6: 'tethering6' }
};
const DEFAULT_ORDER = [ 'wired', 'repeater', 'tethering' ];
const DEFAULT_TARGETS = {
	v4: [ '223.5.5.5', '1.1.1.1', '8.8.8.8' ],
	v6: [ '2400:3200::1', '2606:4700:4700::1111', '2001:4860:4860::8888' ]
};

let bus = null;

function as_list(v) {
	return type(v) == 'array' ? v : (v ? [ v ] : []);
}

function sh(cmd) {
	const p = popen(`${cmd} 2>/dev/null`);
	if (!p)
		return { code: -1, out: '' };
	const out = p.read('all') ?? '';
	return { code: p.close(), out };
}

function load(path, fallback) {
	try {
		return json(readfile(path) ?? 'null') ?? fallback;
	} catch {
		return fallback;
	}
}

function is_ip4(s) {
	return type(s) == 'string' && match(s, /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) != null;
}

function is_ip6(s) {
	return type(s) == 'string' && index(s, ':') >= 0 && match(s, /^[0-9A-Fa-f:.]{2,45}$/) != null;
}

function settings(cur) {
	const order = filter(as_list(cur.get('supacudy', 'failover', 'order')), (n) => UPLINKS[n]);
	for (let n in DEFAULT_ORDER)
		if (!(n in order))
			push(order, n);
	const t4 = filter(as_list(cur.get('supacudy', 'failover', 'target4')), is_ip4);
	const t6 = filter(as_list(cur.get('supacudy', 'failover', 'target6')), is_ip6);
	return {
		order,
		reset: cur.get('supacudy', 'failover', 'reset_connections') != '0',
		targets: { v4: length(t4) ? t4 : DEFAULT_TARGETS.v4, v6: length(t6) ? t6 : DEFAULT_TARGETS.v6 }
	};
}

// What netifd knows about one interface of an uplink, for one family.
function link_of(cur, iface, family) {
	if (!cur.get('network', iface) || cur.get('network', iface, 'disabled') == '1')
		return null;
	const st = bus.call(`network.interface.${iface}`, 'status');
	if (!st?.up || !st.l3_device)
		return null;
	let gateway = null;
	for (let r in st.route ?? [])
		if (r.mask == 0 && (family == 'v4' ? r.target == '0.0.0.0' : r.target == '::'))
			gateway = r.nexthop;
	const addrs = family == 'v4' ? st['ipv4-address'] : st['ipv6-address'];
	const address = addrs?.[0]?.address;
	if (!address || gateway == null)
		return null;
	return {
		dev: st.l3_device,
		address,
		gateway: (gateway == '0.0.0.0' || gateway == '::') ? null : gateway,
		prefixes: family == 'v6' ? map(st['ipv6-prefix'] ?? [], (p) => `${p.address}/${p.mask}`) : []
	};
}

// IPv4 probes leave by interface. IPv6 ones by source address: netifd's
// IPv6 default routes only match the uplink's own source addresses.
function probe(link, family, targets) {
	for (let t in targets) {
		const args = family == 'v4' ? `-4 -I ${link.dev}` : `-6 -I ${link.address}`;
		if (sh(`ping ${args} -c1 -W1 ${t} >/dev/null`).code == 0)
			return true;
	}
	return false;
}

function update_health(h, link, due, family, targets) {
	if (!link) {
		return { iface: h.iface, link: false, ok: false, fails: 0, oks: 0, checked: h.checked ?? null };
	}
	const next = { ...h, link: true, dev: link.dev, address: link.address, prefixes: link.prefixes };
	// A newly connected uplink is judged by its first probe.
	if (!h.link)
		due = true;
	if (!due)
		return next;
	next.checked = time();
	if (probe(link, family, targets)) {
		next.fails = 0;
		next.oks = (h.oks ?? 0) + 1;
		if (!h.link || next.oks >= RECOVER_PROBES)
			next.ok = true;
	} else {
		next.oks = 0;
		next.fails = (h.fails ?? 0) + 1;
		if (!h.link || next.fails >= FAIL_PROBES)
			next.ok = false;
	}
	return next;
}

function choose(order, health, family) {
	for (let n in order)
		if (health[n]?.[family]?.link && health[n][family].ok)
			return n;
	return null;
}

function first_linked(order, health, family) {
	for (let n in order)
		if (health[n]?.[family]?.link)
			return n;
	return null;
}

function set_route(family, link) {
	const ip = family == 'v4' ? 'ip -4' : 'ip -6';
	if (!link) {
		sh(`${ip} route del default proto ${ROUTE_PROTO}`);
		return;
	}
	const via = link.gateway ? `via ${link.gateway} ` : '';
	sh(`${ip} route replace default ${via}dev ${link.dev} metric ${ROUTE_METRIC} proto ${ROUTE_PROTO}`);
}

function set_nat66(dev) {
	if (!dev) {
		sh(`nft delete table ip6 ${NAT66}`);
		return;
	}
	const rules = `table ip6 ${NAT66}\ndelete table ip6 ${NAT66}\n` +
		`table ip6 ${NAT66} {\n\tchain post {\n\t\ttype nat hook postrouting priority srcnat; policy accept;\n` +
		`\t\toifname "${dev}" ip6 saddr fc00::/7 masquerade\n\t}\n}\n`;
	mkdir(RUN);
	writefile(`${RUN}/nat66.nft`, rules);
	sh(`nft -f ${RUN}/nat66.nft`);
}

// Values this file sets itself; never taken for the user's own setting.
function ours(ip6class) {
	const list = as_list(ip6class);
	if (!length(list) || list[length(list) - 1] != 'local' || length(list) > 2)
		return false;
	return length(list) == 1 || length(filter(values(UPLINKS), (u) => u.v6 == list[0])) > 0;
}

// Keeps lan.ip6class and the RA router lifetime as wanted; null means the
// user's own setting.
function set_lan_ipv6(cur, ip6class, ra_off) {
	const orig = load(ORIG, {});
	let net = false, dhcp = false;
	const now_class = cur.get('network', 'lan', 'ip6class');
	if (ip6class) {
		if (!orig.ip6class_managed) {
			orig.ip6class_managed = true;
			orig.ip6class = ours(now_class) ? null : (now_class ?? null);
		}
		if (join(' ', as_list(now_class)) != join(' ', ip6class)) {
			cur.set('network', 'lan', 'ip6class', ip6class);
			net = true;
		}
	} else if (orig.ip6class_managed || ours(now_class)) {
		if (orig.ip6class != null && !ours(orig.ip6class))
			cur.set('network', 'lan', 'ip6class', orig.ip6class);
		else
			cur.delete('network', 'lan', 'ip6class');
		delete orig.ip6class_managed;
		delete orig.ip6class;
		net = true;
	}
	const now_ra = cur.get('dhcp', 'lan', 'ra_lifetime');
	if (ra_off) {
		if (!orig.ra_managed) {
			orig.ra_managed = true;
			orig.ra_lifetime = now_ra ?? null;
		}
		if (now_ra != '0') {
			cur.set('dhcp', 'lan', 'ra_lifetime', '0');
			dhcp = true;
		}
	} else if (orig.ra_managed) {
		if (orig.ra_lifetime != null)
			cur.set('dhcp', 'lan', 'ra_lifetime', orig.ra_lifetime);
		else
			cur.delete('dhcp', 'lan', 'ra_lifetime');
		delete orig.ra_managed;
		delete orig.ra_lifetime;
		dhcp = true;
	}
	if (net || dhcp) {
		if (length(keys(orig))) {
			mkdir('/etc/supacudy');
			writefile(ORIG, sprintf('%J', orig));
		} else {
			unlink(ORIG);
		}
	}
	if (net) {
		cur.commit('network');
		sh('ubus call network reload');
	}
	if (dhcp) {
		cur.commit('dhcp');
		sh('/etc/init.d/odhcpd reload');
	}
}

function reset_connections(family, old) {
	const f = family == 'v4' ? 'ipv4' : 'ipv6';
	if (old.address)
		sh(`conntrack -D -f ${f} --reply-dst ${old.address}`);
	for (let p in old.prefixes ?? [])
		sh(`conntrack -D -f ${f} -s ${p}`);
}

// A tunnel's route to its server still points at the old uplink.
function restart_vpn(cur) {
	if (cur.get('network', 'vpn', 'proto') == 'wireguard')
		sh('ifup vpn');
	if (cur.get('openvpn', 'supacudy', 'enabled') == '1')
		sh('/etc/init.d/openvpn restart');
}

function teardown(cur) {
	set_route('v4', null);
	set_route('v6', null);
	set_nat66(null);
	set_lan_ipv6(cur, null, false);
	unlink(STATE);
}

function tick() {
	const cur = cursor();
	if (cur.get('supacudy', 'netmode', 'mode') == 'ap') {
		teardown(cur);
		return;
	}
	const cfg = settings(cur);
	const prev = load(STATE, {});
	const count = (prev.tick ?? 0) + 1;
	const health = {};
	for (let n in cfg.order)
		health[n] = {};
	for (let family in [ 'v4', 'v6' ]) {
		const active = prev[`active_${family}`];
		const check = (n, due) => {
			const iface = UPLINKS[n][family];
			const h = prev.uplinks?.[n]?.[family] ?? { iface, link: false, ok: false, fails: 0, oks: 0 };
			const link = link_of(cur, iface, family);
			health[n][family] = { ...update_health(h, link, due, family, cfg.targets[family]), iface };
			if (link)
				health[n][family].link_info = link;
		};
		// The uplink in use first: once it misses a probe, the others are
		// checked in the same run, so a switch never waits for them.
		if (active && health[active])
			check(active, true);
		const troubled = !active || !health[active] || active != first_linked(cfg.order, prev.uplinks ?? {}, family) ||
			(health[active][family]?.fails ?? 0) > 0 || !health[active][family]?.link;
		// A connected uplink that does not work yet is checked every time
		// too, so it becomes usable RECOVER_PROBES ticks after it recovers.
		for (let n in cfg.order)
			if (n != active)
				check(n, troubled || count % STANDBY_TICKS == 0 || !(prev.uplinks?.[n]?.[family]?.ok ?? false));
	}

	const state = { tick: count, time: time(), uplinks: {}, order: cfg.order };
	for (let family in [ 'v4', 'v6' ]) {
		const ok = choose(cfg.order, health, family);
		// With no working uplink, IPv4 stays on the best connected one so the
		// router keeps a route; IPv6 is withdrawn from the LAN instead.
		const active = ok ?? (family == 'v4' ? first_linked(cfg.order, health, family) : null);
		const old = prev[`active_${family}`];
		state[`active_${family}`] = active;
		state[`online_${family}`] = ok != null;
		state[`since_${family}`] = active == old ? (prev[`since_${family}`] ?? time()) : time();
		set_route(family, active ? health[active][family].link_info : null);
		if (old && active && old != active) {
			if (cfg.reset && prev.uplinks?.[old]?.[family])
				reset_connections(family, prev.uplinks[old][family]);
			if (family == 'v4')
				restart_vpn(cur);
		}
	}

	// IPv6 on the LAN.
	const active6 = state.active_v6;
	const link6 = active6 ? health[active6].v6.link_info : null;
	let other_prefix = false;
	for (let n in cfg.order)
		if (n != active6 && health[n].v6.link && length(health[n].v6.prefixes ?? []))
			other_prefix = true;
	const own_prefix = link6 && length(link6.prefixes) > 0;
	let ip6class = null;
	if (other_prefix)
		ip6class = own_prefix ? [ UPLINKS[active6].v6, 'local' ] : [ 'local' ];
	set_lan_ipv6(cur, ip6class, !active6 && first_linked(cfg.order, health, 'v6') != null);
	set_nat66(link6 && !own_prefix ? link6.dev : null);

	for (let n in cfg.order) {
		state.uplinks[n] = {};
		for (let family in [ 'v4', 'v6' ]) {
			const h = { ...health[n][family] };
			delete h.link_info;
			state.uplinks[n][family] = h;
		}
	}
	mkdir(RUN);
	writefile(STATE, sprintf('%J', state));
}

bus = connect();
if (ARGV[0] == 'stop')
	teardown(cursor());
else
	tick();
