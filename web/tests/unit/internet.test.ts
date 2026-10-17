// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { joinable, needsPassword, signalBars, type StaEncryption } from '../../src/lib/api';

describe('joinable', () => {
  it.each<[StaEncryption, boolean]>([
    ['none', true], ['owe', true], ['psk2', true], ['psk-mixed', true], ['sae', true], ['sae-mixed', true],
    ['enterprise', false], ['wep', false],
  ])('%s -> %s', (encryption, expected) => {
    expect(joinable(encryption)).toBe(expected);
  });
});

describe('needsPassword', () => {
  it.each<[StaEncryption, boolean]>([
    ['none', false], ['owe', false], ['psk2', true], ['sae', true], ['sae-mixed', true],
  ])('%s -> %s', (encryption, expected) => {
    expect(needsPassword(encryption)).toBe(expected);
  });
});

describe('signalBars', () => {
  it.each<[number | null, number]>([
    [null, 0], [-30, 4], [-55, 4], [-56, 3], [-65, 3], [-70, 2], [-75, 2], [-80, 1], [-85, 1], [-86, 0], [-100, 0],
  ])('%s dBm -> %s bars', (dbm, bars) => {
    expect(signalBars(dbm)).toBe(bars);
  });
});
