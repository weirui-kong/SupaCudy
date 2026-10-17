// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Key, Locale } from './i18n/index.svelte';

type Translate = (key: Key, params?: Record<string, string | number>) => string;

const UNITS = ['B', 'KB', 'MB', 'GB', 'TB'];

export function formatBytes(bytes: number, locale: Locale): string {
  let value = Math.max(0, bytes);
  let unit = 0;
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024;
    unit++;
  }
  const digits = unit === 0 || value >= 100 ? 0 : 1;
  const number = new Intl.NumberFormat(locale, {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
    useGrouping: false,
  }).format(value);
  return `${number} ${UNITS[unit]}`;
}

export function formatDuration(totalSeconds: number, t: Translate): string {
  const minutes = Math.floor(Math.max(0, totalSeconds) / 60);
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  if (days > 0) return t('time.days_hours', { d: days, h: hours });
  if (hours > 0) return t('time.hours_minutes', { h: hours, m: minutes % 60 });
  return t('time.minutes', { m: minutes });
}

export function formatLoad(value: number, locale: Locale): string {
  return new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value);
}

// The router's zone table uses spaces where IANA names use underscores.
export function ianaZone(zonename: string): string {
  return zonename.replace(/ /g, '_');
}

export function formatClock(epochMs: number, timeZone: string, locale: string): string {
  const options: Intl.DateTimeFormatOptions = { dateStyle: 'medium', timeStyle: 'medium' };
  try {
    return new Intl.DateTimeFormat(locale, { ...options, timeZone }).format(epochMs);
  } catch {
    // A zone the browser does not know: show UTC and say so.
    return `${new Intl.DateTimeFormat(locale, { ...options, timeZone: 'UTC' }).format(epochMs)} UTC`;
  }
}
