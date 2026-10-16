#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Start the smoke-test container with the built packages and run the
# Playwright tests against it.
#
#   scripts/test-e2e.sh [playwright args...]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# A separate port so a container started by hand on 8080 is left alone.
PORT="${E2E_PORT:-18080}"

trap 'docker rm -f supacudy-smoke >/dev/null 2>&1 || true' EXIT

PORT="$PORT" "$ROOT/scripts/smoke-test.sh" --keep

cd "$ROOT/web"
npx playwright install chromium ${CI:+--with-deps} >/dev/null
E2E_BASE_URL="http://localhost:$PORT/supacudy/" npx playwright test "$@"
