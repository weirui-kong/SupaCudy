// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Things that happen on a timetable: a weekly reboot and Wi-Fi switched off
// at night (cron lines between our markers in root's crontab), and parental
// controls that keep chosen devices offline at set times (fw4 rules with
// start_time/stop_time/weekdays, named sc_parental_*).

'use strict';

import { readfile, writefile } from 'fs';
import { INVALID, NOT_FOUND, uci, run, run_later, fail, normalize_mac } from 'supacudy.util';

const CRONTAB = '/etc/crontabs/root';
const BEGIN = '# supacudy schedule begin';
const END = '# supacudy schedule end';
const DAYS = [ 'sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat' ];
const FW_DAYS = { sun: 'Sun', mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat' };
const PARENTAL_PREFIX = 'sc_parental_';
const RULES_MAX = 32;

function hhmm(s) {
	const m = type(s) == 'string' ? match(s, /^([01]\d|2[0-3]):([0-5]\d)$/) : null;
	return m ? { h: +m[1], m: +m[2] } : null;
}

function valid_days(days) {
	if (type(days) != 'array' || length(days) < 1 || length(days) > 7)
		return false;
	for (let d in days)
		if (!(d in DAYS))
			return false;
	return length(uniq(days)) == length(days);
}

function as_list(v) {
	return type(v) == 'array' ? v : (v ? split(v, ' ') : []);
}

function schedule(cur, name) {
	return {
		enabled: cur.get('supacudy', name, 'enabled') == '1',
		days: as_list(cur.get('supacudy', name, 'days') ?? 'sun mon tue wed thu fri sat'),
		start: cur.get('supacudy', name, 'start') ?? (name == 'reboot' ? '04:00' : '23:00'),
		end: cur.get('supacudy', name, 'end') ?? '07:00'
	};
}

function cron_days(days) {
	return join(',', map(days, (d) => index(DAYS, d)));
}

// Only fixed commands; times and days were validated above.
function write_crontab(cur) {
	const lines = [];
	const reboot = schedule(cur, 'reboot');
	if (reboot.enabled) {
		const t = hhmm(reboot.start);
		push(lines, `${t.m} ${t.h} * * ${cron_days(reboot.days)} /sbin/reboot`);
	}
	const wifi = schedule(cur, 'wifi_off');
	if (wifi.enabled) {
		const s = hhmm(wifi.start), e = hhmm(wifi.end);
		push(lines, `${s.m} ${s.h} * * ${cron_days(wifi.days)} /sbin/wifi down`);
		// The morning after a night that started on a chosen day.
		const next = map(wifi.days, (d) => DAYS[(index(DAYS, d) + (e.h * 60 + e.m <= s.h * 60 + s.m ? 1 : 0)) % 7]);
		push(lines, `${e.m} ${e.h} * * ${cron_days(uniq(next))} /sbin/wifi up`);
	}
	const kept = [];
	let inside = false;
	for (let l in split(readfile(CRONTAB) ?? '', '\n')) {
		if (l == BEGIN)
			inside = true;
		else if (l == END)
			inside = false;
		else if (!inside && l != '')
			push(kept, l);
	}
	if (length(lines))
		push(kept, BEGIN, ...lines, END);
	writefile(CRONTAB, length(kept) ? join('\n', kept) + '\n' : '');
	run('/etc/init.d/cron enable');
	run_later('/etc/init.d/cron restart', 1);
}

function parental_rules(cur) {
	const out = [];
	cur.foreach('firewall', 'rule', (s) => {
		if (substr(s['.name'], 0, length(PARENTAL_PREFIX)) != PARENTAL_PREFIX)
			return;
		push(out, {
			id: s['.name'],
			name: s.name ?? s['.name'],
			macs: as_list(s.src_mac),
			days: map(as_list(s.weekdays), (d) => lc(d)),
			start: substr(s.start_time ?? '00:00:00', 0, 5),
			end: substr(s.stop_time ?? '23:59:00', 0, 5),
			enabled: s.enabled != '0'
		});
	});
	return out;
}

function schedule_get() {
	const cur = uci();
	return {
		reboot: schedule(cur, 'reboot'),
		wifi_off: schedule(cur, 'wifi_off'),
		parental: parental_rules(cur)
	};
}

function schedule_set(req) {
	const a = req.args;
	if (!(a.kind in [ 'reboot', 'wifi_off' ]) || type(a.enabled) != 'bool' || !valid_days(a.days) || !hhmm(a.start) ||
	    (a.kind == 'wifi_off' && (!hhmm(a.end) || a.end == a.start)))
		return req.error(INVALID);
	const cur = uci();
	cur.set('supacudy', a.kind, 'schedule');
	cur.set('supacudy', a.kind, 'enabled', a.enabled ? '1' : '0');
	cur.set('supacudy', a.kind, 'days', join(' ', a.days));
	cur.set('supacudy', a.kind, 'start', a.start);
	if (a.kind == 'wifi_off')
		cur.set('supacudy', a.kind, 'end', a.end);
	cur.commit('supacudy');
	write_crontab(cur);
	return { applied: true };
}

function free_name(cur) {
	for (let i = 1; ; i++)
		if (!cur.get('firewall', `${PARENTAL_PREFIX}${i}`))
			return `${PARENTAL_PREFIX}${i}`;
}

// nftables matches an hour range that wraps past midnight ("22:00"-"06:30"),
// so a bedtime window needs only one rule.
function parental_set(req) {
	const a = req.args;
	if (type(a.id) != 'string' || type(a.name) != 'string' || length(a.name) < 1 || length(a.name) > 64 ||
	    match(a.name, /[[:cntrl:]'"]/) || type(a.macs) != 'array' || length(a.macs) < 1 || length(a.macs) > 32 ||
	    !valid_days(a.days) || !hhmm(a.start) || !hhmm(a.end) || a.start == a.end || type(a.enabled) != 'bool')
		return req.error(INVALID);
	const macs = map(a.macs, normalize_mac);
	if (length(filter(macs, (m) => m == null)))
		return req.error(INVALID);
	const cur = uci();
	if (a.id != '' && (substr(a.id, 0, length(PARENTAL_PREFIX)) != PARENTAL_PREFIX || cur.get('firewall', a.id) != 'rule'))
		return req.error(NOT_FOUND);
	if (a.id == '' && length(parental_rules(cur)) >= RULES_MAX)
		return fail('too_many_rules');
	const id = a.id != '' ? a.id : free_name(cur);
	cur.set('firewall', id, 'rule');
	cur.set('firewall', id, 'name', a.name);
	cur.set('firewall', id, 'src', 'lan');
	cur.set('firewall', id, 'dest', 'wan');
	cur.set('firewall', id, 'src_mac', uniq(macs));
	cur.set('firewall', id, 'proto', 'all');
	cur.set('firewall', id, 'weekdays', join(' ', map(a.days, (d) => FW_DAYS[d])));
	cur.set('firewall', id, 'start_time', `${a.start}:00`);
	cur.set('firewall', id, 'stop_time', `${a.end}:00`);
	cur.set('firewall', id, 'target', 'REJECT');
	cur.set('firewall', id, 'enabled', a.enabled ? '1' : '0');
	cur.commit('firewall');
	run_later('/etc/init.d/firewall reload', 1);
	return { id };
}

function parental_delete(req) {
	const id = req.args.id;
	if (type(id) != 'string')
		return req.error(INVALID);
	const cur = uci();
	if (substr(id, 0, length(PARENTAL_PREFIX)) != PARENTAL_PREFIX || cur.get('firewall', id) != 'rule')
		return req.error(NOT_FOUND);
	cur.delete('firewall', id);
	cur.commit('firewall');
	run_later('/etc/init.d/firewall reload', 1);
	return { deleted: true };
}

const methods = {
	schedule_get: { call: schedule_get },
	schedule_set: { args: { kind: '', enabled: false, days: [], start: '', end: '' }, call: schedule_set },
	parental_set: { args: { id: '', name: '', macs: [], days: [], start: '', end: '', enabled: false }, call: parental_set },
	parental_delete: { args: { id: '' }, call: parental_delete }
};

export { methods };
