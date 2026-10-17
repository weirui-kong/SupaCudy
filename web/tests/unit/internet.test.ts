// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import {
  groupNetworks, joinable, needsPassword, pickAccessPoint, signalBars, usesKey, validDomain, type ScannedNetwork, type StaEncryption,
} from '../../src/lib/api';

describe('joinable', () => {
  it.each<[StaEncryption, boolean]>([
    ['none', true], ['owe', true], ['psk2', true], ['psk-mixed', true], ['sae', true], ['sae-mixed', true],
    ['enterprise', true], ['wep', false],
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

describe('usesKey', () => {
  it.each<[StaEncryption, boolean]>([
    ['none', false], ['owe', false], ['psk2', true], ['sae-mixed', true], ['enterprise', false],
  ])('%s -> %s', (encryption, expected) => {
    expect(usesKey(encryption)).toBe(expected);
  });
});

describe('validDomain', () => {
  it.each<[string, boolean]>([
    ['radius.example.edu', true], ['emu-server', true], ['a', true], ['', false], ['-bad.example', false],
    ['bad.example.', false], ['has space.example', false], ['x'.repeat(254), false],
  ])('%s -> %s', (domain, expected) => {
    expect(validDomain(domain)).toBe(expected);
  });
});

const ap = (ssid: string, band: '2g' | '5g', signal: number | null, extra: Partial<ScannedNetwork> = {}): ScannedNetwork => ({
  ssid, bssid: `${ssid}-${band}-${signal}`, band, channel: band === '2g' ? 1 : 36, signal, encryption: 'psk2',
  saved: false, current: false, ...extra,
});

describe('groupNetworks', () => {
  it('puts every band of a name in one entry, strongest network first', () => {
    const groups = groupNetworks([ap('Home', '5g', -60), ap('Cafe', '2g', -40), ap('Home', '2g', -50), ap('Home', '5g', -75)]);
    expect(groups.map((g) => g.ssid)).toEqual(['Cafe', 'Home']);
    expect(groups[1].bands).toEqual(['2g', '5g']);
    expect(groups[1].signal).toBe(-50);
    expect(groups[1].aps.map((n) => n.signal)).toEqual([-50, -60, -75]);
  });

  it('marks a name saved or current when any of its access points is', () => {
    const [g] = groupNetworks([ap('Home', '2g', -50), ap('Home', '5g', -60, { saved: true, current: true })]);
    expect(g).toMatchObject({ saved: true, current: true });
  });

  it('keeps networks without a signal reading', () => {
    expect(groupNetworks([ap('Quiet', '2g', null)])[0].signal).toBeNull();
  });
});

describe('pickAccessPoint', () => {
  it('prefers 5 GHz while its signal is good enough', () => {
    const [g] = groupNetworks([ap('Home', '2g', -45), ap('Home', '5g', -65)]);
    expect(pickAccessPoint(g).band).toBe('5g');
  });

  it('takes the strongest when 5 GHz is weak', () => {
    const [g] = groupNetworks([ap('Home', '2g', -45), ap('Home', '5g', -71)]);
    expect(pickAccessPoint(g).band).toBe('2g');
  });

  it('takes the only band there is', () => {
    const [g] = groupNetworks([ap('Old', '2g', -80)]);
    expect(pickAccessPoint(g).band).toBe('2g');
  });
});
