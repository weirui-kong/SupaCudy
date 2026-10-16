// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { beforeEach, describe, expect, it, vi } from 'vitest';

const load = () => import('../../src/lib/theme.svelte');

describe('theme preference', () => {
  beforeEach(() => {
    vi.resetModules();
  });

  it('follows the system by default', async () => {
    const theme = await load();
    expect(theme.themePreference()).toBe('system');
    expect(document.documentElement.dataset.theme).toBeUndefined();
  });

  it.each(['light', 'dark'] as const)('forces %s and remembers it', async (choice) => {
    const theme = await load();
    theme.setThemePreference(choice);
    expect(document.documentElement.dataset.theme).toBe(choice);
    expect(localStorage.getItem('supacudy.theme')).toBe(choice);

    vi.resetModules();
    delete document.documentElement.dataset.theme;
    const reloaded = await load();
    expect(reloaded.themePreference()).toBe(choice);
    expect(document.documentElement.dataset.theme).toBe(choice);
  });

  it('goes back to the system setting and forgets the override', async () => {
    const theme = await load();
    theme.setThemePreference('dark');
    theme.setThemePreference('system');
    expect(document.documentElement.dataset.theme).toBeUndefined();
    expect(localStorage.getItem('supacudy.theme')).toBeNull();
  });

  it('ignores an invalid stored value', async () => {
    localStorage.setItem('supacudy.theme', 'purple');
    const theme = await load();
    expect(theme.themePreference()).toBe('system');
    expect(document.documentElement.dataset.theme).toBeUndefined();
  });

  it('still applies the theme when storage is unavailable', async () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    const theme = await load();
    theme.setThemePreference('dark');
    expect(document.documentElement.dataset.theme).toBe('dark');
  });
});
