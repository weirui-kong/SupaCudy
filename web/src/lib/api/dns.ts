// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export const DNS_MODES = ['auto', 'manual', 'encrypted'] as const;
export type DnsMode = (typeof DNS_MODES)[number];

// Providers the router knows; it may offer others, shown by their id.
export const DOH_PROVIDERS = ['alidns', 'cloudflare', 'google', 'quad9', 'adguard', 'dnspod'] as const;
export type DohProvider = (typeof DOH_PROVIDERS)[number];

export function isKnownProvider(id: string): id is DohProvider {
  return (DOH_PROVIDERS as readonly string[]).includes(id);
}

export interface DnsSettings {
  mode: DnsMode;
  servers: string[];
  /** A key of `providers`, or "custom" with `url`. */
  provider: string;
  url: string;
  providers: string[];
  encrypted_available: boolean;
  rebind_protection: boolean;
  hosts: LocalHost[];
}

export interface LocalHost {
  id: string;
  name: string;
  ip: string;
}

export interface DnsChange {
  mode: DnsMode;
  servers: string[];
  provider: string;
  url: string;
}

export const getDns = () => supacudy<DnsSettings>('dns_get');
export const setDns = (change: DnsChange) => supacudy<{ applied: boolean }>('dns_set', change);

export const setRebindProtection = (enabled: boolean) => supacudy<{ applied: boolean }>('dns_rebind_set', { enabled });
export const saveLocalHost = (h: LocalHost) => supacudy<{ id: string }>('host_set', h);
export const deleteLocalHost = (id: string) => supacudy<{ deleted: boolean }>('host_delete', { id });

export function hostnameError(name: string): boolean {
  return name.length > 253 || !/^[A-Za-z0-9]([A-Za-z0-9-]{0,62})(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}))*$/.test(name);
}

export function dohUrlError(url: string): boolean {
  return !/^https:\/\/[A-Za-z0-9.-]+(:\d+)?\/[!-~]*$/.test(url) || url.length > 256;
}
