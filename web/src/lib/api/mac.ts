// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export type MacTarget = 'wan' | 'repeater';
export const MAC_MODES = ['default', 'clone', 'custom', 'random'] as const;
export type MacMode = (typeof MAC_MODES)[number];

export interface MacSettings {
  wan: { device: string | null; current: string | null; custom: string | null; factory: string | null };
  repeater: { configured: boolean; custom: string | null };
}

export const getMacSettings = () => supacudy<MacSettings>('mac_get');

// Cloning is a custom address taken from a device; the router only knows custom.
export const setMac = (target: MacTarget, mode: MacMode, macaddr = '') =>
  supacudy<{ applied: boolean; macaddr: string | null }>('mac_set', {
    target,
    mode: mode === 'clone' ? 'custom' : mode,
    macaddr,
  });

const MAC = /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i;

export function macError(mac: string): 'format' | 'unusable' | null {
  if (!MAC.test(mac.trim())) return 'format';
  const first = parseInt(mac.trim().slice(0, 2), 16);
  if (first & 1 || /^(00[:-]){5}00$/.test(mac.trim())) return 'unusable';
  return null;
}
