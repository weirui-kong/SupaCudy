// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC address of the router's uplinks (Ethernet WAN and repeater): keep the
// factory address, clone a device's, set one by hand or pick a random one.
// Hotels and some ISPs tie access to a device's MAC address.

'use strict';

import { open } from 'fs';
import { INVALID, uci, read_trimmed, run_later, fail, normalize_mac } from 'supacudy.util';

const TARGETS = ['wan', 'repeater'];
const MODES = ['default', 'custom', 'random'];
// netifd applies a "device" section's macaddr to the port with that name.
const WAN_DEVICE_SECTION = 'supacudy_wan_dev';

function wan_port(cur) {
	return cur.get('network', 'wan', 'device');
}

function wan_device_section(cur, port) {
	let found = null;
	cur.foreach('network', 'device', (s) => {
		if (s.name == port)
			found ??= s['.name'];
	});
	return found;
}

function custom_mac(cur, target) {
	if (target == 'repeater')
		return cur.get('wireless', 'wwan', 'macaddr') ?? null;
	const port = wan_port(cur);
	const section = port ? wan_device_section(cur, port) : null;
	return section ? cur.get('network', section, 'macaddr') ?? null : null;
}

function sysfs_mac(dev) {
	return dev && match(dev, /^[A-Za-z0-9._-]+$/) ? read_trimmed(`/sys/class/net/${dev}/address`) : null;
}

// Locally administered, unicast: never collides with a vendor's address.
function random_mac() {
	const f = open('/dev/urandom');
	const bytes = f ? f.read(6) : null;
	f?.close();
	if (!bytes || length(bytes) != 6)
		return null;
	const b = map(split(bytes, ''), (c) => ord(c));
	b[0] = (b[0] & 0xfc) | 0x02;
	return join(':', map(b, (x) => sprintf('%02x', x)));
}

function usable_mac(mac) {
	if (!mac || mac == '00:00:00:00:00:00')
		return false;
	return (hex(substr(mac, 0, 2)) & 1) == 0;
}

function mac_get() {
	const cur = uci();
	const port = wan_port(cur);
	const wan_custom = custom_mac(cur, 'wan');
	return {
		wan: {
			device: port,
			current: sysfs_mac(port),
			custom: wan_custom,
			factory: wan_custom ? cur.get('supacudy', 'main', 'wan_factory_mac') ?? null : sysfs_mac(port)
		},
		repeater: {
			configured: cur.get('wireless', 'wwan') != null,
			custom: custom_mac(cur, 'repeater')
		}
	};
}

function mac_set(req) {
	const a = req.args;
	if (!(a.target in TARGETS) || !(a.mode in MODES) || type(a.macaddr) != 'string')
		return req.error(INVALID);
	let mac = null;
	if (a.mode == 'custom') {
		mac = normalize_mac(a.macaddr);
		if (!mac)
			return req.error(INVALID);
		if (!usable_mac(mac))
			return fail('mac_not_unicast');
	} else if (a.mode == 'random') {
		mac = random_mac();
		if (!mac)
			return fail('mac_failed');
	}

	const cur = uci();
	if (a.target == 'repeater') {
		if (!cur.get('wireless', 'wwan'))
			return fail('repeater_not_configured');
		if (mac)
			cur.set('wireless', 'wwan', 'macaddr', mac);
		else
			cur.delete('wireless', 'wwan', 'macaddr');
		cur.commit('wireless');
		run_later('wifi reload', 1);
		return { applied: true, macaddr: mac };
	}

	const port = wan_port(cur);
	if (!port)
		return fail('wan_not_configured');
	let section = wan_device_section(cur, port);
	if (mac) {
		if (!custom_mac(cur, 'wan'))
			cur.set('supacudy', 'main', 'wan_factory_mac', sysfs_mac(port) ?? '');
		if (!section) {
			section = WAN_DEVICE_SECTION;
			cur.set('network', section, 'device');
			cur.set('network', section, 'name', port);
		}
		cur.set('network', section, 'macaddr', mac);
	} else if (section) {
		cur.delete('network', section, 'macaddr');
		// Our own section only existed to carry the address.
		if (section == WAN_DEVICE_SECTION)
			cur.delete('network', section);
	}
	cur.commit('network');
	cur.commit('supacudy');
	run_later('/etc/init.d/network reload', 1);
	return { applied: true, macaddr: mac };
}

const methods = {
	mac_get: { call: mac_get },
	mac_set: { args: { target: '', mode: '', macaddr: '' }, call: mac_set }
};

export { methods };
