// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Key } from './i18n/index.svelte';

const NAMES: Record<string, Key> = {
  wan: 'internet.ethernet',
  wwan: 'internet.repeater',
  tethering: 'tethering.title',
};

/** The label of the interface carrying the default route, if it is one of ours. */
export function uplinkName(active: string | null | undefined): Key | null {
  return active ? (NAMES[active] ?? null) : null;
}
