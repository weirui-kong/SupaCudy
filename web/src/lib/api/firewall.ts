// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export const FORWARD_PROTOS = ['tcp', 'udp', 'tcp udp'] as const;
export type ForwardProto = (typeof FORWARD_PROTOS)[number];
export const PROTO_LABELS = { tcp: 'ports.proto_tcp', udp: 'ports.proto_udp', 'tcp udp': 'ports.proto_both' } as const;

export interface PortForward {
  id: string;
  name: string;
  proto: ForwardProto;
  /** A port or a range such as "8000-8010". */
  external_port: string;
  internal_ip: string;
  /** '' keeps the external port. */
  internal_port: string;
  enabled: boolean;
}

export interface OpenPort {
  id: string;
  name: string;
  proto: ForwardProto;
  port: string;
  enabled: boolean;
}

export interface FirewallState {
  forwards: PortForward[];
  open_ports: OpenPort[];
  dmz: { enabled: boolean; ip: string };
  /** For checking that internal addresses are on the LAN. */
  lan: { ipaddr: string; prefix: number };
  offload: 'off' | 'software' | 'hardware';
}

export const getFirewall = () => supacudy<FirewallState>('firewall_get');
export const savePortForward = (f: PortForward) => supacudy<{ id: string }>('forward_set', f);
export const deletePortForward = (id: string) => supacudy<{ deleted: boolean }>('forward_delete', { id });
export const saveOpenPort = (p: OpenPort) => supacudy<{ id: string }>('open_port_set', p);
export const deleteOpenPort = (id: string) => supacudy<{ deleted: boolean }>('open_port_delete', { id });
export const setDmz = (enabled: boolean, ip: string) => supacudy<{ applied: boolean }>('dmz_set', { enabled, ip });

/** "443" or "8000-8010", within 1–65535 and ascending. */
export function portRangeError(s: string): boolean {
  const m = /^(\d{1,5})(?:-(\d{1,5}))?$/.exec(s.trim());
  if (!m) return true;
  const a = Number(m[1]);
  const b = m[2] ? Number(m[2]) : a;
  return a < 1 || b > 65535 || b < a;
}

export function rangeSize(s: string): number {
  const [a, b = a] = s.split('-').map(Number);
  return b - a + 1;
}

export interface WanAccess {
  webui: boolean;
  ssh: boolean;
}

export const getWanAccess = () => supacudy<WanAccess>('wan_access_get');
export const setWanAccess = (a: WanAccess) => supacudy<{ applied: boolean }>('wan_access_set', { ...a });

/** Inclusive ranges the router accepts; attempts are counted within `window` minutes. */
export const GUARD_LIMITS = { attempts: [1, 20], window: [1, 1440], ban: [1, 10080] } as const;

export interface GuardSettings {
  enabled: boolean;
  attempts: number;
  /** Minutes in which the failures are counted. */
  window: number;
  /** Minutes an address stays banned. */
  ban: number;
}

export interface GuardState extends GuardSettings {
  /** expires: seconds left. */
  banned: { ip: string; expires: number | null }[];
}

export const getGuard = () => supacudy<GuardState>('guard_get');
export const setGuard = (s: GuardSettings) => supacudy<{ applied: boolean }>('guard_set', { ...s });
export const unbanAddress = (ip: string) => supacudy<{ applied: boolean }>('guard_unban', { ip });

export function guardFieldError(name: keyof typeof GUARD_LIMITS, value: string): 'range' | null {
  const [min, max] = GUARD_LIMITS[name];
  return /^\d+$/.test(value.trim()) && Number(value) >= min && Number(value) <= max ? null : 'range';
}
