// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export interface Reservation {
  id: string;
  mac: string;
  ip: string;
  name: string | null;
}

export interface LanConfig {
  ipaddr: string;
  netmask: string;
  prefix: number;
  dhcp: {
    enabled: boolean;
    start: number;
    limit: number;
    leasetime: string;
    first: string;
    last: string;
  };
  reservations: Reservation[];
}

export interface LanSettings {
  ipaddr: string;
  netmask: string;
  dhcp_enabled: boolean;
  start: number;
  limit: number;
  leasetime: string;
}

export const getLan = () => supacudy<LanConfig>('lan_get');

export const setLan = (settings: LanSettings) =>
  supacudy<{ applied: boolean; address_changed: boolean; ipaddr: string }>('lan_set', settings);

export const setReservation = (mac: string, ip: string, name = '') =>
  supacudy<{ mac: string; ip: string; name: string | null }>('reservation_set', { mac, ip, name });

export const deleteReservation = (mac: string) =>
  supacudy<{ mac: string; deleted: boolean }>('reservation_delete', { mac });
