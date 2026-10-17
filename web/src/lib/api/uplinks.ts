// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';
import { isIPv4 } from '../validate';

export type UplinkName = 'wired' | 'repeater' | 'tethering';

export interface UplinkFamily {
  /** Connected with an address and a route. */
  connected: boolean;
  /** Connected and its probes are answered. */
  online: boolean;
  checked: number | null;
}

export interface Uplink {
  name: UplinkName;
  /** Set up at all (Ethernet WAN, a repeater network, tethering turned on). */
  configured: boolean;
  v4: UplinkFamily;
  v6: UplinkFamily;
}

export interface UplinkSettings {
  order: UplinkName[];
  /** Drop connections on the old uplink when switching, so devices reconnect at once. */
  reset_connections: boolean;
  targets4: string[];
  targets6: string[];
}

export interface UplinksState extends UplinkSettings {
  /** The failover watcher has reported; everything below is null before. */
  watching: boolean;
  active_v4: UplinkName | null;
  active_v6: UplinkName | null;
  online_v4: boolean | null;
  online_v6: boolean | null;
  uplinks: Uplink[];
}

export const getUplinks = () => supacudy<UplinksState>('uplinks_get');
export const setUplinks = (s: UplinkSettings) => supacudy<{ applied: boolean }>('uplinks_set', s);

export function isIPv6(s: string): boolean {
  if (s.length > 45 || !/^[0-9A-Fa-f:]+$/.test(s)) return false;
  const halves = s.split('::');
  if (halves.length > 2) return false;
  const groups = halves.filter(Boolean).flatMap((h) => h.split(':'));
  if (!groups.every((g) => /^[0-9A-Fa-f]{1,4}$/.test(g))) return false;
  return halves.length === 2 ? groups.length < 8 : groups.length === 8;
}

export const TARGETS_MAX = 8;

/** The first entry that is not an address of the family, or null. */
export function badTarget(list: string[], family: 'v4' | 'v6'): string | null {
  return list.find((t) => !(family === 'v4' ? isIPv4(t) : isIPv6(t))) ?? null;
}

export function moveUplink(order: UplinkName[], name: UplinkName, by: -1 | 1): UplinkName[] {
  const i = order.indexOf(name);
  const j = i + by;
  if (i < 0 || j < 0 || j >= order.length) return order;
  const next = [...order];
  [next[i], next[j]] = [next[j], next[i]];
  return next;
}
