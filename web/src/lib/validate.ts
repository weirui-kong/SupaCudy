// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// Client-side checks for fast feedback only; the router validates again.

export function isIPv4(value: string): boolean {
  const parts = value.trim().split('.');
  return parts.length === 4 && parts.every((p) => /^\d{1,3}$/.test(p) && Number(p) <= 255 && String(Number(p)) === p);
}

export function ipv4ToInt(value: string): number {
  return value.split('.').reduce((n, octet) => n * 256 + Number(octet), 0);
}

export function intToIpv4(n: number): string {
  return [24, 16, 8, 0].map((shift) => Math.floor(n / 2 ** shift) % 256).join('.');
}

export function isMac(value: string): boolean {
  return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(value.trim());
}

export function normalizeMac(value: string): string {
  return value.trim().toLowerCase().replaceAll('-', ':');
}

export function prefixToNetmask(prefix: number): string {
  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  return intToIpv4(mask);
}

export function inSubnet(ip: string, network: string, prefix: number): boolean {
  if (!isIPv4(ip) || !isIPv4(network)) return false;
  const size = 2 ** (32 - prefix);
  const base = Math.floor(ipv4ToInt(network) / size) * size;
  const n = ipv4ToInt(ip);
  return n > base && n < base + size - 1;
}
