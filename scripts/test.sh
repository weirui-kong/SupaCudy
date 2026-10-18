#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Run every automated test category. All of them must pass before a push
# (the pre-push hook in .githooks/ runs this script).
#
#   scripts/test.sh
#
# EMULATOR_TESTS_ELSEWHERE=1 builds the emulator image but leaves its tests
# to another job: on CI they run on an arm64 runner (see .github/workflows).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGS="$ROOT/out/test-logs"
RESULTS="$LOGS/results"
rm -rf "$RESULTS"
mkdir -p "$RESULTS"

CATEGORIES=(lint web-deps web-unit web-build build-packages build api web-e2e emulator-image emulator)

# Results go to files rather than variables because the last categories run
# in background subshells.
run() {
	local category="$1" log="$LOGS/$1.log"
	shift
	echo "==> [$category] started"
	local started=$SECONDS
	if "$@" >"$log" 2>&1; then
		echo "PASS  $category  ($((SECONDS - started))s)" > "$RESULTS/$category"
		echo "==> [$category] passed in $((SECONDS - started))s"
	else
		echo "FAIL  $category  ($((SECONDS - started))s, log: ${log#"$ROOT"/})" > "$RESULTS/$category"
		echo "==> [$category] FAILED, last lines of ${log#"$ROOT"/}:"
		tail -40 "$log" | sed "s/^/    [$category] | /"
	fi
}

passed() {
	grep -q '^PASS' "$RESULTS/$1" 2>/dev/null
}

skip() {
	echo "SKIP  $1  ($2)" > "$RESULTS/$1"
}

web_deps() {
	cd "$ROOT/web" && { [ -d node_modules ] || npm ci --no-audit --no-fund; }
}

# The emulator image only needs packages when it has to be rebuilt; the
# tests deploy the working tree's files into the VM anyway.
emulator_chain() {
	if ! "$ROOT/scripts/emulator.sh" image --check >/dev/null 2>&1; then
		while [ ! -f "$RESULTS/build-packages" ]; do sleep 2; done
		if ! passed build-packages; then
			skip emulator-image "packages did not build"
			skip emulator "packages did not build"
			return
		fi
	fi
	run emulator-image "$ROOT/scripts/emulator.sh" image
	if [ -n "${EMULATOR_TESTS_ELSEWHERE:-}" ]; then
		skip emulator "run in another CI job"
	elif passed emulator-image; then
		run emulator "$ROOT/tests/emulator/run.sh"
	else
		skip emulator "emulator image did not build"
	fi
}

package_chain() {
	WEB_ALREADY_BUILT=1 run build-packages "$ROOT/scripts/build-packages.sh"
	if passed build-packages; then
		run build "$ROOT/tests/build/check-packages.sh"
		SMOKE_NAME=supacudy-api PORT=18081 run api "$ROOT/scripts/smoke-test.sh"
	else
		skip build "packages did not build"
		skip api "packages did not build"
	fi
}

START=$SECONDS

run lint "$ROOT/tests/lint/check-shell.sh"
run web-deps web_deps
run web-unit npm --prefix "$ROOT/web" test
run web-build npm --prefix "$ROOT/web" run build

# Independent of each other: separate containers, ports, VMs and logs.
if passed web-build; then
	run web-e2e "$ROOT/scripts/test-e2e.sh" &
else
	skip web-e2e "the web UI did not build"
fi
package_chain &
emulator_chain &
wait

echo
echo "Summary ($((SECONDS - START))s):"
FAILED=0
for category in "${CATEGORIES[@]}"; do
	if [ -f "$RESULTS/$category" ]; then
		sed 's/^/  /' "$RESULTS/$category"
		if grep -q '^FAIL' "$RESULTS/$category"; then FAILED=1; fi
	else
		echo "  FAIL  $category  (did not report a result)"
		FAILED=1
	fi
done

if [ "$FAILED" = 0 ]; then
	echo "All tests passed."
else
	echo "Some tests failed." >&2
	exit 1
fi
