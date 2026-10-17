// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// Hotplug entry point into supacudy.vpn, so these updates need no API
// method the web UI could reach.
//
//   ucode vpn-dns.uc pushed [SERVER...]   OpenVPN came up with these servers
//   ucode vpn-dns.uc refresh              an uplink's DNS servers changed

'use strict';

import { ovpn_pushed_dns, refresh_vpn_dns } from 'supacudy.vpn';

if (ARGV[0] == 'pushed')
	ovpn_pushed_dns(slice(ARGV, 1));
else if (ARGV[0] == 'refresh')
	refresh_vpn_dns();
