// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Saves an OpenVPN profile for the scenario's server, with the test-only
// client certificate inline as providers ship them, and prints its id.

'use strict';

import { connect } from 'ubus';
import { readfile } from 'fs';

const dir = '/usr/share/supacudy-emulator/openvpn/';
const inline = (tag, file) => `<${tag}>\n${readfile(dir + file)}</${tag}>\n`;
const config = 'client\ndev tun\nproto udp\nremote 10.250.10.2 1194\nnobind\nremote-cert-tls server\ndhcp-option DNS 10.250.31.53\nverb 1\n' +
	inline('ca', 'ca.crt') + inline('cert', 'client.crt') + inline('key', 'client.key');
const reply = connect().call('supacudy', 'vpn_ovpn_set', { id: '', name: 'Emu OpenVPN', config, username: '', password: '' });
print(reply?.id ?? 'failed', '\n');
