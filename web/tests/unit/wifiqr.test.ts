// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import { encode } from 'uqr';
import QrCode from '../../src/components/QrCode.svelte';
import { wifiQrPayload } from '../../src/lib/wifiqr';

const net = { ssid: 'Home', encryption: 'psk2' as const, key: 'secret-123', hidden: false };

describe('wifiQrPayload', () => {
  it('describes a WPA network', () => {
    expect(wifiQrPayload(net)).toBe('WIFI:T:WPA;S:Home;P:secret-123;;');
  });

  it('marks open networks without a password', () => {
    expect(wifiQrPayload({ ...net, encryption: 'none' })).toBe('WIFI:T:nopass;S:Home;;');
  });

  it('uses SAE for WPA3-only and WPA for mixed modes', () => {
    expect(wifiQrPayload({ ...net, encryption: 'sae' })).toContain('T:SAE;');
    expect(wifiQrPayload({ ...net, encryption: 'sae-mixed' })).toContain('T:WPA;');
  });

  it('flags hidden networks', () => {
    expect(wifiQrPayload({ ...net, hidden: true })).toBe('WIFI:T:WPA;S:Home;P:secret-123;H:true;;');
  });

  it('escapes the characters the format reserves', () => {
    expect(wifiQrPayload({ ...net, ssid: 'a;b,c:d"e\\f', key: 'p;w' })).toBe('WIFI:T:WPA;S:a\\;b\\,c\\:d\\"e\\\\f;P:p\\;w;;');
  });

  it('keeps non-ASCII names', () => {
    expect(wifiQrPayload({ ...net, ssid: '我的网络' })).toContain('S:我的网络;');
  });
});

describe('QrCode', () => {
  it('draws every dark module of the code', () => {
    render(QrCode, { data: 'WIFI:T:WPA;S:Home;P:secret-123;;', label: 'Join Home' });
    const svg = screen.getByRole('img', { name: 'Join Home' });
    const qr = encode('WIFI:T:WPA;S:Home;P:secret-123;;', { ecc: 'M', border: 2 });
    expect(svg.getAttribute('viewBox')).toBe(`0 0 ${qr.size} ${qr.size}`);
    const dark = qr.data.flat().filter(Boolean).length;
    expect(svg.querySelector('path')!.getAttribute('d')!.match(/M/g)!.length).toBe(dark);
  });
});
