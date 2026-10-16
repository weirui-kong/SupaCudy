// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

export type ThemePreference = 'system' | 'light' | 'dark';

export const THEMES: readonly ThemePreference[] = ['system', 'light', 'dark'];

// Must match the key read by the inline script in index.html.
const STORAGE_KEY = 'supacudy.theme';

function readStored(): ThemePreference {
  try {
    const value = localStorage.getItem(STORAGE_KEY);
    return value === 'light' || value === 'dark' ? value : 'system';
  } catch {
    return 'system';
  }
}

const state = $state({ preference: readStored() });

function apply(preference: ThemePreference): void {
  if (preference === 'system') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = preference;
}

if (typeof document !== 'undefined') apply(state.preference);

export function themePreference(): ThemePreference {
  return state.preference;
}

export function setThemePreference(next: ThemePreference): void {
  state.preference = next;
  apply(next);
  try {
    if (next === 'system') localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, next);
  } catch {
    // Private mode: the choice just lasts for this page load.
  }
}
