// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { IconName } from '../components/Icon.svelte';
import type { Key } from './i18n/index.svelte';

export type Route = 'overview' | 'internet' | 'wireless' | 'clients' | 'vpn' | 'remote' | 'lan' | 'dns' | 'adblock' | 'ports' | 'settings' | 'maintenance' | 'schedules' | 'logs' | 'more';

export type RouteGroup = 'main' | 'network' | 'system';

export interface RouteEntry {
  route: Route;
  label: Key;
  icon: IconName;
  group: RouteGroup;
  /** Shown in the phone's bottom bar; everything else is under "More". */
  primary?: boolean;
}

export const ROUTES: readonly RouteEntry[] = [
  { route: 'overview', label: 'nav.overview', icon: 'home', group: 'main', primary: true },
  { route: 'internet', label: 'nav.internet', icon: 'globe', group: 'main', primary: true },
  { route: 'wireless', label: 'nav.wireless', icon: 'wifi', group: 'main', primary: true },
  { route: 'clients', label: 'nav.clients', icon: 'device', group: 'main', primary: true },
  { route: 'vpn', label: 'nav.vpn', icon: 'shield', group: 'main' },
  { route: 'remote', label: 'nav.remote', icon: 'laptop', group: 'main' },
  { route: 'lan', label: 'nav.lan', icon: 'network', group: 'network' },
  { route: 'dns', label: 'nav.dns', icon: 'dns', group: 'network' },
  { route: 'adblock', label: 'nav.adblock', icon: 'shield', group: 'network' },
  { route: 'ports', label: 'nav.ports', icon: 'link', group: 'network' },
  { route: 'settings', label: 'nav.settings', icon: 'settings', group: 'system' },
  { route: 'schedules', label: 'nav.schedules', icon: 'clock', group: 'system' },
  { route: 'maintenance', label: 'nav.maintenance', icon: 'power', group: 'system' },
  { route: 'logs', label: 'nav.logs', icon: 'list', group: 'system' },
];

export const MORE: RouteEntry = { route: 'more', label: 'nav.more', icon: 'apps', group: 'main' };

export const GROUPS: readonly { group: RouteGroup; label: Key | null }[] = [
  { group: 'main', label: null },
  { group: 'network', label: 'nav.group_network' },
  { group: 'system', label: 'nav.group_system' },
];

const DEFAULT_ROUTE: Route = 'overview';

export function parseHash(hash: string): Route {
  const name = hash.replace(/^#\/?/, '');
  if (name === MORE.route) return MORE.route;
  return ROUTES.some((entry) => entry.route === name) ? (name as Route) : DEFAULT_ROUTE;
}

export function href(route: Route): string {
  return `#/${route}`;
}

export function entryFor(route: Route): RouteEntry {
  return route === MORE.route ? MORE : ROUTES.find((entry) => entry.route === route)!;
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

export function navigate(route: Route): void {
  location.hash = href(route);
}
