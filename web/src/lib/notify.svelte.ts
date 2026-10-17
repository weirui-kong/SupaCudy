// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// Feedback for every change, per the product rules: "Applying" while the
// request runs, then success or a failure that says why.

import { errorMessage } from './errors';
import { t } from './i18n/index.svelte';

export type NoticeKind = 'applying' | 'success' | 'error';

export interface Notice {
  id: number;
  kind: NoticeKind;
  message: string;
}

const SUCCESS_MS = 3000;
const ERROR_MS = 8000;

const state = $state({ notices: [] as Notice[] });
let nextId = 0;

export function notices(): readonly Notice[] {
  return state.notices;
}

export function dismiss(id: number): void {
  state.notices = state.notices.filter((n) => n.id !== id);
}

function show(kind: NoticeKind, message: string, timeout?: number): number {
  const id = ++nextId;
  state.notices = [...state.notices.filter((n) => n.kind !== 'applying'), { id, kind, message }];
  if (timeout) setTimeout(() => dismiss(id), timeout);
  return id;
}

// null means it failed; the user has already been told why.
export async function apply<T>(change: () => Promise<T>, success: string = t('common.applied')): Promise<T | null> {
  const pending = show('applying', t('common.applying'));
  try {
    const result = await change();
    dismiss(pending);
    show('success', success, SUCCESS_MS);
    return result;
  } catch (err) {
    dismiss(pending);
    show('error', errorMessage(err), ERROR_MS);
    return null;
  }
}
