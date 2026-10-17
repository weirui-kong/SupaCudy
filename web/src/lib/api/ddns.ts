// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export interface DdnsState {
  /** ddns-scripts and at least one provider are installed. */
  available: boolean;
  /** Provider ids such as "duckdns.org" or "cloudflare.com-v4". */
  services: string[];
  enabled: boolean;
  service: string;
  domain: string;
  username: string;
  has_password: boolean;
  /** Seconds since the epoch; 0 if it never updated. */
  last_update: number;
  ip: string | null;
}

export interface DdnsSettings {
  enabled: boolean;
  service: string;
  domain: string;
  username: string;
  /** '' keeps the saved one. */
  password: string;
}

export const getDdns = () => supacudy<DdnsState>('ddns_get');
export const setDdns = (s: DdnsSettings) => supacudy<{ applied: boolean }>('ddns_set', s);

export function domainError(s: string): boolean {
  return s.length > 253 || !/^[A-Za-z0-9]([A-Za-z0-9-]{0,62})(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}))+$/.test(s);
}
