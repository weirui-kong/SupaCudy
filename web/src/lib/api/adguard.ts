// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';
import { loginHash } from './system';

export interface AdguardList {
  name: string;
  url: string;
  enabled: boolean;
  rules: number | null;
}

// Everything except installed/enabled/web is read live from AdGuard Home;
// null means it did not answer.
export interface AdguardState {
  installed: boolean;
  enabled: boolean;
  running: boolean;
  /** Its page has a login SupaCudy does not know, so nothing can be read. */
  locked: boolean;
  /** AdGuard Home stopped and the router answers DNS without filtering. */
  fallback: boolean;
  protection: boolean | null;
  filters: AdguardList[] | null;
  suggested: { name: string; url: string }[];
  rules: string[] | null;
  /** synced: AdGuard Home has the current admin password. */
  web: { enabled: boolean; user: string | null; port: number; synced: boolean };
  stats: {
    queries: number;
    blocked: number;
    avg_ms: number;
    top_blocked: { name: string; count: number }[];
    top_clients: { name: string; count: number }[];
  } | null;
}

type Applied = { applied: boolean };

export const getAdguard = () => supacudy<AdguardState>('adguard_get');
export const setAdguardEnabled = (enabled: boolean) => supacudy<Applied>('adguard_set', { enabled });
export const setAdguardProtection = (enabled: boolean) => supacudy<Applied>('adguard_protection', { enabled });
export const addAdguardList = (url: string, name: string) => supacudy<Applied>('adguard_list_add', { url, name });
export const setAdguardList = (l: { url: string; name: string; enabled: boolean }) => supacudy<Applied>('adguard_list_set', l);
export const removeAdguardList = (url: string) => supacudy<Applied>('adguard_list_remove', { url });
export const setAdguardRules = (rules: string[]) => supacudy<Applied>('adguard_rules_set', { rules });

// The page uses the admin password (user root). It is only sent when
// AdGuard Home does not have it yet, after the browser checked it.
export async function setAdguardWeb(enabled: boolean, password = '') {
  return supacudy<Applied>('adguard_web_set', { enabled, password, hash: password ? await loginHash(password) : '' });
}

export const lines = (s: string) => s.split('\n').map((l) => l.trim()).filter(Boolean);

export function filterUrlError(url: string): boolean {
  return url.length > 512 || !/^https?:\/\/[A-Za-z0-9.-]+(:\d+)?\/[!-~]*$/.test(url);
}

// AdGuard Home needs a name for every list; the host is the best we have.
export const listNameOf = (url: string) => url.replace(/^https?:\/\//, '').split('/')[0] || url;
