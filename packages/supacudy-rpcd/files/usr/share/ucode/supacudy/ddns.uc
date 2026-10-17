// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Dynamic DNS through ddns-scripts and a third-party provider: keeps a name
// pointing at the router's public address, for reaching it from outside.
// One entry, ddns.supacudy; others made in LuCI are left alone.

'use strict';

import { lsdir, readfile } from 'fs';
import { INVALID, uci, run_later, fail } from 'supacudy.util';

const SECTION = 'supacudy';
const SERVICES_DIR = '/usr/share/ddns/default';
const HOST_RE = /^[A-Za-z0-9]([A-Za-z0-9-]{0,62})(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}))+$/;

// ddns-scripts ships one JSON description per provider.
function services() {
	return sort(map(filter(lsdir(SERVICES_DIR) ?? [], (f) => match(f, /\.json$/)), (f) => replace(f, /\.json$/, '')));
}

function read_number(path) {
	const s = trim(readfile(path) ?? '');
	return match(s, /^\d+$/) ? +s : 0;
}

function ddns_get() {
	const cur = uci();
	const s = cur.get_all('ddns', SECTION) ?? {};
	return {
		available: length(services()) > 0,
		services: services(),
		enabled: s.enabled == '1',
		service: s.service_name ?? '',
		domain: s.domain ?? '',
		username: s.username ?? '',
		has_password: !!s.password,
		// ddns-scripts writes these while it runs.
		last_update: read_number(`/var/run/ddns/${SECTION}.update`),
		ip: trim(readfile(`/var/run/ddns/${SECTION}.ip`) ?? '') || null
	};
}

function ddns_set(req) {
	const a = req.args;
	if (type(a.enabled) != 'bool' || type(a.service) != 'string' || type(a.domain) != 'string' ||
	    type(a.username) != 'string' || type(a.password) != 'string' || length(a.username) > 256 || length(a.password) > 256 ||
	    match(a.username + a.password, /[[:cntrl:]]/))
		return req.error(INVALID);
	const cur = uci();
	if (!a.enabled) {
		if (cur.get('ddns', SECTION))
			cur.set('ddns', SECTION, 'enabled', '0');
		cur.commit('ddns');
		run_later('/etc/init.d/ddns restart', 1);
		return { applied: true };
	}
	if (!(a.service in services()))
		return fail('ddns_service_unknown');
	if (length(a.domain) > 253 || !match(a.domain, HOST_RE))
		return fail('ddns_domain_invalid');
	const old_password = cur.get('ddns', SECTION, 'password');
	if (a.password == '' && !old_password)
		return fail('ddns_password_missing');

	cur.set('ddns', SECTION, 'service');
	cur.set('ddns', SECTION, 'enabled', '1');
	cur.set('ddns', SECTION, 'service_name', a.service);
	cur.set('ddns', SECTION, 'domain', a.domain);
	cur.set('ddns', SECTION, 'lookup_host', a.domain);
	cur.set('ddns', SECTION, 'username', a.username);
	cur.set('ddns', SECTION, 'password', a.password != '' ? a.password : old_password);
	// Behind a hotel or carrier NAT the WAN address is private, so ask a web
	// service for the public one.
	cur.set('ddns', SECTION, 'ip_source', 'web');
	cur.set('ddns', SECTION, 'interface', 'wan');
	cur.set('ddns', SECTION, 'use_ipv6', '0');
	cur.commit('ddns');
	run_later('/etc/init.d/ddns enable; /etc/init.d/ddns restart', 1);
	return { applied: true };
}

const methods = {
	ddns_get: { call: ddns_get },
	ddns_set: { args: { enabled: false, service: '', domain: '', username: '', password: '' }, call: ddns_set }
};

export { methods };
