// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0
//
// The "supacudy" ubus object. Methods live in /usr/share/ucode/supacudy/*.uc;
// every method must also be listed in acl.d/supacudy.json.

'use strict';

import { methods as system } from 'supacudy.system';
import { methods as clients } from 'supacudy.clients';
import { methods as lan } from 'supacudy.lan';
import { methods as wireless } from 'supacudy.wireless';
import { methods as internet } from 'supacudy.internet';
import { methods as mac } from 'supacudy.mac';
import { methods as dns } from 'supacudy.dns';
import { methods as vpn } from 'supacudy.vpn';
import { methods as firewall } from 'supacudy.firewall';
import { methods as schedule } from 'supacudy.schedule';
import { methods as ddns } from 'supacudy.ddns';
import { methods as netmode } from 'supacudy.netmode';
import { methods as adguard } from 'supacudy.adguard';
import { methods as remote } from 'supacudy.remote';

return {
	supacudy: { ...system, ...clients, ...lan, ...wireless, ...internet, ...mac, ...dns, ...vpn, ...firewall, ...schedule, ...ddns, ...netmode, ...adguard, ...remote }
};
