// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Key } from './i18n/index.svelte';

export type Route = 'overview' | 'settings';

export interface RouteEntry {
  route: Route;
  label: Key;
  icon: 'home' | 'settings';
}

export const ROUTES: readonly RouteEntry[] = [
  { route: 'overview', label: 'nav.overview', icon: 'home' },
  { route: 'settings', label: 'nav.settings', icon: 'settings' },
];

const DEFAULT_ROUTE: Route = 'overview';

export function parseHash(hash: string): Route {
  const name = hash.replace(/^#\/?/, '');
  return ROUTES.some((entry) => entry.route === name) ? (name as Route) : DEFAULT_ROUTE;
}

export function href(route: Route): string {
  return `#/${route}`;
}

const state = $state({ route: parseHash(typeof location === 'undefined' ? '' : location.hash) });

if (typeof window !== 'undefined') {
  window.addEventListener('hashchange', () => {
    state.route = parseHash(location.hash);
  });
}

export function currentRoute(): Route {
  return state.route;
}
