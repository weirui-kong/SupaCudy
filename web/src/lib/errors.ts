// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { ApiError } from './api';
import { t } from './i18n/index.svelte';

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === 'network') return t('errors.network');
    if (error.code === 'denied') return t('errors.denied');
    return t('errors.unknown', { code: error.status ?? error.code });
  }
  return t('errors.unknown', { code: 'client' });
}
