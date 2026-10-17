// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { beforeEach, describe, expect, it } from 'vitest';
import { ApiError } from '../../src/lib/api';
import { errorMessage } from '../../src/lib/errors';
import { setLocale } from '../../src/lib/i18n/index.svelte';

describe('errorMessage', () => {
  beforeEach(() => setLocale('en'));

  it.each([
    ['network', 'Cannot reach the router'],
    ['denied', 'session has expired'],
    ['invalid', 'This is a bug'],
    ['not_found', 'may have been removed'],
  ] as const)('explains %s', (code, text) => {
    expect(errorMessage(new ApiError(code))).toContain(text);
  });

  it('uses the specific message for a known rejection reason, with its details', () => {
    expect(errorMessage(new ApiError('rejected', null, 'subnet_conflict', { with: 'guest' }))).toBe(
      'This address range overlaps the guest network.',
    );
  });

  it('still names an unknown rejection reason', () => {
    expect(errorMessage(new ApiError('rejected', null, 'brand_new_reason'))).toBe(
      'The router refused the change (brand_new_reason).',
    );
  });

  it('includes the status code for unknown errors', () => {
    expect(errorMessage(new ApiError('unknown', 9))).toContain('error 9');
  });

  it('handles errors that do not come from the API', () => {
    expect(errorMessage(new Error('boom'))).toContain('error client');
  });

  it('speaks Chinese when the UI does', () => {
    setLocale('zh-CN');
    expect(errorMessage(new ApiError('rejected', null, 'outside_lan'))).toBe('这个地址不在局域网内。');
  });
});
