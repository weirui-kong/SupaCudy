// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { supacudy } from './core';

export type TailscaleState = 'NeedsLogin' | 'NeedsMachineAuth' | 'Starting' | 'Running' | 'Stopped' | 'NoState';

export interface TailscaleStatus {
  installed: boolean;
  enabled: boolean;
  share_lan: boolean;
  /** null while tailscaled does not answer. */
  state: TailscaleState | null;
  /** Where to sign in, while it waits for that. */
  login_url: string | null;
  addresses: string[];
  name: string | null;
  tailnet: string | null;
  /** The subnet offered to the tailnet when the LAN is shared. */
  lan: string | null;
}

export const getTailscale = () => supacudy<TailscaleStatus>('tailscale_get');
export const setTailscale = (enabled: boolean, share_lan: boolean) =>
  supacudy<{ applied: boolean }>('tailscale_set', { enabled, share_lan });
export const logoutTailscale = () => supacudy<{ applied: boolean }>('tailscale_logout');

// Only Tailscale's own sign-in pages are offered as links.
export function safeLoginUrl(url: string | null): string | null {
  return url && /^https:\/\/login\.tailscale\.com\/[!-~]*$/.test(url) ? url : null;
}
