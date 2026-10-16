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
		}
	}
};
