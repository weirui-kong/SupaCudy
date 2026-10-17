// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export interface DeviceInfo {
  version: string | null;
  openwrt: string | null;
  revision: string | null;
  board: string | null;
  model: string | null;
}

export interface SystemStatus {
  uptime: number;
  load: [number, number, number];
  cpus: number;
  memory: { total: number; available: number };
  /** Flash space for settings and packages; null when it cannot be read. */
  storage: { total: number; available: number } | null;
}

export const getDeviceInfo = () => supacudy<DeviceInfo>('info');
export const getSystemStatus = () => supacudy<SystemStatus>('status');

export interface TimeSettings {
  /** Seconds since the epoch on the router. */
  time: number;
  zonename: string;
  ntp: boolean;
  /** Names the router knows, e.g. "Asia/Shanghai". */
  zones: string[];
}

export interface FirmwareCheck {
  valid: boolean;
  /** The image can only be installed by forcing it; never offered in the UI. */
  forceable: boolean;
  /** The image can keep the current settings. */
  allow_backup: boolean;
  size: number;
}

export const FIRMWARE_PATH = '/tmp/firmware.bin';
export const PASSWORD_MIN = 8;
export const PASSWORD_MAX = 128;
/** Factory login for SSH, this page and AdGuard Home (user root). */
export const DEFAULT_PASSWORD = 'supacudy';

// AdGuard Home only takes bcrypt hashes and the router has no tool to make
// one, so the browser does. Loaded on demand to keep the main bundle small.
export async function loginHash(password: string): Promise<string> {
  const { hash } = await import('bcryptjs');
  return hash(password, 10);
}

export const getTimeSettings = () => supacudy<TimeSettings>('time_get');
/** `time` is a browser clock in seconds to copy, or 0 to leave the clock alone. */
export const setTimeSettings = (zonename: string, ntp: boolean, time = 0) =>
  supacudy<{ applied: boolean }>('time_set', { zonename, ntp, time });
// One password for every login, so AdGuard Home gets it too.
export const setAdminPassword = async (password: string) =>
  supacudy<{ changed: boolean }>('password_set', { password, hash: await loginHash(password) });
export const rebootRouter = () => supacudy<{ rebooting: boolean }>('reboot');
export const factoryReset = () => supacudy<{ resetting: boolean }>('factory_reset');
export const checkFirmware = () => supacudy<FirmwareCheck>('firmware_check');
export const upgradeFirmware = (keep_settings: boolean) => supacudy<{ upgrading: boolean }>('firmware_upgrade', { keep_settings });
export const discardFirmware = () => supacudy<{ discarded: boolean }>('firmware_discard');

export function passwordError(password: string): 'too_short' | 'too_long' | 'invalid' | 'default' | null {
  if (password.length < PASSWORD_MIN) return 'too_short';
  if (password.length > PASSWORD_MAX) return 'too_long';
  if (/[\x00-\x1f\x7f]/.test(password)) return 'invalid';
  if (password === DEFAULT_PASSWORD) return 'default';
  return null;
}

export interface LogEntry {
  /** As the router prints it, e.g. "Sat Oct 17 04:18:29 2026"; null for lines it could not parse. */
  time: string | null;
  facility: string | null;
  level: string | null;
  source: string | null;
  message: string;
}

export const LOG_LINES = 500;
export const getLogs = (lines = LOG_LINES) => supacudy<{ entries: LogEntry[] }>('log_get', { lines });

const PROBLEM_LEVELS = new Set(['emerg', 'alert', 'crit', 'err', 'warn', 'warning']);

export function isProblem(entry: LogEntry): boolean {
  return entry.level !== null && PROBLEM_LEVELS.has(entry.level);
}

export function logText(entries: readonly LogEntry[]): string {
  return entries
    .map((e) => (e.time ? `${e.time} ${e.facility}.${e.level} ${e.source}: ${e.message}` : e.message))
    .join('\n') + '\n';
}
