// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// AdGuard Home as the router's DNS: clients ask AdGuard Home on port 53,
// which filters and forwards to dnsmasq, moved to port 5353. dnsmasq keeps
// doing everything else (local names, the DNS modes in dns.uc, VPN DNS), so
// those keep working with filtering in front of them.
//
// AdGuard Home's own configuration is the only source of truth: settings
// are read and changed through its API, so changes made on its own web page
// show up here and are never overwritten. /etc/config/supacudy only says
// whether it is the router's DNS.

'use strict';

import { access, readfile, writefile, unlink, mkdir, chmod, popen } from 'fs';
import { INVALID, uci, run, run_later, fail } from 'supacudy.util';

const YAML = '/etc/adguardhome.yaml';
const API = 'http://127.0.0.1:3000/control';
const DNSMASQ_PORT = '5353';
// Advertise this router as DNS server; dnsmasq stops doing so on its own
// once it no longer listens on port 53.
const DNS_OPTION = '6,0.0.0.0';
// One password for everything with a login: AdGuard Home's user is root
// with the admin password. Its API needs that login too, so the password
// is kept for curl, and the root shadow entry it belongs to is recorded to
// notice a change made outside SupaCudy. All root-only.
const LOGIN_DIR = '/etc/supacudy';
const CURL_AUTH = `${LOGIN_DIR}/adguard.curl`;
const LOGIN_HASH = `${LOGIN_DIR}/adguard.bcrypt`;
const LOGIN_SHADOW = `${LOGIN_DIR}/adguard.shadow`;
const REQUEST = '/var/run/supacudy/adguard-request.json';
const WEB_USER = 'root';
const WEB_PORT = 3000;
const RULES_MAX = 2000;
const BCRYPT_RE = /^\$2[aby]\$[0-9][0-9]\$[.\/A-Za-z0-9]{53}$/;

// Suggested lists from AdGuard's own registry.
const CATALOG = [
	{ name: 'AdGuard DNS filter', url: 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt' },
	{ name: 'AdAway Default Blocklist', url: 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt' }
];

function installed() {
	return access('/usr/bin/AdGuardHome', 'x') ?? false;
}

function as_list(v) {
	return type(v) == 'array' ? v : (v ? [ v ] : []);
}

function enabled(cur) {
	return cur.get('supacudy', 'adguard', 'enabled') == '1';
}

// Only used when there is no configuration yet; AdGuard Home fills in the
// rest and owns the file from then on.
function initial_yaml() {
	const hash = trim(readfile(LOGIN_HASH) ?? '');
	return join('\n', [
		'http:', `  address: 127.0.0.1:${WEB_PORT}`,
		...(match(hash, BCRYPT_RE) ? [ 'users:', `  - name: ${WEB_USER}`, `    password: ${sprintf('%J', hash)}` ] : [ 'users: []' ]),
		'dns:', '  bind_hosts:', '    - 0.0.0.0', '  port: 53',
		'  upstream_dns:', `    - 127.0.0.1:${DNSMASQ_PORT}`, '  bootstrap_dns: []',
		'filtering:', '  protection_enabled: true', '  filtering_enabled: true',
		'filters:',
		'  - enabled: true', `    url: ${CATALOG[0].url}`, `    name: ${CATALOG[0].name}`, '    id: 1',
		'user_rules: []',
		'schema_version: 29', ''
	]);
}

// The request body goes through a file so no request data reaches the
// shell. Returns null when AdGuard Home did not answer or refused.
function api(path, body, timeout) {
	let cmd = `curl -s -f -m ${int(timeout ?? 8)}`;
	if (access(CURL_AUTH))
		cmd += ` -K ${CURL_AUTH}`;
	if (body != null) {
		mkdir('/var/run/supacudy');
		writefile(REQUEST, sprintf('%J', body));
		cmd += ` -H 'Content-Type: application/json' --data-binary @${REQUEST}`;
	}
	const p = popen(`${cmd} ${API}/${path} 2>/dev/null`);
	const out = p ? p.read('all') : null;
	const code = p ? p.close() : -1;
	if (body != null)
		unlink(REQUEST);
	if (code != 0)
		return null;
	try {
		return json(out);
	} catch {
		// Changes answer with plain text such as "OK".
		return {};
	}
}

function dhcp_sections(cur) {
	const out = [];
	cur.foreach('dhcp', 'dhcp', (s) => {
		if (s.interface && s.ignore != '1')
			push(out, s['.name']);
	});
	return out;
}

// Also used when a DHCP pool is added later (the guest network).
function dns_option(cur, section) {
	const on = enabled(cur) && installed();
	const opts = filter(as_list(cur.get('dhcp', section, 'dhcp_option')), (o) => o != DNS_OPTION);
	if (on)
		push(opts, DNS_OPTION);
	if (length(opts))
		cur.set('dhcp', section, 'dhcp_option', opts);
	else
		cur.delete('dhcp', section, 'dhcp_option');
}

function dnsmasq_section(cur) {
	let name = null;
	cur.foreach('dhcp', 'dnsmasq', (s) => {
		name ??= s['.name'];
	});
	return name;
}

// Writes the DNS chain for the current on/off state and returns the
// command that applies it.
function apply(cur) {
	const on = enabled(cur) && installed();
	const dm = dnsmasq_section(cur);
	if (on && !access(YAML))
		writefile(YAML, initial_yaml());
	if (dm) {
		if (on)
			cur.set('dhcp', dm, 'port', DNSMASQ_PORT);
		else
			cur.delete('dhcp', dm, 'port');
	}
	for (let section in dhcp_sections(cur))
		dns_option(cur, section);
	cur.commit('dhcp');
	cur.commit('supacudy');
	return on
		? '/etc/init.d/dnsmasq restart; /etc/init.d/adguardhome enable; /etc/init.d/adguardhome restart'
		: '/etc/init.d/adguardhome stop; /etc/init.d/adguardhome disable; /etc/init.d/dnsmasq restart';
}

// Only the web address and the users are touched, line by line, so the
// rest of the file stays exactly as AdGuard Home wrote it.
function top_key(line) {
	return match(line, /^([a-z_]+):/)?.[1];
}

function yaml_web(text) {
	let address = null, section = null;
	const users = [];
	for (let l in split(text ?? '', '\n')) {
		section = top_key(l) ?? section;
		const a = section == 'http' ? match(l, /^  address: *"?([^" ]+)"?/) : null;
		const u = section == 'users' ? match(l, /^  - name: *"?([^"]+)"?/) : null;
		if (a)
			address = a[1];
		if (u)
			push(users, u[1]);
	}
	return { address, users };
}

function yaml_set_web(text, address, users) {
	const out = [];
	let section = null;
	for (let l in split(text, '\n')) {
		const key = top_key(l);
		section = key ?? section;
		if (key == 'users') {
			push(out, length(users) ? 'users:' : 'users: []');
			for (let u in users)
				push(out, `  - name: ${sprintf('%J', u.name)}`, `    password: ${sprintf('%J', u.hash)}`);
			continue;
		}
		if (section == 'users')
			continue;
		push(out, section == 'http' && match(l, /^  address:/) ? `  address: ${address}` : l);
	}
	return join('\n', out);
}

function root_shadow_hash() {
	for (let line in split(readfile('/etc/shadow') ?? '', '\n')) {
		const f = split(line, ':');
		if (f[0] == 'root')
			return f[1] ?? '';
	}
	return '';
}

function web_state() {
	const w = yaml_web(readfile(YAML));
	const open = w.address != null && substr(w.address, 0, 10) != '127.0.0.1:';
	const recorded = readfile(LOGIN_SHADOW);
	return {
		enabled: open && length(w.users) > 0,
		user: w.users[0] ?? null,
		port: WEB_PORT,
		// False once the admin password changed without SupaCudy (passwd,
		// LuCI): AdGuard Home still has the old one until it is entered here.
		synced: recorded != null && recorded == root_shadow_hash() && WEB_USER in w.users
	};
}

function valid_password(pw) {
	return type(pw) == 'string' && length(pw) >= 8 && length(pw) <= 128 && !match(pw, /[[:cntrl:]]/);
}

function valid_hash(hash) {
	return type(hash) == 'string' && match(hash, BCRYPT_RE) != null;
}

function write_private(path, content) {
	mkdir(LOGIN_DIR);
	chmod(LOGIN_DIR, 0700);
	writefile(path, '');
	chmod(path, 0600);
	writefile(path, content);
}

// AdGuard Home writes its file back from memory, so it is stopped while
// the file is edited. address null keeps the current one.
// On first boot nothing runs yet, so there is nothing to restart.
function rewrite_yaml(address, hash, restart) {
	if (!access(YAML))
		return;
	if (restart ?? true)
		run('/etc/init.d/adguardhome stop');
	const text = readfile(YAML);
	writefile(YAML, yaml_set_web(text, address ?? yaml_web(text).address ?? `127.0.0.1:${WEB_PORT}`,
		hash ? [ { name: WEB_USER, hash } ] : []));
	if ((restart ?? true) && enabled(uci()))
		run('/etc/init.d/adguardhome start');
}

// Called whenever the admin password is set, with the bcrypt hash the
// browser made of it.
function sync_login(password, hash, restart) {
	write_private(LOGIN_HASH, hash);
	const quoted = replace(replace(password, '\\', '\\\\'), '"', '\\"');
	write_private(CURL_AUTH, `user = "${WEB_USER}:${quoted}"\n`);
	write_private(LOGIN_SHADOW, root_shadow_hash());
	rewrite_yaml(null, hash, restart);
}

// The factory login (see 91-supacudy-defaults in supacudy-base). The hash
// is of a published password, so its fixed salt gives nothing away.
const DEFAULT_PASSWORD = 'supacudy';
const DEFAULT_HASH = '$2b$10$SYZ4xAKPnDz2PNN8Ojxy3e7bd6HhPkmf/dbOhVRRwDjfVJ0zvl3dO';

function default_password_in_use() {
	const recorded = trim(readfile(`${LOGIN_DIR}/default-password`) ?? '');
	return recorded != '' && recorded == root_shadow_hash();
}

function fallback_active() {
	try {
		return json(readfile('/var/run/supacudy/rescue.json') ?? '{}')?.dns_fallback == true;
	} catch {
		return false;
	}
}

function top(list, n) {
	return map(slice(list ?? [], 0, n), (e) => {
		const k = keys(e)[0];
		return { name: k, count: e[k] };
	});
}

function adguard_get() {
	const on = enabled(uci()) && installed();
	const status = on ? api('status') : null;
	const filtering = status ? api('filtering/status') : null;
	const stats = status ? api('stats') : null;
	const lists = map(filtering?.filters ?? [], (f) => ({
		name: f.name, url: f.url, enabled: f.enabled == true, rules: f.rules_count ?? null
	}));
	const web = web_state();
	return {
		installed: installed(),
		enabled: on,
		running: status?.running ?? false,
		// The page has a login we do not know (set up outside SupaCudy).
		locked: on && !status && web.enabled && !access(CURL_AUTH),
		// The rescue watcher answers DNS without filtering while it is down.
		fallback: fallback_active(),
		// Null while AdGuard Home does not answer: nothing is guessed.
		protection: status ? status.protection_enabled == true : null,
		filters: filtering ? lists : null,
		suggested: filter(CATALOG, (c) => !length(filter(lists, (f) => f.url == c.url))),
		rules: filtering ? as_list(filtering.user_rules) : null,
		web,
		stats: stats ? {
			queries: stats.num_dns_queries ?? 0,
			blocked: stats.num_blocked_filtering ?? 0,
			avg_ms: int((stats.avg_processing_time ?? 0) * 1000),
			top_blocked: top(stats.top_blocked_domains, 5),
			top_clients: top(stats.top_clients, 5)
		} : null
	};
}

function valid_url(u) {
	return type(u) == 'string' && length(u) <= 512 && match(u, /^https?:\/\/[A-Za-z0-9.-]+(:[0-9]+)?\/[!-~]*$/) != null;
}

function valid_text(s, max) {
	return type(s) == 'string' && length(s) >= 1 && length(s) <= max && !match(s, /[[:cntrl:]]/);
}

function adguard_set(req) {
	if (type(req.args.enabled) != 'bool')
		return req.error(INVALID);
	if (req.args.enabled && !installed())
		return fail('adguard_missing');
	const cur = uci();
	if (!cur.get('supacudy', 'adguard'))
		cur.set('supacudy', 'adguard', 'adguard');
	cur.set('supacudy', 'adguard', 'enabled', req.args.enabled ? '1' : '0');
	run_later(apply(cur), 1);
	return { applied: true };
}

// Each returns INVALID, an error reply, or the API call that makes the
// change.
const CHANGES = {
	adguard_protection: (a) => type(a.enabled) != 'bool' ? INVALID
		: () => api('protection', { enabled: a.enabled }),
	// AdGuard Home downloads the list before it answers.
	adguard_list_add: (a) => !valid_url(a.url) ? fail('filter_url_invalid', { value: `${a.url}` })
		: !valid_text(a.name, 128) ? INVALID
		: () => api('filtering/add_url', { name: a.name, url: a.url, whitelist: false }, 60),
	adguard_list_set: (a) => !valid_url(a.url) || !valid_text(a.name, 128) || type(a.enabled) != 'bool' ? INVALID
		: () => api('filtering/set_url', { url: a.url, whitelist: false, data: { name: a.name, url: a.url, enabled: a.enabled } }, 60),
	adguard_list_remove: (a) => !valid_url(a.url) ? INVALID
		: () => api('filtering/remove_url', { url: a.url, whitelist: false }),
	adguard_rules_set: (a) => {
		if (type(a.rules) != 'array' || length(a.rules) > RULES_MAX)
			return INVALID;
		for (let r in a.rules)
			if (!valid_text(r, 1024))
				return fail('rule_invalid', { value: `${r}` });
		return () => api('filtering/set_rules', { rules: a.rules });
	}
};

function change_method(name) {
	return function(req) {
		const change = CHANGES[name](req.args);
		if (change == INVALID)
			return req.error(INVALID);
		if (type(change) == 'object')
			return change;
		if (!enabled(uci()) || !api('status')?.running)
			return fail('adguard_not_running');
		return change() == null ? fail('adguard_refused') : { applied: true };
	};
}

// Opening the page needs the admin password once if AdGuard Home does
// not have it yet; the browser has checked it and made the hash.
function adguard_web_set(req) {
	const a = req.args;
	if (type(a.enabled) != 'bool' || type(a.password) != 'string' || type(a.hash) != 'string')
		return req.error(INVALID);
	const with_login = a.password != '';
	if (with_login && (!valid_password(a.password) || !valid_hash(a.hash)))
		return req.error(INVALID);
	if (!enabled(uci()) || !access(YAML))
		return fail('adguard_not_running');
	if (with_login)
		sync_login(a.password, a.hash);
	else if (a.enabled && !web_state().synced)
		return fail('password_needed');
	rewrite_yaml(`${a.enabled ? '0.0.0.0' : '127.0.0.1'}:${WEB_PORT}`, trim(readfile(LOGIN_HASH) ?? ''));
	return { applied: true };
}

// First boot, and upgrades from before AdGuard Home was the default.
function apply_defaults() {
	if (default_password_in_use() && !access(LOGIN_HASH))
		sync_login(DEFAULT_PASSWORD, DEFAULT_HASH, false);
	const cur = uci();
	if (cur.get('supacudy', 'adguard') || !installed())
		return;
	cur.set('supacudy', 'adguard', 'adguard');
	cur.set('supacudy', 'adguard', 'enabled', '1');
	apply(cur);
}

const methods = {
	adguard_get: { call: adguard_get },
	adguard_set: { args: { enabled: false }, call: adguard_set },
	adguard_protection: { args: { enabled: false }, call: change_method('adguard_protection') },
	adguard_list_add: { args: { url: '', name: '' }, call: change_method('adguard_list_add') },
	adguard_list_set: { args: { url: '', name: '', enabled: false }, call: change_method('adguard_list_set') },
	adguard_list_remove: { args: { url: '' }, call: change_method('adguard_list_remove') },
	adguard_rules_set: { args: { rules: [] }, call: change_method('adguard_rules_set') },
	adguard_web_set: { args: { enabled: false, password: '', hash: '' }, call: adguard_web_set }
};

export { methods, dns_option, apply_defaults, sync_login, valid_hash, default_password_in_use };
