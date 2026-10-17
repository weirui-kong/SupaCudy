#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Sourced by the emulator test scripts.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EMU="$ROOT/scripts/emulator.sh"

# A separate instance from the one kept open for manual checks.
export EMU_STATE="${EMU_STATE:-$ROOT/out/emulator-test}"
export EMU_HTTP_PORT="${EMU_HTTP_PORT:-18088}"
export EMU_SSH_PORT="${EMU_SSH_PORT:-12222}"
export EMU_ADGUARD_PORT="${EMU_ADGUARD_PORT:-13000}"

# shellcheck disable=SC2034 # read by run.sh, which sources this file
FAILED=0
ok()     { echo "ok - $*"; }
# shellcheck disable=SC2034 # read by run.sh
not_ok() { echo "not ok - $*"; FAILED=1; }

# Keepalives end a session whose connection died while the VM's network
# restarted, instead of waiting forever.
vm() { "$EMU" ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "$@"; }

# Runs a check inside the VM, retrying for up to 60 s: radios, DHCP and
# service reloads settle asynchronously.
eventually() {
	local desc="$1" cmd="$2"
	for _ in $(seq 30); do
		if vm "$cmd" >/dev/null 2>&1; then
			ok "$desc"
			return
		fi
		sleep 2
	done
	not_ok "$desc"
	vm "$cmd" 2>&1 | sed 's/^/    | /' || true
}

check() {
	local desc="$1" cmd="$2"
	if vm "$cmd" >/dev/null 2>&1; then ok "$desc"; else not_ok "$desc"; vm "$cmd" 2>&1 | sed 's/^/    | /' || true; fi
}
