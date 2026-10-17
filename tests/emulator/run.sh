#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests: boot fresh VMs (separate from the one kept open for
# manual checks) and run the feature checks against the real system.
#
#   tests/emulator/run.sh                    every suite, split over two VMs
#   tests/emulator/run.sh [--keep] SUITE...  only these suites, on one VM
#
# --keep leaves the VMs running afterwards.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Two groups of about the same length; system reboots, so it goes last.
# Suites that build on each other (vpn, ovpn) stay in one group.
GROUP_A=(scenario clients lan wireless internet tethering ports dns tailscale ddns schedule netmode)
GROUP_B=(scenario adguard vpn ovpn rescue system)

run_suites() {
	# shellcheck source=tests/emulator/lib.sh
	. "$HERE/lib.sh"
	local keep="$1"
	shift
	"$EMU" stop >/dev/null
	"$EMU" start --fresh
	[ "$keep" = --keep ] || trap '"$EMU" stop >/dev/null' EXIT

	eventually "ssh login with the emulator key" "true"
	# The image may predate the working tree's packages; test what is checked out.
	"$EMU" deploy >/dev/null

	local suite started
	for suite in "$@"; do
		echo "# $suite"
		started=$SECONDS
		# shellcheck source=/dev/null # each suite is a list of checks
		. "$HERE/$suite.sh"
		echo "# $suite took $((SECONDS - started))s"
	done
	[ "$FAILED" = 0 ]
}

prefixed() {
	local tag="$1" line
	while IFS= read -r line; do
		printf '[%s] %s\n' "$tag" "$line"
	done
}

KEEP=""
if [ "${1:-}" = --keep ]; then
	KEEP=--keep
	shift
fi

if [ $# -gt 0 ]; then
	if (run_suites "$KEEP" "$@"); then
		echo "emulator tests: PASS"
		exit 0
	fi
	echo "emulator tests: FAIL" >&2
	exit 1
fi

STATUS="$(mktemp -d)"
trap 'rm -rf "$STATUS"' EXIT
(
	if (run_suites "$KEEP" "${GROUP_A[@]}") 2>&1 | prefixed a; then
		touch "$STATUS/a"
	fi
) &
# The second VM gets its own disk and ports.
(
	export EMU_STATE="$HERE/../../out/emulator-test2"
	export EMU_HTTP_PORT=18089 EMU_SSH_PORT=12223 EMU_ADGUARD_PORT=13001
	if (run_suites "$KEEP" "${GROUP_B[@]}") 2>&1 | prefixed b; then
		touch "$STATUS/b"
	fi
) &
wait

if [ -e "$STATUS/a" ] && [ -e "$STATUS/b" ]; then
	echo "emulator tests: PASS"
else
	echo "emulator tests: FAIL" >&2
	exit 1
fi
