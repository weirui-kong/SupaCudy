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
