// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// The "WIFI:" format phone cameras understand (from the ZXing project, also
// used by Android and iOS). Special characters are backslash-escaped.

import type { WifiNetwork } from './api';

const escape = (s: string) => s.replace(/([\\;,:"])/g, '\\$1');

export function wifiQrPayload(network: Pick<WifiNetwork, 'ssid' | 'encryption' | 'key' | 'hidden'>): string {
  const type = network.encryption === 'none' ? 'nopass' : network.encryption === 'sae' ? 'SAE' : 'WPA';
  const password = network.encryption === 'none' ? '' : `P:${escape(network.key)};`;
  return `WIFI:T:${type};S:${escape(network.ssid)};${password}${network.hidden ? 'H:true;' : ''};`;
}
