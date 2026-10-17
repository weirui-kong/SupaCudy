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

export const EAP_METHODS = ['peap', 'ttls'] as const;
export type EapMethod = (typeof EAP_METHODS)[number];
export type EapPhase2 = 'MSCHAPV2' | 'GTC' | 'PAP';
export const EAP_PHASE2: Record<EapMethod, readonly EapPhase2[]> = { peap: ['MSCHAPV2', 'GTC'], ttls: ['MSCHAPV2', 'PAP'] };

/** WPA2-Enterprise login. The server certificate is checked against the
 *  router's trusted authorities and `domain` when `validate` is on. */
export interface EapSettings {
  method: EapMethod;
  identity: string;
  anonymous_identity: string;
  /** '' keeps the saved password. */
  password: string;
  phase2: EapPhase2;
  validate: boolean;
  domain: string;
}

export interface SavedNetworks {
  /** eap comes without its password. */
  networks: { ssid: string; encryption: StaEncryption; last_used: number; eap: EapSettings | null }[];
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
  eap?: EapSettings;
}

export type JoinFailure = 'wrong_key' | 'auth_failed' | 'certificate' | 'rejected' | 'not_found' | 'no_address' | 'timeout';

export interface JoinStatus {
  state: 'idle' | 'connecting' | 'connected' | 'failed';
  ssid: string | null;
  reason: JoinFailure | null;
  ipaddr: string | null;
}

export const getInternetStatus = () => supacudy<InternetStatus>('internet_status');
export const getWan = () => supacudy<WanConfig>('wan_get');
export const setWan = (settings: WanSettings) => supacudy<{ applied: boolean }>('wan_set', settings);
export const scanNetworks = () => supacudy<{ networks: ScannedNetwork[] }>('repeater_scan');
export const connectRepeater = (settings: ConnectSettings) => supacudy<{ applied: boolean }>('repeater_connect', settings);
export const getJoinStatus = () => supacudy<JoinStatus>('repeater_status');
export const disconnectRepeater = () => supacudy<{ applied: boolean }>('repeater_disconnect');
export const getSavedNetworks = () => supacudy<SavedNetworks>('repeater_saved');
export const forgetNetwork = (ssid: string) => supacudy<{ forgotten: boolean }>('repeater_forget', { ssid });
export const setWanPortAsLan = (as_lan: boolean) => supacudy<{ applied: boolean }>('wan_port_set', { as_lan });
export const setTethering = (enabled: boolean) => supacudy<{ applied: boolean }>('tethering_set', { enabled });
export const setRepeaterOptions = (auto_switch: boolean, force_20mhz: boolean) =>
  supacudy<{ auto_switch: boolean; force_20mhz: boolean }>('repeater_options', { auto_switch, force_20mhz });

// WEP is too weak to be offered.
export function joinable(encryption: StaEncryption): boolean {
  return encryption !== 'wep';
}

export function needsPassword(encryption: StaEncryption): boolean {
  return encryption !== 'none' && encryption !== 'owe';
}

/** A Wi-Fi password, as opposed to an enterprise login. */
export function usesKey(encryption: StaEncryption): boolean {
  return needsPassword(encryption) && encryption !== 'enterprise';
}

export function validDomain(domain: string): boolean {
  return /^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$/.test(domain);
}

export interface NetworkGroup {
  ssid: string;
  /** Strongest first. */
  aps: ScannedNetwork[];
  bands: Band[];
  signal: number | null;
  encryption: StaEncryption;
  saved: boolean;
  current: boolean;
}

const BAND_ORDER: Band[] = ['2g', '5g', '6g'];
const strength = (n: ScannedNetwork) => n.signal ?? -999;

// One entry per name, whatever the bands and access points behind it.
export function groupNetworks(networks: ScannedNetwork[]): NetworkGroup[] {
  const groups = new Map<string, ScannedNetwork[]>();
  for (const n of networks) groups.set(n.ssid, [...(groups.get(n.ssid) ?? []), n]);
  return [...groups.entries()]
    .map(([ssid, list]) => {
      const aps = [...list].sort((a, b) => strength(b) - strength(a));
      return {
        ssid, aps,
        bands: BAND_ORDER.filter((b) => aps.some((n) => n.band === b)),
        signal: aps[0].signal,
        encryption: aps[0].encryption,
        saved: aps.some((n) => n.saved),
        current: aps.some((n) => n.current),
      };
    })
    .sort((a, b) => (b.signal ?? -999) - (a.signal ?? -999));
}

/** Above this a 5 GHz access point is preferred: faster, and it leaves the
 *  router's 2.4 GHz channel alone. */
export const PREFER_5G_DBM = -70;

export function pickAccessPoint(group: NetworkGroup): ScannedNetwork {
  const fast = group.aps.find((n) => n.band === '5g' && strength(n) >= PREFER_5G_DBM);
  return fast ?? group.aps[0];
}

export function signalBars(dbm: number | null): number {
  if (dbm === null) return 0;
  if (dbm >= -55) return 4;
  if (dbm >= -65) return 3;
  if (dbm >= -75) return 2;
  if (dbm >= -85) return 1;
  return 0;
}
