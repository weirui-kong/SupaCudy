// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Uplink priority and failover settings, and what the failover watcher
// (/usr/libexec/supacudy/failover.uc in supacudy-base) last found. The
// settings live in supacudy.failover; the watcher picks them up on its next
// check, which is started right away.

'use strict';

import { readfile } from 'fs';
import { INVALID, uci, run_later, fail } from 'supacudy.util';

const STATE = '/var/run/supacudy/failover.json';
const NAMES = [ 'wired', 'repeater', 'tethering' ];
const TARGETS_MAX = 8;
// Mirrors the watcher's defaults; shown when nothing is set.
const DEFAULT_TARGETS4 = [ '223.5.5.5', '1.1.1.1', '8.8.8.8' ];
const DEFAULT_TARGETS6 = [ '2400:3200::1', '2606:4700:4700::1111', '2001:4860:4860::8888' ];

function as_list(v) {
	return type(v) == 'array' ? v : (v ? [ v ] : []);
}

function is_ip4(s) {
	const m = type(s) == 'string' ? match(s, /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) : null;
	return m != null && +m[1] <= 255 && +m[2] <= 255 && +m[3] <= 255 && +m[4] <= 255;
}

function is_ip6(s) {
	if (type(s) != 'string' || length(s) > 45 || !match(s, /^[0-9A-Fa-f:]+$/))
		return false;
	const halves = split(s, '::');
	if (length(halves) > 2)
		return false;
	let groups = 0;
	for (let h in halves) {
		if (h == '')
			continue;
		for (let g in split(h, ':')) {
			if (!match(g, /^[0-9A-Fa-f]{1,4}$/))
				return false;
			groups++;
		}
	}
	return length(halves) == 2 ? groups < 8 : groups == 8;
}

function order_of(cur) {
	const order = filter(as_list(cur.get('supacudy', 'failover', 'order')), (n) => n in NAMES);
	for (let n in NAMES)
		if (!(n in order))
			push(order, n);
	return order;
}

function configured(cur, name) {
	if (name == 'wired')
		return cur.get('network', 'wan') != null;
	if (name == 'repeater')
		return cur.get('wireless', 'wwan') != null;
	return cur.get('supacudy', 'tethering', 'enabled') == '1';
}

function family_view(h) {
	return h ? { connected: h.link == true, online: h.link == true && h.ok == true, checked: h.checked ?? null } :
		{ connected: false, online: false, checked: null };
}

function uplinks_get() {
	const cur = uci();
	let st = null;
	try {
		st = json(readfile(STATE) ?? 'null');
	} catch {
		st = null;
	}
	const t4 = as_list(cur.get('supacudy', 'failover', 'target4'));
	const t6 = as_list(cur.get('supacudy', 'failover', 'target6'));
	return {
		order: order_of(cur),
		reset_connections: cur.get('supacudy', 'failover', 'reset_connections') != '0',
		targets4: length(t4) ? t4 : DEFAULT_TARGETS4,
		targets6: length(t6) ? t6 : DEFAULT_TARGETS6,
		// Null while the watcher has not reported yet.
		watching: st != null,
		active_v4: st?.active_v4 ?? null,
		active_v6: st?.active_v6 ?? null,
		online_v4: st ? st.online_v4 == true : null,
		online_v6: st ? st.online_v6 == true : null,
		uplinks: map(order_of(cur), (n) => ({
			name: n,
			configured: configured(cur, n),
			v4: family_view(st?.uplinks?.[n]?.v4),
			v6: family_view(st?.uplinks?.[n]?.v6)
		}))
	};
}

function valid_targets(list, check) {
	if (type(list) != 'array' || length(list) < 1 || length(list) > TARGETS_MAX)
		return false;
	for (let t in list)
		if (!check(t))
			return false;
	return true;
}

function uplinks_set(req) {
	const a = req.args;
	if (type(a.order) != 'array' || length(a.order) != length(NAMES) || type(a.reset_connections) != 'bool')
		return req.error(INVALID);
	for (let n in NAMES)
		if (!(n in a.order))
			return req.error(INVALID);
	if (!valid_targets(a.targets4, is_ip4))
		return fail('target_invalid', { family: 'ipv4' });
	if (!valid_targets(a.targets6, is_ip6))
		return fail('target_invalid', { family: 'ipv6' });
	const cur = uci();
	if (!cur.get('supacudy', 'failover'))
		cur.set('supacudy', 'failover', 'failover');
	cur.set('supacudy', 'failover', 'order', a.order);
	cur.set('supacudy', 'failover', 'reset_connections', a.reset_connections ? '1' : '0');
	cur.set('supacudy', 'failover', 'target4', a.targets4);
	cur.set('supacudy', 'failover', 'target6', a.targets6);
	cur.commit('supacudy');
	// Same lock as failover-watch, so the two checks never overlap.
	run_later('flock /var/run/supacudy-failover.lock ucode /usr/libexec/supacudy/failover.uc', 0);
	return { applied: true };
}

const methods = {
	uplinks_get: { call: uplinks_get },
	uplinks_set: {
		args: { order: [], reset_connections: false, targets4: [], targets6: [] },
		call: uplinks_set
	}
};

export { methods };
