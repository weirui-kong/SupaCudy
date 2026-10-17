// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Which DNS servers the router's dnsmasq asks: the provider's (automatic),
// servers typed by the user (manual), or DNS over HTTPS through
// https-dns-proxy (encrypted); rebind protection; and local host names
// (dnsmasq "domain" sections).

'use strict';

import { access } from 'fs';
import { INVALID, NOT_FOUND, uci, run, run_later, fail, ipv4_to_int } from 'supacudy.util';

const MODES = ['auto', 'manual', 'encrypted'];
const PROXY = '/etc/init.d/https-dns-proxy';
const PROXY_PORT = '5053';
const SERVERS_MAX = 4;
const HOSTS_MAX = 128;
const HOSTNAME_RE = /^[A-Za-z0-9]([A-Za-z0-9-]{0,62})(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}))*$/;

// Bootstrap servers resolve the DoH host name itself.
// The first one is the default. AliDNS is addressed by IP, so it works
// before any name can be resolved.
const DEFAULT_PROVIDER = 'alidns';
const PROVIDERS = {
	alidns: { url: 'https://223.5.5.5/dns-query', bootstrap: '223.5.5.5,223.6.6.6' },
	cloudflare: { url: 'https://cloudflare-dns.com/dns-query', bootstrap: '1.1.1.1,1.0.0.1' },
	google: { url: 'https://dns.google/dns-query', bootstrap: '8.8.8.8,8.8.4.4' },
	quad9: { url: 'https://dns.quad9.net/dns-query', bootstrap: '9.9.9.9,149.112.112.112' },
	adguard: { url: 'https://dns.adguard-dns.com/dns-query', bootstrap: '94.140.14.14,94.140.15.15' },
	dnspod: { url: 'https://doh.pub/dns-query', bootstrap: '119.29.29.29,182.254.116.116' }
};

function dnsmasq_section(cur) {
	let name = null;
	cur.foreach('dhcp', 'dnsmasq', (s) => {
		name ??= s['.name'];
	});
	return name;
}

function as_list(v) {
	return type(v) == 'array' ? v : (v ? [ v ] : []);
}

function hosts(cur) {
	const out = [];
	cur.foreach('dhcp', 'domain', (s) => {
		if (s.name && s.ip)
			push(out, { id: s['.name'], name: s.name, ip: s.ip });
	});
	return out;
}

function dns_get() {
	const cur = uci();
	const provider = cur.get('supacudy', 'dns', 'provider') ?? DEFAULT_PROVIDER;
	return {
		mode: cur.get('supacudy', 'dns', 'mode') ?? 'auto',
		servers: as_list(cur.get('supacudy', 'dns', 'server')),
		provider,
		url: cur.get('supacudy', 'dns', 'url') ?? '',
		providers: keys(PROVIDERS),
		encrypted_available: access(PROXY, 'x') ?? false,
		rebind_protection: cur.get('dhcp', dnsmasq_section(cur) ?? '', 'rebind_protection') != '0',
		hosts: hosts(cur)
	};
}


// Rebind protection drops answers that point public names at private
// addresses, which blocks attacks on the LAN from web pages.
function dns_rebind_set(req) {
	if (type(req.args.enabled) != 'bool')
		return req.error(INVALID);
	const cur = uci();
	const section = dnsmasq_section(cur);
	if (!section)
		return req.error(NOT_FOUND);
	cur.set('dhcp', section, 'rebind_protection', req.args.enabled ? '1' : '0');
	cur.commit('dhcp');
	run_later('/etc/init.d/dnsmasq restart', 1);
	return { applied: true };
}

function host_set(req) {
	const a = req.args;
	if (type(a.id) != 'string' || type(a.name) != 'string' || length(a.name) > 253 || !match(a.name, HOSTNAME_RE) ||
	    ipv4_to_int(a.ip) == null)
		return req.error(INVALID);
	const cur = uci();
	if (a.id != '' && cur.get('dhcp', a.id) != 'domain')
		return req.error(NOT_FOUND);
	for (let h in hosts(cur))
		if (h.id != a.id && lc(h.name) == lc(a.name))
			return fail('host_exists');
	if (a.id == '' && length(hosts(cur)) >= HOSTS_MAX)
		return fail('too_many_rules');
	const id = a.id != '' ? a.id : cur.add('dhcp', 'domain');
	cur.set('dhcp', id, 'name', a.name);
	cur.set('dhcp', id, 'ip', a.ip);
	cur.commit('dhcp');
	run_later('/etc/init.d/dnsmasq reload', 1);
	return { id };
}

function host_delete(req) {
	const id = req.args.id;
	if (type(id) != 'string')
		return req.error(INVALID);
	const cur = uci();
	if (cur.get('dhcp', id) != 'domain')
		return req.error(NOT_FOUND);
	cur.delete('dhcp', id);
	cur.commit('dhcp');
	run_later('/etc/init.d/dnsmasq reload', 1);
	return { deleted: true };
}

// Remove exactly the servers we added, keeping any the user set elsewhere.
function drop_our_servers(cur, section) {
	const ours = as_list(cur.get('supacudy', 'dns', 'server'));
	const kept = filter(as_list(cur.get('dhcp', section, 'server')), (s) => !(s in ours));
	if (length(kept))
		cur.set('dhcp', section, 'server', kept);
	else
		cur.delete('dhcp', section, 'server');
	if (cur.get('supacudy', 'dns', 'mode') == 'manual')
		cur.delete('dhcp', section, 'noresolv');
}

function valid_url(url) {
	return type(url) == 'string' && length(url) <= 256 && match(url, /^https:\/\/[A-Za-z0-9.-]+(:\d+)?\/[!-~]*$/) != null;
}

function dns_set(req) {
	const a = req.args;
	if (!(a.mode in MODES) || type(a.servers) != 'array' || length(a.servers) > SERVERS_MAX ||
	    type(a.provider) != 'string' || type(a.url) != 'string')
		return req.error(INVALID);
	for (let s in a.servers)
		if (ipv4_to_int(s) == null)
			return req.error(INVALID);
	if (a.mode == 'manual' && !length(a.servers))
		return req.error(INVALID);
	if (a.mode == 'encrypted') {
		if (!access(PROXY, 'x'))
			return fail('encrypted_unavailable');
		if (a.provider != 'custom' && !PROVIDERS[a.provider])
			return req.error(INVALID);
		if (a.provider == 'custom' && !valid_url(a.url))
			return fail('doh_url_invalid');
	}

	// The proxy edits dnsmasq's config itself when it starts and restores it
	// when it stops, so stop it before touching that config.
	if (access(PROXY, 'x'))
		run(`${PROXY} stop; ${PROXY} disable`);

	const cur = uci();
	const section = dnsmasq_section(cur);
	if (!section)
		return req.error(NOT_FOUND);
	if (!cur.get('supacudy', 'dns'))
		cur.set('supacudy', 'dns', 'dns');
	drop_our_servers(cur, section);

	cur.set('supacudy', 'dns', 'mode', a.mode);
	cur.delete('supacudy', 'dns', 'server');
	if (a.mode == 'manual') {
		cur.set('supacudy', 'dns', 'server', a.servers);
		cur.set('dhcp', section, 'server', [ ...as_list(cur.get('dhcp', section, 'server')), ...a.servers ]);
		cur.set('dhcp', section, 'noresolv', '1');
	}
	if (a.mode == 'encrypted') {
		cur.set('supacudy', 'dns', 'provider', a.provider);
		cur.set('supacudy', 'dns', 'url', a.provider == 'custom' ? a.url : '');
		const p = a.provider == 'custom' ? { url: a.url, bootstrap: '223.5.5.5,119.29.29.29' } : PROVIDERS[a.provider];
		cur.foreach('https-dns-proxy', 'https-dns-proxy', (s) => {
			cur.delete('https-dns-proxy', s['.name']);
		});
		const name = cur.add('https-dns-proxy', 'https-dns-proxy');
		cur.set('https-dns-proxy', name, 'resolver_url', p.url);
		cur.set('https-dns-proxy', name, 'bootstrap_dns', p.bootstrap);
		cur.set('https-dns-proxy', name, 'listen_port', PROXY_PORT);
		cur.commit('https-dns-proxy');
	}
	cur.commit('dhcp');
	cur.commit('supacudy');
	run_later(a.mode == 'encrypted'
		? `${PROXY} enable; ${PROXY} restart`
		: '/etc/init.d/dnsmasq restart', 1);
	return { applied: true };
}

const methods = {
	dns_get: { call: dns_get },
	dns_set: { args: { mode: '', servers: [], provider: '', url: '' }, call: dns_set },
	dns_rebind_set: { args: { enabled: false }, call: dns_rebind_set },
	host_set: { args: { id: '', name: '', ip: '' }, call: host_set },
	host_delete: { args: { id: '' }, call: host_delete }
};

export { methods };
