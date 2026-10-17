// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// After a reboot, factory reset or upgrade the app shows a waiting screen
// instead of pages that can only fail until the router is back.

export type RestartKind = 'reboot' | 'reset' | 'upgrade';

const state = $state({ kind: null as RestartKind | null });

export function restarting(): RestartKind | null {
  return state.kind;
}

export function beginRestart(kind: RestartKind): void {
  state.kind = kind;
}

export function endRestart(): void {
  state.kind = null;
}
