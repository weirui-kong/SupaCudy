// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { IconName } from '../components/Icon.svelte';
import { clientLabel, type Client, type ClientList, type ClientType } from './api';

export interface Rate {
  up: number;
  down: number;
}

export interface Sample {
  time: number;
  tx: number;
  rx: number;
}

export const SORT_KEYS = ['name', 'ip', 'upload', 'download'] as const;
export type SortKey = (typeof SORT_KEYS)[number];

const TYPE_ICONS: Record<ClientType, IconName> = {
  phone: 'phone',
  tablet: 'tablet',
  laptop: 'laptop',
  desktop: 'desktop',
  tv: 'tv',
  camera: 'camera',
  printer: 'printer',
  speaker: 'speaker',
  watch: 'watch',
  game: 'game',
  appliance: 'appliance',
  gateway: 'router',
  nas: 'nas',
  other: 'device',
};

export function clientIcon(client: Pick<Client, 'type' | 'connection'>): IconName {
  if (client.type) return TYPE_ICONS[client.type];
  return client.connection === 'wifi' ? 'phone' : 'desktop';
}

// Speeds come from counter deltas between two polls. A counter that went
// down (reset, or the router rebooted) gives no rate rather than a negative.
export function rates(previous: Map<string, Sample>, list: ClientList): Map<string, Rate> {
  const out = new Map<string, Rate>();
  for (const client of list.clients) {
    const before = previous.get(client.mac);
    const elapsed = before ? list.time - before.time : 0;
    if (!before || elapsed <= 0 || client.tx_bytes < before.tx || client.rx_bytes < before.rx) continue;
    out.set(client.mac, {
      up: (client.tx_bytes - before.tx) / elapsed,
      down: (client.rx_bytes - before.rx) / elapsed,
    });
  }
  return out;
}

export function samples(list: ClientList): Map<string, Sample> {
  return new Map(list.clients.map((c) => [c.mac, { time: list.time, tx: c.tx_bytes, rx: c.rx_bytes }]));
}

function ipValue(ip: string | null): number {
  if (!ip) return Number.MAX_SAFE_INTEGER;
  return ip.split('.').reduce((n, octet) => n * 256 + Number(octet), 0);
}

export function sortClients(clients: readonly Client[], key: SortKey, speeds: Map<string, Rate>, locale: string): Client[] {
  const byName = (a: Client, b: Client) => clientLabel(a).localeCompare(clientLabel(b), locale, { sensitivity: 'base' });
  const compare: Record<SortKey, (a: Client, b: Client) => number> = {
    name: byName,
    ip: (a, b) => ipValue(a.ip) - ipValue(b.ip),
    upload: (a, b) => (speeds.get(b.mac)?.up ?? 0) - (speeds.get(a.mac)?.up ?? 0) || byName(a, b),
    download: (a, b) => (speeds.get(b.mac)?.down ?? 0) - (speeds.get(a.mac)?.down ?? 0) || byName(a, b),
  };
  return [...clients].sort(compare[key]);
}
