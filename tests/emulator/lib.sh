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

# Without hardware acceleration (an x86 or arm64 host emulating the VM
# instruction by instruction) everything is several times slower: waits are
# EMU_WAIT_SCALE times longer, ubus calls get the same longer timeout, and a
# failed check is tried again a few times before it counts.
if [ -z "${EMU_WAIT_SCALE:-}" ]; then
	EMU_WAIT_SCALE=1
	[ "$("$EMU" accel)" = tcg ] && EMU_WAIT_SCALE=10
fi
UBUS_SLOW=""
[ "$EMU_WAIT_SCALE" -gt 1 ] && UBUS_SLOW="ubus() { command ubus -t $((30 * EMU_WAIT_SCALE)) \"\$@\"; }; "

# Keepalives end a session whose connection died while the VM's network
# restarted, instead of waiting forever.
# ssh joins its arguments into one command line, so the ubus wrapper goes first.
vm() {
	"$EMU" ssh -o BatchMode=yes -o ConnectTimeout=$((10 * EMU_WAIT_SCALE)) -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
		"$UBUS_SLOW" "$@"
}

# Runs a check inside the VM, retrying for up to 60 s (times EMU_WAIT_SCALE):
# radios, DHCP and service reloads settle asynchronously.
eventually() {
	local desc="$1" cmd="$2"
	for _ in $(seq $((30 * EMU_WAIT_SCALE))); do
		if vm "$cmd" >/dev/null 2>&1; then
			ok "$desc"
			return
		fi
		sleep 2
	done
	not_ok "$desc"
	vm "$cmd" 2>&1 | sed 's/^/    | /' || true
}

# For checks that count the product's own probes (1 s pings, 2 s DHCP tries)
# or measure CPU time: emulated without acceleration they cannot pass
# reliably, so there they are reported as skipped, with the suite's
# TIMED_REASON. The pre-push hook runs them on HVF or KVM.
#   timed check|eventually "description" "command"
timed() {
	if [ "$EMU_WAIT_SCALE" -gt 1 ]; then
		echo "ok - $2 # SKIP without hardware acceleration: ${TIMED_REASON:-depends on real-time behaviour}"
	else
		"$@"
	fi
}

check() {
	local desc="$1" cmd="$2"
	for _ in $(seq $((EMU_WAIT_SCALE > 1 ? 3 : 1))); do
		if vm "$cmd" >/dev/null 2>&1; then ok "$desc"; return; fi
		[ "$EMU_WAIT_SCALE" = 1 ] || sleep $((2 * EMU_WAIT_SCALE))
	done
	not_ok "$desc"
	vm "$cmd" 2>&1 | sed 's/^/    | /' || true
}
