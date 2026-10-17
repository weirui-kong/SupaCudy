// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const;
export type Weekday = (typeof WEEKDAYS)[number];

export interface Schedule {
  enabled: boolean;
  days: Weekday[];
  /** "HH:MM", router time. */
  start: string;
  /** Only for Wi-Fi off: when it comes back. */
  end: string;
}

export interface ParentalRule {
  id: string;
  name: string;
  macs: string[];
  days: Weekday[];
  start: string;
  end: string;
  enabled: boolean;
}

export interface ScheduleState {
  reboot: Schedule;
  wifi_off: Schedule;
  parental: ParentalRule[];
}

export const getSchedules = () => supacudy<ScheduleState>('schedule_get');
export const setSchedule = (kind: 'reboot' | 'wifi_off', s: Schedule) =>
  supacudy<{ applied: boolean }>('schedule_set', { kind, ...s, end: kind === 'reboot' ? '' : s.end });
export const saveParentalRule = (r: ParentalRule) => supacudy<{ id: string }>('parental_set', r);
export const deleteParentalRule = (id: string) => supacudy<{ deleted: boolean }>('parental_delete', { id });

export const OFFLOAD_MODES = ['off', 'software', 'hardware'] as const;
export type OffloadMode = (typeof OFFLOAD_MODES)[number];
export const setOffload = (mode: OffloadMode) => supacudy<{ applied: boolean }>('offload_set', { mode });

export const isTime = (s: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(s);
