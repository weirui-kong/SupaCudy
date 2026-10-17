// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { setLocale } from '../../src/lib/i18n/index.svelte';

// A fresh copy per test: notify keeps module-level state. ApiError must come
// from the same fresh module graph, or instanceof checks fail.
const load = async () => ({
  notify: await import('../../src/lib/notify.svelte'),
  ApiError: (await import('../../src/lib/api')).ApiError,
});

describe('apply', () => {
  beforeEach(() => {
    vi.resetModules();
    setLocale('en');
  });

  it('shows "Applying" while the change runs, then success', async () => {
    const { notify } = await load();
    let finish!: (v: string) => void;
    const result = notify.apply(() => new Promise<string>((r) => (finish = r)), 'Done!');

    expect(notify.notices().map((n) => [n.kind, n.message])).toEqual([['applying', 'Applying…']]);
    finish('value');
    await expect(result).resolves.toBe('value');
    expect(notify.notices().map((n) => [n.kind, n.message])).toEqual([['success', 'Done!']]);
  });

  it('explains a failure and returns null', async () => {
    const { notify, ApiError } = await load();
    const result = await notify.apply(() => Promise.reject(new ApiError('rejected', null, 'ip_taken')));

    expect(result).toBeNull();
    expect(notify.notices().map((n) => n.kind)).toEqual(['error']);
    expect(notify.notices()[0].message).toBe('Another device already has this address reserved.');
  });

  it('dismisses success after a while but keeps errors longer', async () => {
    vi.useFakeTimers();
    const { notify, ApiError } = await load();
    await notify.apply(() => Promise.resolve(1));
    await notify.apply(() => Promise.reject(new ApiError('network')));
    expect(notify.notices()).toHaveLength(2);

    vi.advanceTimersByTime(3500);
    expect(notify.notices().map((n) => n.kind)).toEqual(['error']);
    vi.advanceTimersByTime(5000);
    expect(notify.notices()).toHaveLength(0);
  });

  it('can be dismissed by hand', async () => {
    const { notify, ApiError } = await load();
    await notify.apply(() => Promise.reject(new ApiError('network')));
    notify.dismiss(notify.notices()[0].id);
    expect(notify.notices()).toHaveLength(0);
  });
});
