// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { MORE, ROUTES, entryFor, href, parseHash } from '../../src/lib/router.svelte';

describe('parseHash', () => {
  it.each([
    ['', 'overview'],
    ['#', 'overview'],
    ['#/', 'overview'],
    ['#/overview', 'overview'],
    ['#/settings', 'settings'],
    ['#/clients', 'clients'],
    ['#/lan', 'lan'],
    ['#/internet', 'internet'],
    ['#/more', 'more'],
    ['#settings', 'settings'],
    ['#/unknown', 'overview'],
    ['#/settings/extra', 'overview'],
    ['#/<script>', 'overview'],
  ])('%s -> %s', (hash, route) => {
    expect(parseHash(hash)).toBe(route);
  });

  it('round-trips every route through href', () => {
    for (const entry of [...ROUTES, MORE]) expect(parseHash(href(entry.route))).toBe(entry.route);
  });

  it('finds the entry for every route', () => {
    for (const entry of [...ROUTES, MORE]) expect(entryFor(entry.route)).toBe(entry);
  });

  it('keeps the phone bottom bar short enough to tap', () => {
    expect(ROUTES.filter((r) => r.primary).length + 1).toBeLessThanOrEqual(5);
  });
});

describe('uplinkName', () => {
  it.each([
    ['wan', 'internet.ethernet'],
    ['wwan', 'internet.repeater'],
    ['tethering', 'tethering.title'],
    ['vpn', null],
    [null, null],
  ])('%s -> %s', async (active, key) => {
    const { uplinkName } = await import('../../src/lib/uplink');
    expect(uplinkName(active)).toBe(key);
  });
});
