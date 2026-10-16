// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { beforeEach, describe, expect, it, vi } from 'vitest';
import en from '../../src/lib/i18n/en';
import zhCN from '../../src/lib/i18n/zh-CN';
import { detectLocale, type Key } from '../../src/lib/i18n/index.svelte';

function leaves(node: object, prefix = ''): Map<string, string> {
  const out = new Map<string, string>();
  for (const [key, value] of Object.entries(node)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof value === 'string') out.set(path, value);
    else for (const [k, v] of leaves(value, path)) out.set(k, v);
  }
  return out;
}

const placeholders = (text: string) => [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

describe('catalogs', () => {
  const enLeaves = leaves(en);
  const zhLeaves = leaves(zhCN);

  it('have exactly the same keys', () => {
    expect([...zhLeaves.keys()].sort()).toEqual([...enLeaves.keys()].sort());
  });

  it('have no empty messages', () => {
    for (const [key, text] of [...enLeaves, ...zhLeaves]) expect(text.trim(), key).not.toBe('');
  });

  it('use the same placeholders in both languages', () => {
    for (const [key, text] of enLeaves) expect(placeholders(zhLeaves.get(key)!), key).toEqual(placeholders(text));
  });

  it('contain no raw-key markers', () => {
    for (const [key, text] of [...enLeaves, ...zhLeaves]) expect(text, key).not.toMatch(/⟦|⟧/);
  });

  it('actually translate user-facing text into Chinese', () => {
    expect(zhLeaves.get('login.submit')).not.toBe(enLeaves.get('login.submit'));
    expect(zhLeaves.get('overview.title')).toMatch(/[一-鿿]/);
  });
});

describe('detectLocale', () => {
  it.each([
    [null, ['zh-CN'], 'zh-CN'],
    [null, ['zh-TW', 'en'], 'zh-CN'],
    [null, ['zh'], 'zh-CN'],
    [null, ['en-GB'], 'en'],
    [null, ['de-DE', 'fr'], 'en'],
    [null, [], 'en'],
    [null, ['fr', 'zh-CN'], 'zh-CN'],
    ['en', ['zh-CN'], 'en'],
    ['zh-CN', ['en-US'], 'zh-CN'],
    ['de', ['zh-CN'], 'zh-CN'],
  ] as const)('stored=%s browser=%j -> %s', (stored, browser, expected) => {
    expect(detectLocale(stored, browser)).toBe(expected);
  });
});

describe('t and setLocale', () => {
  beforeEach(() => {
    vi.resetModules();
  });

  async function load(browser: string[] = ['en-US']) {
    vi.stubGlobal('navigator', { ...navigator, languages: browser });
    return import('../../src/lib/i18n/index.svelte');
  }

  it('follows the browser language on first visit', async () => {
    const i18n = await load(['zh-CN']);
    expect(i18n.locale()).toBe('zh-CN');
    expect(document.documentElement.lang).toBe('zh-CN');
    expect(i18n.t('login.submit')).toBe('登录');
  });

  it('interpolates parameters', async () => {
    const i18n = await load();
    expect(i18n.t('time.hours_minutes', { h: 3, m: 7 })).toBe('3 h 7 min');
  });

  it('leaves unknown placeholders untouched', async () => {
    const i18n = await load();
    expect(i18n.t('time.minutes')).toBe('{m} min');
  });

  it('marks a missing key instead of showing nothing', async () => {
    const i18n = await load();
    expect(i18n.t('does.not.exist' as Key)).toBe('⟦does.not.exist⟧');
  });

  it('switches language, updates <html lang> and remembers the choice', async () => {
    const i18n = await load(['en-US']);
    i18n.setLocale('zh-CN');
    expect(i18n.t('nav.settings')).toBe('设置');
    expect(document.documentElement.lang).toBe('zh-CN');
    expect(localStorage.getItem('supacudy.locale')).toBe('zh-CN');

    vi.resetModules();
    const reloaded = await load(['en-US']);
    expect(reloaded.locale()).toBe('zh-CN');
  });

  it('keeps working when storage is unavailable', async () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    const i18n = await load();
    expect(() => i18n.setLocale('zh-CN')).not.toThrow();
    expect(i18n.locale()).toBe('zh-CN');
  });
});
