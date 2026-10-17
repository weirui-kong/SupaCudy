// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { formatBytes, formatClock, formatDuration, formatLoad, ianaZone } from '../../src/lib/format';
import en from '../../src/lib/i18n/en';
import zhCN from '../../src/lib/i18n/zh-CN';
import { lookup, type Key } from '../../src/lib/i18n/index.svelte';

const translator = (catalog: object) => (key: Key, params: Record<string, string | number> = {}) =>
  lookup(catalog, key)!.replace(/\{(\w+)\}/g, (_m, name: string) => String(params[name]));

describe('formatBytes', () => {
  it.each([
    [0, '0 B'],
    [1023, '1023 B'],
    [1024, '1.0 KB'],
    [1536, '1.5 KB'],
    [512 * 1024 ** 2, '512 MB'],
    [128.4 * 1024 ** 2, '128 MB'],
    [1.25 * 1024 ** 3, '1.3 GB'],
    [3 * 1024 ** 5, '3072 TB'],
  ])('%d bytes -> %s', (bytes, expected) => {
    expect(formatBytes(bytes, 'en')).toBe(expected);
  });

  it('never shows negative sizes', () => {
    expect(formatBytes(-5, 'en')).toBe('0 B');
  });

  it('formats numbers for the Chinese locale too', () => {
    expect(formatBytes(1536, 'zh-CN')).toBe('1.5 KB');
  });
});

describe('formatDuration', () => {
  const t = translator(en);
  const tZh = translator(zhCN);

  it.each([
    [0, '0 min'],
    [59, '0 min'],
    [61, '1 min'],
    [3600, '1 h 0 min'],
    [3 * 3600 + 25 * 60, '3 h 25 min'],
    [86400, '1 d 0 h'],
    [2 * 86400 + 5 * 3600 + 59 * 60, '2 d 5 h'],
  ])('%d s -> %s', (seconds, expected) => {
    expect(formatDuration(seconds, t)).toBe(expected);
  });

  it('uses the Chinese templates', () => {
    expect(formatDuration(2 * 86400 + 5 * 3600, tZh)).toBe('2 天 5 小时');
    expect(formatDuration(125 * 60, tZh)).toBe('2 小时 5 分钟');
  });

  it('treats negative values as zero', () => {
    expect(formatDuration(-100, t)).toBe('0 min');
  });
});

describe('formatLoad', () => {
  it('always shows two decimals', () => {
    expect(formatLoad(0, 'en')).toBe('0.00');
    expect(formatLoad(1.5, 'en')).toBe('1.50');
    expect(formatLoad(0.126, 'zh-CN')).toBe('0.13');
  });
});

describe('ianaZone', () => {
  it('turns router zone names into IANA names', () => {
    expect(ianaZone('America/New York')).toBe('America/New_York');
    expect(ianaZone('UTC')).toBe('UTC');
  });
});

describe('formatClock', () => {
  const instant = Date.UTC(2026, 9, 17, 4, 5, 6);

  it('shows the time in the router zone', () => {
    expect(formatClock(instant, 'Asia/Shanghai', 'en')).toContain('12:05:06');
    expect(formatClock(instant, 'UTC', 'en')).toContain('4:05:06');
  });

  it('falls back to UTC, labelled, for a zone the browser does not know', () => {
    expect(formatClock(instant, 'Mars/Base', 'en')).toMatch(/4:05:06.*UTC$/);
  });
});
