// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';
import { isIPv4 } from '../validate';

export interface WgProfile {
  id: string;
  type: 'wireguard';
  name: string;
  addresses: string[];
  dns: string[];
  /** 0 means the default. */
  mtu: number;
  public_key: string;
  has_preshared_key: boolean;
  endpoint_host: string;
  endpoint_port: number;
  allowed_ips: string[];
  keepalive: number;
}

export interface OvpnProfile {
  id: string;
  type: 'openvpn';
  name: string;
  /** First "remote" of the configuration, host:port. */
  remote: string;
  username: string;
}

export type VpnProfile = WgProfile | OvpnProfile;

export interface VpnStatus {
  up: boolean;
  /** The server answers: a recent WireGuard handshake, or an OpenVPN address. */
  connected: boolean;
  addresses: string[];
  uptime: number;
  endpoint: string | null;
  /** Seconds since the epoch of the last handshake; 0 if none yet. */
  handshake: number;
  rx_bytes: number;
  tx_bytes: number;
}

export interface VpnState {
  profiles: VpnProfile[];
  active: string | null;
  kill_switch: boolean;
  allow_lan: boolean;
  route_mode: VpnRouteMode;
  /** MAC addresses that use the VPN when `route_mode` is "selected". */
  devices: string[];
  /** Domains and IPv4 networks that use the VPN for everyone in "selected" mode. */
  destinations: string[];
  /** The router can route by domain (dnsmasq-full). */
  domains_supported: boolean;
  status: VpnStatus;
  /** While connected: IPv6 goes through the tunnel, or is blocked so it cannot bypass it. */
  ipv6: 'tunnel' | 'blocked' | null;
  /** Router clock, to compare with `handshake`. */
  time: number;
}

/** What the router stores; keys left empty keep the stored ones. */
export interface VpnProfileInput {
  id: string;
  name: string;
  private_key: string;
  public_key: string;
  /** '' keeps the stored key, '-' removes it. */
  preshared_key: string;
  addresses: string[];
  dns: string[];
  endpoint_host: string;
  endpoint_port: number;
  allowed_ips: string[];
  keepalive: number;
  mtu: number;
}

export const getVpn = () => supacudy<VpnState>('vpn_get');
export const saveVpnProfile = (profile: VpnProfileInput) => supacudy<{ id: string }>('vpn_profile_set', profile);
export interface OvpnProfileInput {
  id: string;
  name: string;
  /** The .ovpn file; '' keeps the saved one when editing. */
  config: string;
  /** '' keeps the saved login. */
  username: string;
  /** '' keeps the saved password. */
  password: string;
}

export const saveOvpnProfile = (profile: OvpnProfileInput) => supacudy<{ id: string }>('vpn_ovpn_set', profile);
export const deleteVpnProfile = (id: string) => supacudy<{ deleted: boolean }>('vpn_profile_delete', { id });
export const connectVpn = (id: string) => supacudy<{ applied: boolean }>('vpn_connect', { id });
export const disconnectVpn = () => supacudy<{ applied: boolean }>('vpn_disconnect');
export type VpnRouteMode = 'all' | 'selected';

export interface VpnOptions {
  kill_switch: boolean;
  allow_lan: boolean;
  route_mode: VpnRouteMode;
  devices: string[];
  destinations: string[];
}

export const setVpnOptions = (options: VpnOptions) => supacudy<{ applied: boolean }>('vpn_options', options);

export function vpnOptionsOf(state: Pick<VpnState, keyof VpnOptions>): VpnOptions {
  const { kill_switch, allow_lan, route_mode, devices, destinations } = state;
  return { kill_switch, allow_lan, route_mode, devices: [...devices], destinations: [...destinations] };
}

const DOMAIN = /^([A-Za-z0-9]([A-Za-z0-9-]{0,62})\.)+[A-Za-z]{2,63}$/;
const ROUTE = /^\d{1,3}(\.\d{1,3}){3}(\/\d{1,2})?$/;

/** What kind of destination a line is, or null if it is neither. */
export function destinationKind(s: string): 'domain' | 'network' | null {
  if (ROUTE.test(s)) {
    const [ip, prefix = '32'] = s.split('/');
    return ip.split('.').every((o) => Number(o) <= 255) && Number(prefix) <= 32 ? 'network' : null;
  }
  return s.length <= 253 && DOMAIN.test(s) ? 'domain' : null;
}

// A WireGuard key is 32 bytes of base64: 43 characters and one "=".
const KEY = /^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$/;
const HOST = /^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$/;

export const isWgKey = (s: string) => KEY.test(s);

function isIPv6(s: string): boolean {
  return s.includes(':') && /^[0-9A-Fa-f:.]{2,45}$/.test(s);
}

export const isIP = (s: string) => isIPv4(s) || isIPv6(s);

export function isCidr(s: string): boolean {
  const m = /^([^/]+)\/(\d{1,3})$/.exec(s);
  if (!m) return false;
  return isIPv6(m[1]) ? Number(m[2]) <= 128 : isIPv4(m[1]) && Number(m[2]) <= 32;
}

export const isEndpointHost = (s: string) => HOST.test(s) || isIP(s);

export const splitList = (s: string) => s.split(/[\s,]+/).filter(Boolean);

/** Splits "host:port" or "[v6]:port". */
export function parseEndpoint(s: string): { host: string; port: number } | null {
  const m = /^\[([^\]]+)\]:(\d+)$/.exec(s.trim()) ?? /^([^:\s]+):(\d+)$/.exec(s.trim());
  if (!m) return null;
  const port = Number(m[2]);
  return port >= 1 && port <= 65535 ? { host: m[1], port } : null;
}

export function formatEndpoint(host: string, port: number): string {
  return host ? `${host.includes(':') ? `[${host}]` : host}:${port}` : '';
}

export type WgConfProblem = 'no_interface' | 'no_peer' | 'missing_private_key' | 'missing_public_key' | 'missing_endpoint';

export interface ParsedWgConf {
  profile: Omit<VpnProfileInput, 'id' | 'name'>;
  /** Peers after the first are ignored. */
  extraPeers: number;
}

// The wg-quick format VPN providers hand out ([Interface] + [Peer] sections).
export function parseWgConf(text: string): ParsedWgConf | WgConfProblem {
  const sections: { name: string; values: Record<string, string> }[] = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, '').trim();
    if (!line) continue;
    const header = /^\[(\w+)\]$/.exec(line);
    if (header) {
      sections.push({ name: header[1].toLowerCase(), values: {} });
      continue;
    }
    const kv = /^([A-Za-z]+)\s*=\s*(.*)$/.exec(line);
    if (kv && sections.length) sections[sections.length - 1].values[kv[1].toLowerCase()] = kv[2].trim();
  }
  const iface = sections.find((s) => s.name === 'interface')?.values;
  const peers = sections.filter((s) => s.name === 'peer').map((s) => s.values);
  if (!iface) return 'no_interface';
  if (!peers.length) return 'no_peer';
  const peer = peers[0];
  if (!iface.privatekey) return 'missing_private_key';
  if (!peer.publickey) return 'missing_public_key';
  const endpoint = parseEndpoint(peer.endpoint ?? '');
  if (!endpoint) return 'missing_endpoint';
  return {
    profile: {
      private_key: iface.privatekey,
      public_key: peer.publickey,
      preshared_key: peer.presharedkey ?? '',
      addresses: splitList(iface.address ?? ''),
      // DNS may also list search domains; the router only takes addresses.
      dns: splitList(iface.dns ?? '').filter(isIP),
      endpoint_host: endpoint.host,
      endpoint_port: endpoint.port,
      allowed_ips: splitList(peer.allowedips ?? '0.0.0.0/0'),
      keepalive: Number(peer.persistentkeepalive ?? 0) || 0,
      mtu: Number(iface.mtu ?? 0) || 0,
    },
    extraPeers: peers.length - 1,
  };
}

export function profileServer(p: VpnProfile): string {
  return p.type === 'openvpn' ? p.remote : formatEndpoint(p.endpoint_host, p.endpoint_port);
}

const OVPN_MAX = 65536;

/** Checks an .ovpn file before upload; the router checks it again. */
export function ovpnProblem(text: string): 'too_large' | 'no_remote' | null {
  if (text.length > OVPN_MAX) return 'too_large';
  return /^\s*remote\s+\S+/m.test(text) ? null : 'no_remote';
}
