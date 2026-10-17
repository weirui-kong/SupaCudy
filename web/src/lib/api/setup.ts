// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { call, supacudy } from './core';

export interface RescueState {
  /** The router could not be reached normally, so it opened a way in. */
  active: boolean;
  /** Extra address with its own DHCP, when nobody got one from the router. */
  address: string | null;
  /** Open network, when no Wi-Fi and no cable was available. */
  ssid: string | null;
  since: number | null;
}

export interface SetupStatus {
  setup_done: boolean;
  /** False on a fresh install, where root has no password yet. */
  password_set: boolean;
  /** Still the factory login root / supacudy; only reported before setup. */
  default_password: boolean;
  rescue: RescueState;
}

// Readable before logging in, so a fresh router can greet its owner.
export const getSetupStatus = () => call<SetupStatus>('supacudy', 'setup_status', {}, true);
export const completeSetup = () => supacudy<{ setup_done: boolean }>('setup_complete');
export const getRescue = () => supacudy<RescueState>('rescue_get');
