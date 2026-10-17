// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';
import type { Band } from './wifi';

export interface Addressing {
  /** CIDR, e.g. 10.0.0.15/24. */
  ipaddr: string | null;
  gateway: string | null;
  dns: string[];
}

export interface EthernetStatus extends Addressing {
  configured: boolean;
  carrier: boolean;
  up: boolean;
  proto: WanProto;
  uptime: number;
}

export interface RepeaterStatus extends Addressing {
  configured: boolean;
  enabled: boolean;
  ssid: string | null;
  band: Band | null;
  connected: boolean;
  bssid: string | null;
  signal: number | null;
  up: boolean;
  uptime: number;
}

export interface TetheringStatus extends Addressing {
  enabled: boolean;
  /** A phone is plugged in and offers its connection. */
  available: boolean;
  device: string | null;
  up: boolean;
  uptime: number;
}

export interface InternetStatus {
  /** UCI interface carrying the default route: 'wan', 'wwan'... */
  active: string | null;
  internet: boolean;
  ethernet: EthernetStatus;
  repeater: RepeaterStatus;
  tethering: TetheringStatus;
  time: number;
}

export const WAN_PROTOS = ['dhcp', 'static', 'pppoe'] as const;
export type WanProto = (typeof WAN_PROTOS)[number];

export interface WanConfig {
  proto: WanProto;
  /** The WAN port is in use as an extra LAN port. */
  as_lan: boolean;
  device: string | null;
  ipaddr: string;
  netmask: string;
  gateway: string;
  dns: string[];
  username: string;
  /** A PPPoE password is saved; it is never sent back. */
  has_password: boolean;
  service: string;
}

export interface WanSettings {
  proto: WanProto;
  ipaddr: string;
  netmask: string;
  gateway: string;
  dns: string[];
  username: string;
  /** '' keeps the saved PPPoE password. */
  password: string;
}

export type StaEncryption = 'none' | 'psk2' | 'psk-mixed' | 'sae' | 'sae-mixed' | 'owe' | 'enterprise' | 'wep';

export interface ScannedNetwork {
  ssid: string;
  bssid: string;
  band: Band;
  channel: number;
  signal: number | null;
  encryption: StaEncryption;
  saved: boolean;
  current: boolean;
}

export interface SavedNetworks {
  networks: { ssid: string; encryption: StaEncryption; last_used: number }[];
  auto_switch: boolean;
  force_20mhz: boolean;
}

export interface ConnectSettings {
  ssid: string;
  bssid: string;
  encryption: StaEncryption;
  key: string;
  band: Band | '';
  save: boolean;
}

export const getInternetStatus = () => supacudy<InternetStatus>('internet_status');
export const getWan = () => supacudy<WanConfig>('wan_get');
export const setWan = (settings: WanSettings) => supacudy<{ applied: boolean }>('wan_set', settings);
export const scanNetworks = () => supacudy<{ networks: ScannedNetwork[] }>('repeater_scan');
export const connectRepeater = (settings: ConnectSettings) => supacudy<{ applied: boolean }>('repeater_connect', settings);
export const disconnectRepeater = () => supacudy<{ applied: boolean }>('repeater_disconnect');
export const getSavedNetworks = () => supacudy<SavedNetworks>('repeater_saved');
export const forgetNetwork = (ssid: string) => supacudy<{ forgotten: boolean }>('repeater_forget', { ssid });
export const setWanPortAsLan = (as_lan: boolean) => supacudy<{ applied: boolean }>('wan_port_set', { as_lan });
export const setTethering = (enabled: boolean) => supacudy<{ applied: boolean }>('tethering_set', { enabled });
export const setRepeaterOptions = (auto_switch: boolean, force_20mhz: boolean) =>
  supacudy<{ auto_switch: boolean; force_20mhz: boolean }>('repeater_options', { auto_switch, force_20mhz });

// The router can join these; enterprise (802.1X) and WEP are not offered.
export function joinable(encryption: StaEncryption): boolean {
  return encryption !== 'enterprise' && encryption !== 'wep';
}

export function needsPassword(encryption: StaEncryption): boolean {
  return encryption !== 'none' && encryption !== 'owe';
}

export function signalBars(dbm: number | null): number {
  if (dbm === null) return 0;
  if (dbm >= -55) return 4;
  if (dbm >= -65) return 3;
  if (dbm >= -75) return 2;
  if (dbm >= -85) return 1;
  return 0;
}
