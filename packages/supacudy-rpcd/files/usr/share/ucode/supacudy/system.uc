// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Device information, live status, time, admin password and maintenance
// (reboot, factory reset, firmware upgrade).

'use strict';

import { readfile, popen, stat, unlink } from 'fs';
import zoneinfo from 'luci.zoneinfo';
import { sync_login, valid_hash, default_password_in_use } from 'supacudy.adguard';
import { INVALID, NOT_FOUND, ubus, uci, read_trimmed, run, run_later, fail } from 'supacudy.util';

// cgi-io writes uploads here; the ACL grants the UI write access to this path only.
const FIRMWARE = '/tmp/firmware.bin';
// Clocks before this are unset (no RTC, no NTP yet), after it a typo.
const TIME_MIN = 1704067200;
const TIME_MAX = 4102444800;

function openwrt_release() {
	const rel = {};

	for (let line in split(readfile('/etc/openwrt_release') || '', '\n')) {
		const m = match(line, /^([A-Z_]+)='?([^']*)'?$/);
		if (m)
			rel[m[1]] = m[2];
	}

	return rel;
}

// Values come straight from /proc rather than procd's system.info so the
// method also works where procd is not running (the test container).
function meminfo() {
	const kib = {};

	for (let line in split(readfile('/proc/meminfo') || '', '\n')) {
		const m = match(line, /^(\w+):\s+(\d+) kB$/);
		if (m)
			kib[m[1]] = +m[2];
	}

	return {
		total: (kib.MemTotal ?? 0) * 1024,
		available: (kib.MemAvailable ?? kib.MemFree ?? 0) * 1024
	};
}

// ucode has no statvfs; df's last line is "<fs> <total> <used> <avail> ...".
// /overlay holds the user's data on flash; images without one use /.
function storage() {
	const r = run('df -k /overlay 2>/dev/null || df -k /');
	const lines = filter(split(trim(r.out), '\n'), length);
	const f = split(replace(lines[-1] ?? '', /\s+/g, ' '), ' ');
	if (r.code != 0 || length(f) < 4 || !match(f[1], /^\d+$/))
		return null;
	return { total: +f[1] * 1024, available: +f[3] * 1024 };
}

function cpu_count() {
	let count = 0;

	for (let line in split(readfile('/proc/cpuinfo') || '', '\n'))
		if (match(line, /^processor\s*:/))
			count++;

	return count || 1;
}

// Fresh OpenWrt leaves root's shadow field empty; LuCI then logs in
// without a password.
function root_password_set() {
	for (let line in split(readfile('/etc/shadow') ?? '', '\n')) {
		const f = split(line, ':');
		if (f[0] == 'root')
			return length(f[1] ?? '') > 0;
	}
	return false;
}

// Written by the rescue watcher (supacudy-base); runtime only.
function rescue_state() {
	let s = null;
	try {
		s = json(readfile('/var/run/supacudy/rescue.json') ?? 'null');
	} catch {
		s = null;
	}
	if (!s?.active)
		return { active: false, address: null, ssid: null, since: null };
	return { active: true, address: s.dhcp?.address ?? null, ssid: s.wifi?.ssid ?? null, since: s.since ?? null };
}

function system_section(cur) {
	let name = null;
	cur.foreach('system', 'system', (s) => {
		name ??= s['.name'];
	});
	return name;
}

function time_get() {
	const cur = uci();
	const sys = system_section(cur);
	return {
		time: time(),
		zonename: (sys ? cur.get('system', sys, 'zonename') : null) ?? 'UTC',
		ntp: cur.get('system', 'ntp', 'enabled') != '0',
		zones: [ 'UTC', ...sort(keys(zoneinfo)) ]
	};
}

function time_set(req) {
	const a = req.args;
	if (type(a.zonename) != 'string' || type(a.ntp) != 'bool' || type(a.time) != 'int' ||
	    (a.zonename != 'UTC' && zoneinfo[a.zonename] == null) ||
	    (a.time != 0 && (a.time < TIME_MIN || a.time > TIME_MAX)))
		return req.error(INVALID);
	const cur = uci();
	const sys = system_section(cur);
	if (!sys)
		return req.error(NOT_FOUND);
	cur.set('system', sys, 'zonename', a.zonename);
	cur.set('system', sys, 'timezone', a.zonename == 'UTC' ? 'UTC' : zoneinfo[a.zonename]);
	if (!cur.get('system', 'ntp'))
		cur.set('system', 'ntp', 'timeserver');
	cur.set('system', 'ntp', 'enabled', a.ntp ? '1' : '0');
	cur.commit('system');
	if (a.time)
		run(`date -s @${int(a.time)}`);
	run_later('/etc/init.d/system reload; /etc/init.d/sysntpd restart', 1);
	return { applied: true };
}

// The caller already proved the current password by logging in; the UI
// asks for it again before calling this (see verifyPassword in the UI).
// One password for every login: the browser also sends the bcrypt hash
// AdGuard Home needs, which the router cannot compute.
function password_set(req) {
	const pw = req.args.password;
	if (type(pw) != 'string' || !valid_hash(req.args.hash))
		return req.error(INVALID);
	if (length(pw) < 8 || length(pw) > 128 || match(pw, /[[:cntrl:]]/))
		return fail('password_invalid');
	const p = popen('passwd root >/dev/null 2>&1', 'w');
	if (!p)
		return fail('password_failed');
	p.write(`${pw}\n${pw}\n`);
	if (p.close() != 0)
		return fail('password_failed');
	sync_login(pw, req.args.hash);
	return { changed: true };
}

// procd answers with an error instead of a verdict for images the platform
// check aborts on (armsr does this), so no answer means "cannot install".
function firmware_state() {
	const st = stat(FIRMWARE);
	if (!st)
		return null;
	const v = ubus().call('system', 'validate_firmware_image', { path: FIRMWARE });
	return {
		valid: v?.valid ?? false,
		forceable: v?.forceable ?? false,
		allow_backup: v?.allow_backup ?? false,
		size: st.size
	};
}

const LOG_LINES_MAX = 2000;

// logread lines look like "Sat Oct 17 04:18:29 2026 daemon.notice netifd: ...".
function parse_log_line(line) {
	const m = match(line, /^(\w{3} \w{3} +\d+ \d\d:\d\d:\d\d \d{4}) (\w+)\.(\w+) ([^:]+): (.*)$/);
	if (!m)
		return { time: null, facility: null, level: null, source: null, message: line };
	return { time: m[1], facility: m[2], level: m[3], source: m[4], message: m[5] };
}

function log_get(req) {
	const lines = req.args.lines;
	if (type(lines) != 'int' || lines < 1 || lines > LOG_LINES_MAX)
		return req.error(INVALID);
	const r = run(`logread -l ${int(lines)}`);
	return { entries: map(filter(split(r.out, '\n'), length), parse_log_line) };
}

const methods = {
	info: {
		call: function() {
			const rel = openwrt_release();

			return {
				version: read_trimmed('/etc/supacudy_version'),
				openwrt: rel.DISTRIB_RELEASE,
				revision: rel.DISTRIB_REVISION,
				board: read_trimmed('/tmp/sysinfo/board_name'),
				model: read_trimmed('/tmp/sysinfo/model')
			};
		}
	},

	status: {
		call: function() {
			const uptime = split(read_trimmed('/proc/uptime') || '0', ' ');
			const load = split(read_trimmed('/proc/loadavg') || '0 0 0', ' ');

			return {
				uptime: int(+uptime[0]),
				load: [ +load[0], +load[1], +load[2] ],
				cpus: cpu_count(),
				memory: meminfo(),
				storage: storage()
			};
		}
	},

	setup_status: {
		call: function() {
			const done = uci().get('supacudy', 'main', 'setup_done') == '1';
			return {
				setup_done: done,
				password_set: root_password_set(),
				// Only told before setup, so the login page can show it.
				default_password: !done && default_password_in_use(),
				rescue: rescue_state()
			};
		}
	},

	setup_complete: {
		call: function() {
			const cur = uci();
			cur.set('supacudy', 'main', 'setup_done', '1');
			cur.commit('supacudy');
			return { setup_done: true };
		}
	},

	log_get: { args: { lines: 0 }, call: log_get },

	rescue_get: { call: rescue_state },

	time_get: { call: time_get },
	time_set: { args: { zonename: '', ntp: false, time: 0 }, call: time_set },
	password_set: { args: { password: '', hash: '' }, call: password_set },

	reboot: {
		call: function() {
			run_later('reboot', 2);
			return { rebooting: true };
		}
	},

	factory_reset: {
		call: function() {
			run_later('firstboot -y && reboot', 2);
			return { resetting: true };
		}
	},

	firmware_check: {
		call: function(req) {
			return firmware_state() ?? req.error(NOT_FOUND);
		}
	},

	firmware_upgrade: {
		args: { keep_settings: false },
		call: function(req) {
			const keep = req.args.keep_settings;
			if (type(keep) != 'bool')
				return req.error(INVALID);
			const fw = firmware_state();
			if (!fw)
				return req.error(NOT_FOUND);
			if (!fw.valid)
				return fail('firmware_invalid');
			if (keep && !fw.allow_backup)
				return fail('firmware_no_backup');
			run_later(keep ? `sysupgrade ${FIRMWARE}` : `sysupgrade -n ${FIRMWARE}`, 2);
			return { upgrading: true };
		}
	},

	firmware_discard: {
		call: function() {
			unlink(FIRMWARE);
			return { discarded: true };
		}
	}
};

export { methods };
