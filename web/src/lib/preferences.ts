// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// Per-browser UI preferences (sort order and the like). Storage may be
// unavailable, so every access falls back silently.

const PREFIX = 'supacudy.pref.';

export function readPreference<T extends string>(key: string, allowed: readonly T[], fallback: T): T {
  try {
    const value = localStorage.getItem(PREFIX + key);
    return value !== null && (allowed as readonly string[]).includes(value) ? (value as T) : fallback;
  } catch {
    return fallback;
  }
}

export function writePreference(key: string, value: string): void {
  try {
    localStorage.setItem(PREFIX + key, value);
  } catch {
    // Not persisted; the choice still applies for this page load.
  }
}
