// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { keyError, ssidError } from '../../src/lib/api';

describe('ssidError', () => {
  it('accepts names up to 32 bytes', () => {
    expect(ssidError('a')).toBeNull();
    expect(ssidError('a'.repeat(32))).toBeNull();
    expect(ssidError('家庭网络')).toBeNull();
  });

  it('rejects empty names', () => {
    expect(ssidError('')).toBe('empty');
  });

  it('counts bytes, not characters', () => {
    expect(ssidError('a'.repeat(33))).toBe('too_long');
    // 11 Chinese characters are 33 bytes in UTF-8.
    expect(ssidError('一二三四五六七八九十一')).toBe('too_long');
    expect(ssidError('一二三四五六七八九十')).toBeNull();
  });
});

describe('keyError', () => {
  it('needs no password for an open network', () => {
    expect(keyError('none', '')).toBeNull();
  });

  it.each(['psk2', 'sae', 'sae-mixed', 'psk-mixed'] as const)('enforces 8-63 characters for %s', (encryption) => {
    expect(keyError(encryption, '1234567')).toBe('too_short');
    expect(keyError(encryption, '12345678')).toBeNull();
    expect(keyError(encryption, 'x'.repeat(63))).toBeNull();
    expect(keyError(encryption, 'x'.repeat(64))).toBe('too_long');
  });

  it('allows spaces and symbols but not control or non-ASCII characters', () => {
    expect(keyError('psk2', 'correct horse !@#$')).toBeNull();
    expect(keyError('psk2', 'password\tabc')).toBe('invalid');
    expect(keyError('psk2', '密码密码密码密码')).toBe('invalid');
  });
});
