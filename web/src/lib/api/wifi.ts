// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export const ENCRYPTIONS = ['sae-mixed', 'psk2', 'sae', 'psk-mixed', 'none'] as const;
export type Encryption = (typeof ENCRYPTIONS)[number];

export const TX_POWERS = ['max', 'high', 'medium', 'low'] as const;
export type TxPower = (typeof TX_POWERS)[number];

export type Band = '2g' | '5g' | '6g';

export interface WifiNetwork {
  enabled: boolean;
  ssid: string;
  encryption: Encryption;
  key: string;
  hidden: boolean;
}

export interface Radio {
  name: string;
  band: Band;
  enabled: boolean;
  channel: number | 'auto';
  channels: number[];
  /** Channel width in MHz. */
  width: number;
  widths: number[];
  txpower: TxPower;
  /** Why channel and width cannot be changed right now. */
  locked: 'repeater' | null;
  encryptions: Encryption[];
  main: WifiNetwork;
  /** null until a guest network has been set up on this radio. */
  guest: WifiNetwork | null;
}

export interface WifiConfig {
  radios: Radio[];
  guest_subnet: string | null;
}

export interface RadioSettings {
  radio: string;
  enabled: boolean;
  channel: string;
  width: number;
  txpower: TxPower;
  ssid: string;
  encryption: Encryption;
  key: string;
  hidden: boolean;
}

export interface GuestSettings {
  radio: string;
  enabled: boolean;
  ssid: string;
  encryption: Encryption;
  key: string;
  hidden: boolean;
}

export const getWifi = () => supacudy<WifiConfig>('wifi_get');
export const setWifi = (settings: RadioSettings) => supacudy<{ applied: boolean }>('wifi_set', settings);
export const setGuestWifi = (settings: GuestSettings) => supacudy<{ applied: boolean; subnet: string }>('guest_set', settings);

// Matches hostapd: SSIDs are 1-32 bytes, WPA passphrases 8-63 characters.
export function ssidError(ssid: string): 'empty' | 'too_long' | null {
  if (ssid.length === 0) return 'empty';
  return new TextEncoder().encode(ssid).length > 32 ? 'too_long' : null;
}

export function keyError(encryption: Encryption, key: string): 'too_short' | 'too_long' | 'invalid' | null {
  if (encryption === 'none') return null;
  if (key.length < 8) return 'too_short';
  if (key.length > 63) return 'too_long';
  return /^[\x20-\x7e]+$/.test(key) ? null : 'invalid';
}
