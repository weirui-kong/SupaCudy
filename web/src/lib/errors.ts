// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { ApiError } from './api';
import { catalogs, locale, lookup, t, type Key } from './i18n/index.svelte';

export function errorMessage(error: unknown): string {
  if (!(error instanceof ApiError)) return t('errors.unknown', { code: 'client' });
  switch (error.code) {
    case 'network':
      return t('errors.network');
    case 'denied':
      return t('errors.denied');
    case 'invalid':
      return t('errors.invalid');
    case 'not_found':
      return t('errors.not_found');
    case 'rejected': {
      // Reasons without a specific message still say what the router sent.
      const key = `errors.reasons.${error.reason}`;
      if (lookup(catalogs[locale()], key) === undefined) return t('errors.rejected', { reason: error.reason ?? '' });
      const details = Object.fromEntries(Object.entries(error.details).map(([k, v]) => [k, String(v)]));
      return t(key as Key, details);
    }
    default:
      return t('errors.unknown', { code: error.status ?? error.code });
  }
}
