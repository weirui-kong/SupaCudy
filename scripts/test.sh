#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Run every automated test category. All of them must pass before a push
# (the pre-push hook in .githooks/ runs this script).
#
#   scripts/test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGS="$ROOT/out/test-logs"
mkdir -p "$LOGS"

RESULTS=()
FAILED=0

run() {
	local category="$1" log="$LOGS/$2.log"
	shift 2
	echo "==> [$category] $*"
	if "$@" >"$log" 2>&1; then
		RESULTS+=("PASS  $category")
	else
		RESULTS+=("FAIL  $category  (log: ${log#"$ROOT"/})")
		FAILED=1
		tail -40 "$log" | sed 's/^/    | /'
	fi
}

skip() {
	echo "==> [$1] skipped: $2"
	RESULTS+=("SKIP  $1  ($2)")
}

run lint lint "$ROOT/tests/lint/check-shell.sh"

web_deps() { (cd "$ROOT/web" && { [ -d node_modules ] || npm ci --no-audit --no-fund; }); }
run web-deps web-deps web_deps
run web-unit web-unit npm --prefix "$ROOT/web" test

# Every test category below needs freshly built packages.
run build-packages build-packages "$ROOT/scripts/build-packages.sh"

if [ "$FAILED" = 0 ]; then
	run build   build-tests "$ROOT/tests/build/check-packages.sh"
	run api     api-tests   "$ROOT/scripts/smoke-test.sh"
	run web-e2e web-e2e     "$ROOT/scripts/test-e2e.sh"
else
	skip build   "packages did not build"
	skip api     "packages did not build"
	skip web-e2e "packages did not build"
fi

echo
echo "Summary:"
printf '  %s\n' "${RESULTS[@]}"

if [ "$FAILED" = 0 ]; then
	echo "All tests passed."
else
	echo "Some tests failed." >&2
	exit 1
fi
