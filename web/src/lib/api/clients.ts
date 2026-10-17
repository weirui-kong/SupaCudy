// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export const CLIENT_TYPES = [
  'phone', 'tablet', 'laptop', 'desktop', 'tv', 'camera', 'printer',
  'speaker', 'watch', 'game', 'appliance', 'gateway', 'nas', 'other',
] as const;

export type ClientType = (typeof CLIENT_TYPES)[number];

export interface Client {
  mac: string;
  ip: string | null;
  hostname: string | null;
  name: string | null;
  type: ClientType | null;
  online: boolean;
  connection: 'wifi' | 'wired' | null;
  band: '2g' | '5g' | '6g' | null;
  network: string;
  signal: number | null;
  random_mac: boolean;
  blocked: boolean;
  /** KB/s, 0 means unlimited. */
  up_limit: number;
  down_limit: number;
  /** Cumulative bytes since the counters were last reset. */
  tx_bytes: number;
  rx_bytes: number;
  reserved_ip: string | null;
}

export interface ClientList {
  clients: Client[];
  /** Router uptime in seconds when the list was taken, for speed calculation. */
  time: number;
}

export const listClients = () => supacudy<ClientList>('clients_list');

export const setClientInfo = (mac: string, name: string, type: ClientType | '') =>
  supacudy<{ mac: string; name: string | null; type: ClientType | null }>('client_set', { mac, name, type });

export const setClientBlocked = (mac: string, blocked: boolean) =>
  supacudy<{ mac: string; blocked: boolean }>('client_block', { mac, blocked });

export const setClientLimit = (mac: string, up: number, down: number) =>
  supacudy<{ mac: string; up_limit: number; down_limit: number }>('client_limit', { mac, up, down });

export const forgetOfflineClients = () => supacudy<{ forgotten: number }>('clients_forget_offline');

export const resetClientCounters = () => supacudy<{ reset: boolean }>('clients_reset_counters');

export function clientLabel(client: Pick<Client, 'name' | 'hostname' | 'mac'>): string {
  return client.name || client.hostname || client.mac.toUpperCase();
}
