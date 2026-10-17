// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { inSubnet, intToIpv4, ipv4ToInt, isIPv4, isMac, normalizeMac, prefixToNetmask } from '../../src/lib/validate';

describe('isIPv4', () => {
  it.each(['0.0.0.0', '192.168.1.1', '255.255.255.255', ' 10.0.0.1 '])('accepts %s', (ip) => {
    expect(isIPv4(ip)).toBe(true);
  });

  it.each(['', '192.168.1', '192.168.1.256', '192.168.01.1', '1.2.3.4.5', 'a.b.c.d', '1..2.3'])('rejects %j', (ip) => {
    expect(isIPv4(ip)).toBe(false);
  });
});

describe('IPv4 conversions', () => {
  it('round-trips', () => {
    for (const ip of ['0.0.0.0', '10.250.3.15', '192.168.200.1', '255.255.255.255']) expect(intToIpv4(ipv4ToInt(ip))).toBe(ip);
  });

  it.each([
    [24, '255.255.255.0'],
    [16, '255.255.0.0'],
    [30, '255.255.255.252'],
    [0, '0.0.0.0'],
    [32, '255.255.255.255'],
  ])('/%i is %s', (prefix, mask) => {
    expect(prefixToNetmask(prefix)).toBe(mask);
  });
});

describe('inSubnet', () => {
  it('accepts host addresses only', () => {
    expect(inSubnet('192.168.1.10', '192.168.1.0', 24)).toBe(true);
    expect(inSubnet('192.168.1.0', '192.168.1.0', 24)).toBe(false);
    expect(inSubnet('192.168.1.255', '192.168.1.0', 24)).toBe(false);
    expect(inSubnet('192.168.2.10', '192.168.1.0', 24)).toBe(false);
    expect(inSubnet('192.168.3.10', '192.168.0.0', 22)).toBe(true);
    expect(inSubnet('not an ip', '192.168.1.0', 24)).toBe(false);
  });
});

describe('MAC addresses', () => {
  it.each(['aa:bb:cc:dd:ee:ff', 'AA-BB-CC-DD-EE-FF', ' 00:11:22:33:44:55 '])('accepts %s', (mac) => {
    expect(isMac(mac)).toBe(true);
  });

  it.each(['', 'aa:bb:cc:dd:ee', 'aa:bb:cc:dd:ee:fg', 'aabbccddeeff'])('rejects %j', (mac) => {
    expect(isMac(mac)).toBe(false);
  });

  it('normalizes to lower case with colons', () => {
    expect(normalizeMac(' AA-BB-CC-DD-EE-FF ')).toBe('aa:bb:cc:dd:ee:ff');
  });
});
