// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Every method added here must also be listed in acl.d/supacudy.json.

'use strict';

import { readfile } from 'fs';

function read_trimmed(path) {
	const s = readfile(path);
	return s ? trim(s) : null;
}

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

function cpu_count() {
	let count = 0;

	for (let line in split(readfile('/proc/cpuinfo') || '', '\n'))
		if (match(line, /^processor\s*:/))
			count++;

	return count || 1;
}

return {
	supacudy: {
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
					memory: meminfo()
				};
			}
		}
	}
};
