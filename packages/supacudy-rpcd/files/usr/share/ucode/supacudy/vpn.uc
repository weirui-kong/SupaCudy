// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// VPN client (WireGuard or OpenVPN): saved profiles, one of which can be
// connected as the "vpn" interface; a kill switch that stops LAN traffic from
// leaving outside the tunnel; and an exception for the upstream network's
// private ranges.
//
// Profiles live in /etc/config/supacudy (wg_profile, ovpn_profile). A
// connected WireGuard profile is copied into network.vpn plus a
// wireguard_vpn peer; an OpenVPN one runs as openvpn.supacudy on a fixed
// tun device that network.vpn wraps.

'use strict';

import { access, mkdir, readfile, unlink, writefile, chmod } from 'fs';
import { INVALID, NOT_FOUND, ubus, uci, run, run_later, fail, ipv4_to_int, normalize_mac } from 'supacudy.util';
import { CLEAR_CACHE_CMD } from 'supacudy.adguard';

const IFACE = 'vpn';
const PEER = 'vpn_peer';
const ZONE = 'supacudy_vpn';
const LAN_FORWARD = 'supacudy_vpn_fwd';
const ALLOW_LAN_RULE = 'supacudy_vpn_lan';
const NO_IPV6_RULE = 'supacudy_vpn_no6';
const DNS_TUNNEL_RULE = 'supacudy_vpn_dns';
// DNS servers of the connected uplinks, written by netifd.
const RESOLV_AUTO = '/tmp/resolv.conf.d/resolv.conf.auto';
const PRIVATE_RANGES = [ '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16' ];
const PROFILES_MAX = 16;
const DEVICES_MAX = 64;
const ROUTE_MODES = [ 'all', 'selected' ];
// With only some devices on the VPN, its routes go to this table and
// policy.uc marks those devices' packets so this rule sends them there.
const VPN_TABLE = '100';
const VPN_RULE = 'supacudy_vpn_rule';
const VPN_MARK = '0x100';
const DESTINATIONS_MAX = 64;
// dnsmasq adds the addresses of these domains to policy.uc's set vpn_dns as
// it answers lookups for them.
const DOMAIN_SET = 'supacudy_vpn_domains';
const DOMAIN_RE = /^([A-Za-z0-9]([A-Za-z0-9-]{0,62})\.)+[A-Za-z]{2,63}$/;

const OVPN_DIR = '/etc/supacudy/ovpn';
const OVPN_DEV = 'ovpnc';
const OVPN_SECTION = 'supacudy';
const OVPN_MAX = 65536;
// Directives that run programs, load plugins or replace our device and
// credentials. Provider files never need them; refusing them keeps an
// uploaded file from executing anything as root.
const OVPN_DENY = [
	'up', 'down', 'route-up', 'route-pre-down', 'ipchange', 'learn-address', 'client-connect',
	'client-disconnect', 'tls-verify', 'auth-user-pass-verify', 'script-security', 'plugin', 'iproute',
	'setenv', 'setenv-safe', 'config', 'cd', 'chroot', 'daemon', 'log', 'log-append', 'status',
	'writepid', 'management', 'management-client', 'askpass', 'dev-node', 'tmp-dir', 'up-delay',
	'route-noexec', 'ifconfig-noexec'
];
// Replaced by our own values.
const OVPN_DROP = [ 'dev', 'dev-type', 'auth-user-pass', 'auth-nocache' ];

const KEY_RE = /^[A-Za-z0-9+\/]{42}[AEIMQUYcgkosw480]=$/;
const HOST_RE = /^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$/;
const V6_RE = /^[0-9A-Fa-f:.]{2,45}$/;

function is_ip(s) {
	return type(s) == 'string' && (ipv4_to_int(s) != null || (index(s, ':') >= 0 && match(s, V6_RE) != null));
}

function is_cidr(s) {
	if (type(s) != 'string')
		return false;
	const m = match(s, /^([^\/]+)\/(\d{1,3})$/);
	if (!m)
		return false;
	const max = index(m[1], ':') >= 0 ? 128 : 32;
	return is_ip(m[1]) && +m[2] <= max;
}

function list_of(v, check, min, max) {
	if (type(v) != 'array' || length(v) < min || length(v) > max)
		return false;
	for (let x in v)
		if (!check(x))
			return false;
	return true;
}

function as_list(v) {
	return type(v) == 'array' ? v : (v ? [ v ] : []);
}

function profile_view(s) {
	if (s['.type'] == 'ovpn_profile')
		return {
			id: s['.name'],
			type: 'openvpn',
			name: s.name ?? s['.name'],
			remote: s.remote ?? '',
			username: s.username ?? ''
		};
	return {
		id: s['.name'],
		type: 'wireguard',
		name: s.name ?? s['.name'],
		addresses: as_list(s.address),
		dns: as_list(s.dns),
		mtu: +(s.mtu ?? 0),
		public_key: s.public_key ?? '',
		has_preshared_key: !!s.preshared_key,
		endpoint_host: s.endpoint_host ?? '',
		endpoint_port: +(s.endpoint_port ?? 51820),
		allowed_ips: as_list(s.allowed_ips),
		keepalive: +(s.keepalive ?? 0)
	};
}

function profiles(cur) {
	const out = [];
	cur.foreach('supacudy', 'wg_profile', (s) => push(out, s));
	cur.foreach('supacudy', 'ovpn_profile', (s) => push(out, s));
	return out;
}

function profile_type(cur, id) {
	const t = id ? cur.get('supacudy', id) : null;
	return t == 'wg_profile' ? 'wireguard' : (t == 'ovpn_profile' ? 'openvpn' : null);
}

// "wg show vpn dump" peer line: pubkey psk endpoint allowed handshake rx tx keepalive.
function tunnel_status(kind) {
	const st = ubus().call('network.interface', 'status', { interface: IFACE });
	const addresses = map(st?.['ipv4-address'] ?? [], (a) => `${a.address}/${a.mask}`);
	if (kind == 'openvpn') {
		// OpenVPN sets the address itself, so netifd (proto none) does not know it.
		const own = [];
		for (let l in split(run(`ip -4 -o addr show dev ${OVPN_DEV}`).out, '\n')) {
			const m = match(l, /inet ([0-9.]+\/[0-9]+)/);
			if (m)
				push(own, m[1]);
		}
		return {
			up: st?.up ?? false,
			// OpenVPN has no handshake to show; an address means the server accepted us.
			connected: length(own) > 0,
			addresses: own,
			uptime: st?.uptime ?? 0,
			endpoint: null,
			handshake: 0,
			rx_bytes: +(readfile(`/sys/class/net/${OVPN_DEV}/statistics/rx_bytes`) ?? 0),
			tx_bytes: +(readfile(`/sys/class/net/${OVPN_DEV}/statistics/tx_bytes`) ?? 0)
		};
	}
	const r = run(`wg show ${IFACE} dump`);
	let peer = null;
	if (r.code == 0) {
		const lines = split(trim(r.out), '\n');
		const f = length(lines) > 1 ? split(lines[1], '\t') : [];
		if (length(f) >= 7)
			peer = { endpoint: f[2] == '(none)' ? null : f[2], handshake: +f[4], rx: +f[5], tx: +f[6] };
	}
	return {
		up: st?.up ?? false,
		// WireGuard rekeys every two minutes; an older handshake means no answer.
		connected: (st?.up ?? false) && peer != null && peer.handshake > 0 && time() - peer.handshake < 180,
		addresses,
		uptime: st?.uptime ?? 0,
		endpoint: peer?.endpoint ?? null,
		// Seconds since the epoch; 0 means no handshake yet.
		handshake: peer?.handshake ?? 0,
		rx_bytes: peer?.rx ?? 0,
		tx_bytes: peer?.tx ?? 0
	};
}

// Only WireGuard routes can be moved to their own table (ip4table); OpenVPN
// installs its routes itself, so it always carries everything.
// Only dnsmasq-full can add looked-up addresses to an nftables set.
function domains_supported() {
	const out = run('dnsmasq --version').out;
	return index(out, 'nftset') >= 0 && index(out, 'no-nftset') < 0;
}

function route_mode(cur) {
	const active = cur.get('supacudy', 'vpn', 'active');
	if (active && profile_type(cur, active) == 'openvpn')
		return 'all';
	return cur.get('supacudy', 'vpn', 'route_mode') == 'selected' ? 'selected' : 'all';
}

// IPv6 the tunnel cannot carry would leave through the normal connection,
// so it is blocked unless the profile has an IPv6 address. For OpenVPN that
// is only known when its file sets one up itself.
function tunnel_ipv6(cur) {
	const id = cur.get('supacudy', 'vpn', 'active');
	const kind = profile_type(cur, id);
	if (kind == 'wireguard')
		return length(filter(as_list(cur.get('supacudy', id, 'address')), (a) => index(a, ':') >= 0)) > 0;
	if (kind == 'openvpn')
		return match(readfile(`${OVPN_DIR}/${id}.ovpn`) ?? '', /(^|\n)[ \t]*(ifconfig-ipv6|route-ipv6)[ \t]/) != null;
	return false;
}

function ipv6_state(cur) {
	if (!cur.get('supacudy', 'vpn', 'active'))
		return null;
	return cur.get('supacudy', 'vpn', 'ipv6') == '1' ? 'tunnel' : 'blocked';
}

function vpn_get() {
	const cur = uci();
	return {
		profiles: map(profiles(cur), profile_view),
		active: cur.get('supacudy', 'vpn', 'active') || null,
		kill_switch: cur.get('supacudy', 'vpn', 'kill_switch') == '1',
		allow_lan: cur.get('supacudy', 'vpn', 'allow_lan') != '0',
		route_mode: cur.get('supacudy', 'vpn', 'route_mode') == 'selected' ? 'selected' : 'all',
		devices: as_list(cur.get('supacudy', 'vpn', 'devices')),
		domains_supported: domains_supported(),
		destinations: [ ...as_list(cur.get('supacudy', 'vpn', 'domains')), ...as_list(cur.get('supacudy', 'vpn', 'routes')) ],
		status: tunnel_status(profile_type(cur, cur.get('supacudy', 'vpn', 'active'))),
		ipv6: ipv6_state(cur),
		time: time()
	};
}

function validate_profile(a, creating) {
	if (type(a.name) != 'string' || length(a.name) < 1 || length(a.name) > 64 || match(a.name, /[[:cntrl:]]/))
		return 'name';
	if (type(a.private_key) != 'string' || (a.private_key == '' ? creating : !match(a.private_key, KEY_RE)))
		return 'private_key';
	if (type(a.public_key) != 'string' || !match(a.public_key, KEY_RE))
		return 'public_key';
	if (type(a.preshared_key) != 'string' || (a.preshared_key != '' && a.preshared_key != '-' && !match(a.preshared_key, KEY_RE)))
		return 'preshared_key';
	if (!list_of(a.addresses, is_cidr, 1, 4))
		return 'addresses';
	if (!list_of(a.dns, is_ip, 0, 4))
		return 'dns';
	if (type(a.endpoint_host) != 'string' || !(match(a.endpoint_host, HOST_RE) || is_ip(a.endpoint_host)))
		return 'endpoint_host';
	if (type(a.endpoint_port) != 'int' || a.endpoint_port < 1 || a.endpoint_port > 65535)
		return 'endpoint_port';
	if (!list_of(a.allowed_ips, is_cidr, 1, 32))
		return 'allowed_ips';
	if (type(a.keepalive) != 'int' || a.keepalive < 0 || a.keepalive > 3600)
		return 'keepalive';
	if (type(a.mtu) != 'int' || (a.mtu != 0 && (a.mtu < 1280 || a.mtu > 1500)))
		return 'mtu';
	return null;
}

function ensure_vpn_section(cur) {
	if (!cur.get('supacudy', 'vpn'))
		cur.set('supacudy', 'vpn', 'vpn');
}

function lan_wan_forwardings(cur) {
	const out = [];
	cur.foreach('firewall', 'forwarding', (s) => {
		if (s.src == 'lan' && s.dest == 'wan')
			push(out, s['.name']);
	});
	return out;
}

function ensure_zone(cur) {
	if (cur.get('firewall', ZONE))
		return;
	cur.set('firewall', ZONE, 'zone');
	cur.set('firewall', ZONE, 'name', 'vpn');
	cur.set('firewall', ZONE, 'network', [ IFACE ]);
	cur.set('firewall', ZONE, 'input', 'REJECT');
	cur.set('firewall', ZONE, 'output', 'ACCEPT');
	cur.set('firewall', ZONE, 'forward', 'REJECT');
	cur.set('firewall', ZONE, 'masq', '1');
	cur.set('firewall', ZONE, 'mtu_fix', '1');
	cur.set('firewall', LAN_FORWARD, 'forwarding');
	cur.set('firewall', LAN_FORWARD, 'src', 'lan');
	cur.set('firewall', LAN_FORWARD, 'dest', 'vpn');
}

function uplink_dns() {
	const out = [];
	for (let line in split(readfile(RESOLV_AUTO) ?? '', '\n')) {
		const m = match(line, /^nameserver[ \t]+([0-9A-Fa-f:.]+)/);
		if (m && is_ip(m[1]) && !(m[1] in out) && substr(m[1], 0, 4) != '127.' && m[1] != '::1')
			push(out, m[1]);
	}
	return out;
}

// The VPN server's name, if it has one. The router looks it up again
// whenever the tunnel is (re)built, i.e. while the VPN's own DNS cannot be
// reached, so that one name goes to the uplink's DNS servers.
function endpoint_name(cur) {
	const id = cur.get('supacudy', 'vpn', 'active');
	const kind = profile_type(cur, id);
	let host = null;
	if (kind == 'wireguard')
		host = cur.get('supacudy', id, 'endpoint_host');
	else if (kind == 'openvpn') {
		const remote = cur.get('supacudy', id, 'remote') ?? '';
		// More than one colon is an IPv6 address with its port.
		host = length(split(remote, ':')) > 2 ? null : split(remote, ':')[0];
	}
	return host && !is_ip(host) && match(host, HOST_RE) ? lc(host) : null;
}

// The DNS servers the connected profile brings: its own, and for OpenVPN
// also those the server pushed (see ovpn_pushed_dns).
function profile_dns(cur) {
	const id = cur.get('supacudy', 'vpn', 'active');
	if (!id)
		return [];
	const pushed = profile_type(cur, id) == 'openvpn' ? as_list(cur.get('supacudy', 'vpn', 'pushed_dns')) : [];
	return uniq([ ...as_list(cur.get('supacudy', id, 'dns')), ...pushed ]);
}

// The kill switch acts only while a profile is connected: then LAN traffic
// may leave only through the tunnel (plus private ranges if allowed), even
// when the tunnel itself is down.
function apply_firewall(cur) {
	const active = !!cur.get('supacudy', 'vpn', 'active');
	// With selected devices, policy.uc enforces the kill switch for them only.
	const kill = active && cur.get('supacudy', 'vpn', 'kill_switch') == '1' && route_mode(cur) == 'all';
	const allow_lan = cur.get('supacudy', 'vpn', 'allow_lan') != '0';
	for (let name in lan_wan_forwardings(cur)) {
		if (kill)
			cur.set('firewall', name, 'enabled', '0');
		else
			cur.delete('firewall', name, 'enabled');
	}
	// policy.uc reads this to do the same for the chosen devices only.
	const ipv6 = active && tunnel_ipv6(cur);
	cur.set('supacudy', 'vpn', 'ipv6', ipv6 ? '1' : '0');
	if (cur.get('firewall', ZONE))
		cur.set('firewall', ZONE, 'masq6', ipv6 ? '1' : '0');
	if (active && !ipv6 && route_mode(cur) == 'all') {
		cur.set('firewall', NO_IPV6_RULE, 'rule');
		cur.set('firewall', NO_IPV6_RULE, 'name', 'SupaCudy VPN: no IPv6 outside the tunnel');
		cur.set('firewall', NO_IPV6_RULE, 'src', 'lan');
		cur.set('firewall', NO_IPV6_RULE, 'dest', 'wan');
		cur.set('firewall', NO_IPV6_RULE, 'family', 'ipv6');
		cur.set('firewall', NO_IPV6_RULE, 'proto', 'all');
		cur.set('firewall', NO_IPV6_RULE, 'target', 'REJECT');
	} else if (cur.get('firewall', NO_IPV6_RULE)) {
		cur.delete('firewall', NO_IPV6_RULE);
	}
	// With the kill switch, the VPN's DNS servers are reachable only through
	// the tunnel: while it is down the router's own lookups would otherwise
	// leave through the uplink. The uplink's own servers stay reachable for
	// the VPN server's name (see endpoint_name).
	const uplink = uplink_dns();
	const vpn_dns = filter(as_list(cur.get('supacudy', 'vpn', 'dns_servers')),
		(d) => substr(d, 0, 1) != '/' && !(d in uplink));
	if (kill && length(vpn_dns)) {
		cur.set('firewall', DNS_TUNNEL_RULE, 'rule');
		cur.set('firewall', DNS_TUNNEL_RULE, 'name', 'SupaCudy VPN: DNS only through the tunnel');
		cur.set('firewall', DNS_TUNNEL_RULE, 'dest', 'wan');
		cur.set('firewall', DNS_TUNNEL_RULE, 'dest_ip', vpn_dns);
		cur.set('firewall', DNS_TUNNEL_RULE, 'proto', 'tcp udp');
		cur.set('firewall', DNS_TUNNEL_RULE, 'dest_port', '53 853');
		cur.set('firewall', DNS_TUNNEL_RULE, 'target', 'REJECT');
	} else if (cur.get('firewall', DNS_TUNNEL_RULE)) {
		cur.delete('firewall', DNS_TUNNEL_RULE);
	}
	if (kill && allow_lan) {
		cur.set('firewall', ALLOW_LAN_RULE, 'rule');
		cur.set('firewall', ALLOW_LAN_RULE, 'name', 'SupaCudy VPN: upstream network');
		cur.set('firewall', ALLOW_LAN_RULE, 'src', 'lan');
		cur.set('firewall', ALLOW_LAN_RULE, 'dest', 'wan');
		cur.set('firewall', ALLOW_LAN_RULE, 'dest_ip', PRIVATE_RANGES);
		cur.set('firewall', ALLOW_LAN_RULE, 'proto', 'all');
		cur.set('firewall', ALLOW_LAN_RULE, 'target', 'ACCEPT');
	} else if (cur.get('firewall', ALLOW_LAN_RULE)) {
		cur.delete('firewall', ALLOW_LAN_RULE);
	}
}

// With automatic DNS, lookups would still go to the upstream network's
// servers; send them to the profile's servers instead while connected.
// Returns whether dnsmasq's settings changed.
function apply_dns(cur) {
	let section = null;
	cur.foreach('dhcp', 'dnsmasq', (s) => {
		section ??= s['.name'];
	});
	if (!section)
		return false;
	const before = join(' ', as_list(cur.get('dhcp', section, 'server')));
	const previous = as_list(cur.get('supacudy', 'vpn', 'dns_servers'));
	const kept = filter(as_list(cur.get('dhcp', section, 'server')), (s) => !(s in previous));
	// Everyone shares dnsmasq, so with only some devices on the VPN the
	// lookups stay on the normal path (its DNS may only work in the tunnel).
	const auto = (cur.get('supacudy', 'dns', 'mode') ?? 'auto') == 'auto' && route_mode(cur) == 'all';
	const add = auto ? profile_dns(cur) : [];
	const host = length(add) ? endpoint_name(cur) : null;
	if (host)
		for (let d in uplink_dns())
			push(add, `/${host}/${d}`);
	if (length(kept) + length(add))
		cur.set('dhcp', section, 'server', [ ...kept, ...add ]);
	else
		cur.delete('dhcp', section, 'server');
	if (auto) {
		if (length(add))
			cur.set('dhcp', section, 'noresolv', '1');
		else
			cur.delete('dhcp', section, 'noresolv');
	}
	if (length(add))
		cur.set('supacudy', 'vpn', 'dns_servers', add);
	else
		cur.delete('supacudy', 'vpn', 'dns_servers');
	return join(' ', as_list(cur.get('dhcp', section, 'server'))) != before;
}

function apply_routing(cur) {
	const selected = route_mode(cur) == 'selected' && !!cur.get('supacudy', 'vpn', 'active');
	if (cur.get('network', IFACE)) {
		if (selected)
			cur.set('network', IFACE, 'ip4table', VPN_TABLE);
		else
			cur.delete('network', IFACE, 'ip4table');
	}
	if (selected) {
		cur.set('network', VPN_RULE, 'rule');
		cur.set('network', VPN_RULE, 'mark', `${VPN_MARK}/${VPN_MARK}`);
		cur.set('network', VPN_RULE, 'lookup', VPN_TABLE);
		cur.set('network', VPN_RULE, 'priority', '100');
	} else if (cur.get('network', VPN_RULE)) {
		cur.delete('network', VPN_RULE);
	}
}

function write_interface(cur, p) {
	cur.delete('network', IFACE);
	cur.delete('network', PEER);
	cur.set('network', IFACE, 'interface');
	cur.set('network', IFACE, 'proto', 'wireguard');
	cur.set('network', IFACE, 'private_key', p.private_key);
	cur.set('network', IFACE, 'addresses', as_list(p.address));
	if (+(p.mtu ?? 0))
		cur.set('network', IFACE, 'mtu', p.mtu);
	apply_routing(cur);
	cur.set('network', PEER, `wireguard_${IFACE}`);
	cur.set('network', PEER, 'description', p.name ?? '');
	cur.set('network', PEER, 'public_key', p.public_key);
	if (p.preshared_key)
		cur.set('network', PEER, 'preshared_key', p.preshared_key);
	cur.set('network', PEER, 'endpoint_host', p.endpoint_host);
	cur.set('network', PEER, 'endpoint_port', p.endpoint_port ?? '51820');
	cur.set('network', PEER, 'allowed_ips', as_list(p.allowed_ips));
	cur.set('network', PEER, 'route_allowed_ips', '1');
	if (+(p.keepalive ?? 0))
		cur.set('network', PEER, 'persistent_keepalive', p.keepalive);
}

function write_openvpn(cur, id, enabled) {
	cur.delete('network', PEER);
	if (enabled) {
		cur.delete('network', IFACE);
		cur.set('network', IFACE, 'interface');
		cur.set('network', IFACE, 'proto', 'none');
		cur.set('network', IFACE, 'device', OVPN_DEV);
	}
	if (!cur.get('openvpn', OVPN_SECTION))
		cur.set('openvpn', OVPN_SECTION, 'openvpn');
	cur.set('openvpn', OVPN_SECTION, 'enabled', enabled ? '1' : '0');
	cur.set('openvpn', OVPN_SECTION, 'config', `${OVPN_DIR}/${id}.ovpn`);
	cur.commit('openvpn');
}

// tunnel_changed: the profile or connection changed, so the tunnel is
// restarted. Option changes (kill switch, routing) leave it up.
// AdGuard Home answers repeated lookups from its cache, which dnsmasq then
// never sees, so the cache is cleared for the websites routed through the
// VPN to be learned again (and with the VPN's DNS to take effect at once).
function commit_all(cur, tunnel_changed, websites_changed) {
	for (let c in [ 'network', 'firewall', 'dhcp', 'supacudy' ])
		cur.commit(c);
	let cmd = websites_changed ? `nft flush set inet supacudy_vpnroute vpn_dns; ` : '';
	// The routing rules first: dnsmasq reads the type of the set it fills
	// for websites when it starts.
	cmd += '/etc/init.d/network reload; /etc/init.d/firewall reload; /etc/init.d/supacudy reload; /etc/init.d/dnsmasq restart';
	if (tunnel_changed) {
		// Re-raising the interface applies changed WireGuard peers, which a
		// netifd reload alone leaves as they were.
		const wg = cur.get('network', IFACE, 'proto') == 'wireguard';
		cmd += `; /etc/init.d/openvpn restart${wg ? `; ifup ${IFACE}` : ''}`;
	}
	run_later(`${cmd}; ${CLEAR_CACHE_CMD}`, 1);
}

function vpn_profile_set(req) {
	const a = req.args;
	if (type(a.id) != 'string')
		return req.error(INVALID);
	const cur = uci();
	const creating = a.id == '';
	if (!creating && cur.get('supacudy', a.id) != 'wg_profile')
		return req.error(NOT_FOUND);
	const problem = validate_profile(a, creating);
	if (problem)
		return fail('profile_invalid', { field: problem });
	if (creating && length(profiles(cur)) >= PROFILES_MAX)
		return fail('too_many_profiles');

	const id = creating ? cur.add('supacudy', 'wg_profile') : a.id;
	cur.set('supacudy', id, 'name', a.name);
	if (a.private_key != '')
		cur.set('supacudy', id, 'private_key', a.private_key);
	// '' keeps the stored preshared key, '-' removes it.
	if (a.preshared_key == '-')
		cur.delete('supacudy', id, 'preshared_key');
	else if (a.preshared_key != '')
		cur.set('supacudy', id, 'preshared_key', a.preshared_key);
	cur.set('supacudy', id, 'public_key', a.public_key);
	cur.set('supacudy', id, 'address', a.addresses);
	if (length(a.dns))
		cur.set('supacudy', id, 'dns', a.dns);
	else
		cur.delete('supacudy', id, 'dns');
	cur.set('supacudy', id, 'endpoint_host', a.endpoint_host);
	cur.set('supacudy', id, 'endpoint_port', `${a.endpoint_port}`);
	cur.set('supacudy', id, 'allowed_ips', a.allowed_ips);
	cur.set('supacudy', id, 'keepalive', `${a.keepalive}`);
	cur.set('supacudy', id, 'mtu', `${a.mtu}`);

	// Editing the connected profile reconnects with the new settings.
	if (cur.get('supacudy', 'vpn', 'active') == id) {
		const p = cur.get_all('supacudy', id);
		write_interface(cur, p);
		apply_dns(cur);
		apply_firewall(cur);
		commit_all(cur, true);
	} else {
		cur.commit('supacudy');
	}
	return { id };
}

function vpn_profile_delete(req) {
	const id = req.args.id;
	if (type(id) != 'string')
		return req.error(INVALID);
	const cur = uci();
	if (!profile_type(cur, id))
		return req.error(NOT_FOUND);
	if (cur.get('supacudy', 'vpn', 'active') == id)
		return fail('profile_active');
	unlink(`${OVPN_DIR}/${id}.ovpn`);
	unlink(`${OVPN_DIR}/${id}.auth`);
	unlink(`${OVPN_DIR}/${id}.base`);
	cur.delete('supacudy', id);
	cur.commit('supacudy');
	return { deleted: true };
}

function vpn_connect(req) {
	const id = req.args.id;
	if (type(id) != 'string')
		return req.error(INVALID);
	const cur = uci();
	const kind = profile_type(cur, id);
	if (!kind)
		return req.error(NOT_FOUND);
	const p = cur.get_all('supacudy', id);
	ensure_vpn_section(cur);
	ensure_zone(cur);
	cur.set('supacudy', 'vpn', 'active', id);
	cur.delete('supacudy', 'vpn', 'pushed_dns');
	if (kind == 'openvpn') {
		write_openvpn(cur, id, true);
		apply_routing(cur);
	} else {
		if (cur.get('openvpn', OVPN_SECTION)) {
			cur.set('openvpn', OVPN_SECTION, 'enabled', '0');
			cur.commit('openvpn');
		}
		write_interface(cur, p);
	}
	apply_dns(cur);
	apply_firewall(cur);
	commit_all(cur, true);
	return { applied: true };
}

function vpn_disconnect() {
	const cur = uci();
	ensure_vpn_section(cur);
	if (cur.get('openvpn', OVPN_SECTION)) {
		cur.set('openvpn', OVPN_SECTION, 'enabled', '0');
		cur.commit('openvpn');
	}
	cur.delete('network', IFACE);
	cur.delete('network', PEER);
	cur.set('supacudy', 'vpn', 'active', '');
	cur.delete('supacudy', 'vpn', 'pushed_dns');
	apply_routing(cur);
	apply_dns(cur);
	apply_firewall(cur);
	commit_all(cur, true);
	return { applied: true };
}

function apply_domains(cur, domains) {
	if (cur.get('dhcp', DOMAIN_SET) && !length(domains)) {
		cur.delete('dhcp', DOMAIN_SET);
		return;
	}
	if (!length(domains))
		return;
	cur.set('dhcp', DOMAIN_SET, 'ipset');
	cur.set('dhcp', DOMAIN_SET, 'name', [ 'vpn_dns' ]);
	cur.set('dhcp', DOMAIN_SET, 'table', 'supacudy_vpnroute');
	cur.set('dhcp', DOMAIN_SET, 'table_family', 'inet');
	cur.set('dhcp', DOMAIN_SET, 'domain', domains);
}

function is_route(s) {
	const m = match(s, /^(\d{1,3}(\.\d{1,3}){3})(\/(\d{1,2}))?$/);
	return m != null && ipv4_to_int(m[1]) != null && (m[4] == null || +m[4] <= 32);
}

function vpn_options(req) {
	const a = req.args;
	if (type(a.kill_switch) != 'bool' || type(a.allow_lan) != 'bool' || !(a.route_mode in ROUTE_MODES) ||
	    type(a.devices) != 'array' || length(a.devices) > DEVICES_MAX ||
	    type(a.destinations) != 'array' || length(a.destinations) > DESTINATIONS_MAX)
		return req.error(INVALID);
	const domains = [], routes = [];
	for (let d in a.destinations) {
		if (type(d) == 'string' && is_route(d))
			push(routes, d);
		else if (type(d) == 'string' && length(d) <= 253 && match(d, DOMAIN_RE))
			push(domains, lc(d));
		else
			return fail('destination_invalid', { value: `${d}` });
	}
	if (length(domains) && !domains_supported())
		return fail('domains_unsupported');
	const devices = map(a.devices, normalize_mac);
	if (length(filter(devices, (d) => d == null)))
		return req.error(INVALID);
	const cur = uci();
	ensure_vpn_section(cur);
	const websites_changed = join(' ', as_list(cur.get('supacudy', 'vpn', 'domains'))) != join(' ', uniq(domains));
	cur.set('supacudy', 'vpn', 'kill_switch', a.kill_switch ? '1' : '0');
	cur.set('supacudy', 'vpn', 'allow_lan', a.allow_lan ? '1' : '0');
	cur.set('supacudy', 'vpn', 'route_mode', a.route_mode);
	for (let pair in [ [ 'devices', uniq(devices) ], [ 'domains', uniq(domains) ], [ 'routes', uniq(routes) ] ]) {
		if (length(pair[1]))
			cur.set('supacudy', 'vpn', pair[0], pair[1]);
		else
			cur.delete('supacudy', 'vpn', pair[0]);
	}
	apply_domains(cur, uniq(domains));
	apply_routing(cur);
	apply_dns(cur);
	apply_firewall(cur);
	const id = cur.get('supacudy', 'vpn', 'active');
	// While connected the routing mode touches netifd and dnsmasq too.
	if (id) {
		commit_all(cur, false, websites_changed);
	} else {
		cur.commit('network');
		cur.commit('firewall');
		cur.commit('dhcp');
		cur.commit('supacudy');
		run_later((websites_changed ? 'nft flush set inet supacudy_vpnroute vpn_dns; ' : '') +
			`/etc/init.d/firewall reload; /etc/init.d/supacudy reload; /etc/init.d/dnsmasq restart; ${CLEAR_CACHE_CMD}`, 1);
	}
	return { applied: true };
}

// Returns the cleaned configuration, or the directive that was refused.
function sanitize_ovpn(text) {
	const out = [];
	let inline = null;
	let remote = null;
	let tap = false;
	const dns = [];
	for (let line in split(replace(text, /\r/g, ''), '\n')) {
		const t = trim(line);
		if (inline) {
			push(out, line);
			if (t == `</${inline}>`)
				inline = null;
			continue;
		}
		const block = match(t, /^<([a-z-]+)>$/);
		if (block) {
			inline = block[1];
			push(out, line);
			continue;
		}
		if (t == '' || substr(t, 0, 1) == '#' || substr(t, 0, 1) == ';') {
			push(out, line);
			continue;
		}
		const word = lc(split(replace(t, /^--/, ''), /[ \t]+/)[0]);
		if (word in OVPN_DENY)
			return { refused: word };
		if (word == 'dev' && match(t, /^dev[ \t]+tap/) || word == 'dev-type' && match(t, /tap/))
			tap = true;
		if (word in OVPN_DROP)
			continue;
		// Servers in the file itself; pushed ones arrive via the hotplug script.
		if (word == 'dhcp-option') {
			const f = split(t, /[ \t]+/);
			if ((f[1] == 'DNS' || f[1] == 'DNS6') && is_ip(f[2]) && !(f[2] in dns))
				push(dns, f[2]);
		}
		if (word == 'remote' && !remote) {
			const f = split(t, /[ \t]+/);
			remote = f[2] ? `${f[1]}:${f[2]}` : f[1];
		}
		push(out, line);
	}
	if (tap)
		return { refused: 'dev tap' };
	if (!remote)
		return { refused: 'remote' };
	return { config: join('\n', out), remote, dns };
}

function vpn_ovpn_set(req) {
	const a = req.args;
	if (type(a.id) != 'string' || type(a.name) != 'string' || type(a.config) != 'string' ||
	    type(a.username) != 'string' || type(a.password) != 'string')
		return req.error(INVALID);
	if (length(a.name) < 1 || length(a.name) > 64 || match(a.name, /[[:cntrl:]]/) ||
	    length(a.username) > 128 || length(a.password) > 128 || match(a.username + a.password, /[[:cntrl:]]/))
		return fail('profile_invalid', { field: 'name' });
	if (length(a.config) > OVPN_MAX)
		return fail('ovpn_too_large');
	const cur = uci();
	const creating = a.id == '';
	if (!creating && cur.get('supacudy', a.id) != 'ovpn_profile')
		return req.error(NOT_FOUND);
	if (creating && a.config == '')
		return fail('profile_invalid', { field: 'config' });
	if (a.username == '' && a.password != '')
		return fail('profile_invalid', { field: 'username' });
	let clean = null;
	if (a.config != '') {
		clean = sanitize_ovpn(a.config);
		if (clean.refused)
			return fail('ovpn_unsafe', { directive: clean.refused });
	}
	if (creating && length(profiles(cur)) >= PROFILES_MAX)
		return fail('too_many_profiles');

	const id = creating ? cur.add('supacudy', 'ovpn_profile') : a.id;
	mkdir('/etc/supacudy');
	mkdir(OVPN_DIR, 0700);
	cur.set('supacudy', id, 'name', a.name);
	// An empty user name keeps the saved login; an empty password keeps the
	// saved password for a new user name.
	const auth = `${OVPN_DIR}/${id}.auth`;
	if (a.username != '') {
		const old = split(readfile(auth) ?? '', '\n');
		const password = a.password != '' ? a.password : (old[1] ?? '');
		cur.set('supacudy', id, 'username', a.username);
		writefile(auth, `${a.username}\n${password}\n`);
		chmod(auth, 0600);
	}
	const body = clean ? clean.config : readfile(`${OVPN_DIR}/${id}.base`) ?? '';
	if (clean) {
		writefile(`${OVPN_DIR}/${id}.base`, clean.config);
		cur.set('supacudy', id, 'remote', clean.remote);
		if (length(clean.dns))
			cur.set('supacudy', id, 'dns', clean.dns);
		else
			cur.delete('supacudy', id, 'dns');
	}
	// The device name is fixed so network.vpn can find it.
	const extra = [ `dev ${OVPN_DEV}`, 'dev-type tun' ];
	if (access(auth))
		push(extra, `auth-user-pass ${auth}`);
	writefile(`${OVPN_DIR}/${id}.ovpn`, `${body}\n${join('\n', extra)}\n`);
	chmod(`${OVPN_DIR}/${id}.ovpn`, 0600);
	// The new file may bring other DNS servers or add or drop IPv6 in the
	// tunnel; the server pushes its DNS again once it has reconnected.
	const active = cur.get('supacudy', 'vpn', 'active') == id;
	if (active) {
		cur.delete('supacudy', 'vpn', 'pushed_dns');
		apply_dns(cur);
		apply_firewall(cur);
		cur.commit('firewall');
		cur.commit('dhcp');
	}
	cur.commit('supacudy');
	if (active)
		run_later(`/etc/init.d/firewall reload; /etc/init.d/dnsmasq restart; /etc/init.d/openvpn restart; ${CLEAR_CACHE_CMD}`, 1);
	return { id };
}

const PROFILE_ARGS = {
	id: '', name: '', private_key: '', public_key: '', preshared_key: '', addresses: [], dns: [],
	endpoint_host: '', endpoint_port: 0, allowed_ips: [], keepalive: 0, mtu: 0
};

const methods = {
	vpn_get: { call: vpn_get },
	vpn_profile_set: { args: PROFILE_ARGS, call: vpn_profile_set },
	vpn_profile_delete: { args: { id: '' }, call: vpn_profile_delete },
	vpn_ovpn_set: { args: { id: '', name: '', config: '', username: '', password: '' }, call: vpn_ovpn_set },
	vpn_connect: { args: { id: '' }, call: vpn_connect },
	vpn_disconnect: { call: vpn_disconnect },
	vpn_options: { args: { kill_switch: false, allow_lan: false, route_mode: '', devices: [], destinations: [] }, call: vpn_options }
};

// For /usr/libexec/supacudy/vpn-dns.uc, run by hotplug as root.

// The DNS servers an OpenVPN server pushed when the tunnel came up.
function ovpn_pushed_dns(servers) {
	const cur = uci();
	if (profile_type(cur, cur.get('supacudy', 'vpn', 'active')) != 'openvpn')
		return;
	const list = uniq(filter(servers, is_ip));
	if (join(' ', list) == join(' ', as_list(cur.get('supacudy', 'vpn', 'pushed_dns'))))
		return;
	if (length(list))
		cur.set('supacudy', 'vpn', 'pushed_dns', list);
	else
		cur.delete('supacudy', 'vpn', 'pushed_dns');
	apply_dns(cur);
	apply_firewall(cur);
	for (let c in [ 'dhcp', 'firewall', 'supacudy' ])
		cur.commit(c);
	run_later(`/etc/init.d/dnsmasq restart; /etc/init.d/firewall reload; ${CLEAR_CACHE_CMD}`, 0);
}

// An uplink's DNS servers changed: the VPN server's name follows them.
function refresh_vpn_dns() {
	const cur = uci();
	if (!cur.get('supacudy', 'vpn', 'active') || !apply_dns(cur))
		return;
	apply_firewall(cur);
	for (let c in [ 'dhcp', 'firewall', 'supacudy' ])
		cur.commit(c);
	run_later('/etc/init.d/dnsmasq restart; /etc/init.d/firewall reload', 0);
}

export { methods, ovpn_pushed_dns, refresh_vpn_dns };
