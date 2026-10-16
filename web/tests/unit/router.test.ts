// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { ROUTES, href, parseHash } from '../../src/lib/router.svelte';

describe('parseHash', () => {
  it.each([
    ['', 'overview'],
    ['#', 'overview'],
    ['#/', 'overview'],
    ['#/overview', 'overview'],
    ['#/settings', 'settings'],
    ['#settings', 'settings'],
    ['#/unknown', 'overview'],
    ['#/settings/extra', 'overview'],
    ['#/<script>', 'overview'],
  ])('%s -> %s', (hash, route) => {
    expect(parseHash(hash)).toBe(route);
  });

  it('round-trips every route through href', () => {
    for (const entry of ROUTES) expect(parseHash(href(entry.route))).toBe(entry.route);
  });
});
