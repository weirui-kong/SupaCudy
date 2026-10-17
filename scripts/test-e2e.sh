#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Run the Playwright UI tests against the built front-end and the mock
# router. Expects packages/supacudy-ui/htdocs to be built (build-packages.sh
# or `npm run build` in web/).
#
#   scripts/test-e2e.sh [playwright args...]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/web"
[ -f "$ROOT/packages/supacudy-ui/htdocs/index.html" ] || npm run build
npx playwright install chromium ${CI:+--with-deps} >/dev/null
npx playwright test "$@"
