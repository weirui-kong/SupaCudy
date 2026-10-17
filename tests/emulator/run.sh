#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests: boot a fresh VM (separate from the one kept open for
# manual checks) and run every feature check against the real system.
#
#   tests/emulator/run.sh            boot, check, stop
#   tests/emulator/run.sh --keep     leave the test VM running

set -euo pipefail

# shellcheck source=tests/emulator/lib.sh
. "$(dirname "$0")/lib.sh"

KEEP="${1:-}"

"$EMU" stop >/dev/null
"$EMU" start --fresh
[ "$KEEP" = --keep ] || trap '"$EMU" stop >/dev/null' EXIT

eventually "ssh login with the emulator key" "true"
# The image may predate the working tree's packages; test what is checked out.
"$EMU" deploy >/dev/null

for suite in scenario clients lan wireless internet tethering ports dns adguard vpn ovpn tailscale ddns schedule rescue netmode system; do
	echo "# $suite"
	# shellcheck source=/dev/null # each suite is a list of checks
	. "$(dirname "$0")/$suite.sh"
done

if [ "$FAILED" = 0 ]; then
	echo "emulator tests: PASS"
else
	echo "emulator tests: FAIL" >&2
	exit 1
fi
