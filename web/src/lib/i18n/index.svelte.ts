// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import en from './en';
import zhCN from './zh-CN';
import type { MessageKey, MessageShape } from './types';

export type Locale = 'en' | 'zh-CN';
export type Key = MessageKey<typeof en>;

export const LOCALES: readonly Locale[] = ['zh-CN', 'en'];
export const catalogs: Record<Locale, MessageShape<typeof en>> = { en, 'zh-CN': zhCN };

const STORAGE_KEY = 'supacudy.locale';

export function detectLocale(stored: string | null, browser: readonly string[]): Locale {
  if (stored === 'en' || stored === 'zh-CN') return stored;
  for (const tag of browser) {
    const lower = tag.toLowerCase();
    if (lower.startsWith('zh')) return 'zh-CN';
    if (lower.startsWith('en')) return 'en';
  }
  return 'en';
}

function readStored(): string | null {
  try {
    return localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

const state = $state({
  locale: detectLocale(readStored(), typeof navigator === 'undefined' ? [] : navigator.languages),
});

if (typeof document !== 'undefined') document.documentElement.lang = state.locale;

export function locale(): Locale {
  return state.locale;
}

export function setLocale(next: Locale): void {
  state.locale = next;
  document.documentElement.lang = next;
  try {
    localStorage.setItem(STORAGE_KEY, next);
  } catch {
    // Private mode: the choice just lasts for this page load.
  }
}

export function lookup(catalog: object, key: string): string | undefined {
  let node: unknown = catalog;
  for (const part of key.split('.')) {
    if (typeof node !== 'object' || node === null || !(part in node)) return undefined;
    node = (node as Record<string, unknown>)[part];
  }
  return typeof node === 'string' ? node : undefined;
}

// A missing key renders as ⟦key⟧ so tests can detect it; the type of `key`
// already rules this out at compile time.
export function t(key: Key, params: Record<string, string | number> = {}): string {
  const template = lookup(catalogs[state.locale], key) ?? lookup(catalogs.en, key) ?? `⟦${key}⟧`;
  return template.replace(/\{(\w+)\}/g, (match, name: string) =>
    name in params ? String(params[name]) : match,
  );
}
