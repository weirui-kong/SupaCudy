// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export type NetMode = 'router' | 'ap';

export interface NetModeState {
  mode: NetMode;
  lan: { ipaddr: string; netmask: string; gateway: string | null };
  /** What the WAN got from the main router, to suggest settings for AP mode. */
  upstream: { ipaddr: string; prefix: number; gateway: string | null; dns: string[] } | null;
}

export interface ApSettings {
  ipaddr: string;
  netmask: string;
  gateway: string;
  dns: string[];
}

export const getNetMode = () => supacudy<NetModeState>('netmode_get');
export const setRouterMode = () =>
  supacudy<{ applied: boolean }>('netmode_set', { mode: 'router', ipaddr: '', netmask: '', gateway: '', dns: [] });
export const setApMode = (s: ApSettings) => supacudy<{ applied: boolean }>('netmode_set', { mode: 'ap', ...s });
