// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Shared helpers for the supacudy rpcd modules.
//
// Error convention:
//   - malformed arguments: return req.error(INVALID)
//   - a well-formed request the router refuses (wrong password, address
//     conflict...): return fail('reason_code', { details })
// so the UI can tell "bug in the caller" from "explain this to the user".

'use strict';

import { cursor } from 'uci';
import { connect } from 'ubus';
import { popen, readfile } from 'fs';

const INVALID = 2;
const NOT_FOUND = 4;
const DENIED = 6;

let bus = null;

function ubus() {
	bus ??= connect();
	return bus;
}

function uci() {
	return cursor();
}

function read_trimmed(path) {
	const s = readfile(path);
	return s ? trim(s) : null;
}

// Only for fixed command strings: never interpolate request data here.
function run(cmd) {
	const p = popen(`${cmd} 2>&1`);
	if (!p)
		return { code: -1, out: '' };
	const out = p.read('all') ?? '';
	return { code: p.close(), out };
}

// Restarting services right away would cut off the reply to the browser,
// so changes are applied a moment later in the background.
function run_later(cmd, delay) {
	run(`(sleep ${int(delay ?? 1)}; ${cmd}) >/dev/null 2>&1 &`);
}

function fail(reason, extra) {
	return { ...(extra ?? {}), error: reason };
}

function uptime() {
	return +split(read_trimmed('/proc/uptime') ?? '0', ' ')[0];
}

const MAC_RE = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/;

function normalize_mac(value) {
	if (type(value) != 'string')
		return null;
	const mac = lc(replace(trim(value), '-', ':'));
	return match(mac, MAC_RE) ? mac : null;
}

// Phones and laptops randomize MACs per network; those set the locally
// administered bit (second-lowest bit of the first octet).
function is_random_mac(mac) {
	return (hex(substr(mac, 0, 2)) & 2) != 0;
}

function ipv4_to_int(ip) {
	if (type(ip) != 'string')
		return null;
	const m = match(ip, /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
	if (!m)
		return null;
	let n = 0;
	for (let i = 1; i <= 4; i++) {
		const octet = +m[i];
		if (octet > 255)
			return null;
		n = n * 256 + octet;
	}
	return n;
}

function int_to_ipv4(n) {
	return sprintf('%d.%d.%d.%d', (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255);
}

function prefix_to_mask(prefix) {
	return prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
}

// Accepts dotted (255.255.255.0) or prefix (24) notation.
function parse_netmask(value) {
	if (match(`${value}`, /^\d{1,2}$/)) {
		const prefix = +value;
		return prefix >= 0 && prefix <= 32 ? prefix : null;
	}
	const n = ipv4_to_int(value);
	if (n == null)
		return null;
	for (let prefix = 0; prefix <= 32; prefix++)
		if (prefix_to_mask(prefix) == n)
			return prefix;
	return null;
}

function subnet(ip, prefix) {
	const n = ipv4_to_int(ip);
	if (n == null || prefix == null)
		return null;
	const mask = prefix_to_mask(prefix);
	const network = n & mask;
	const broadcast = network | (~mask & 0xffffffff);
	return { address: n, network, broadcast, prefix, size: broadcast - network + 1 };
}

function overlaps(a, b) {
	return a.network <= b.broadcast && b.network <= a.broadcast;
}

// RFC 1918 private ranges only: LAN addresses outside them break things.
function is_private(net) {
	for (let r in [['10.0.0.0', 8], ['172.16.0.0', 12], ['192.168.0.0', 16]]) {
		const range = subnet(r[0], r[1]);
		if (net.network >= range.network && net.broadcast <= range.broadcast)
			return true;
	}
	return false;
}

function uci_bool(value, fallback) {
	if (value == null)
		return fallback;
	return value == '1' || value == 'true' || value == 'on' || value == 'yes';
}

export {
	INVALID, NOT_FOUND, DENIED,
	ubus, uci, read_trimmed, run, run_later, fail, uptime,
	normalize_mac, is_random_mac,
	ipv4_to_int, int_to_ipv4, parse_netmask, prefix_to_mask, subnet, overlaps, is_private,
	uci_bool
};
