#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
#   tests/lint/check-shell.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if ! command -v shellcheck >/dev/null; then
	echo "shellcheck is not installed (macOS: brew install shellcheck, Debian/Ubuntu: apt install shellcheck)" >&2
	exit 1
fi

host_scripts=(scripts/*.sh tests/*/*.sh .githooks/*)

# Anything under packages/*/files/ runs on the router under BusyBox ash.
device_scripts=()
while IFS= read -r f; do
	head -1 "$f" | grep -q '^#!/bin/sh' && device_scripts+=("$f")
done < <(find packages -path '*/files/*' -type f)

echo "==> host scripts (bash): ${#host_scripts[@]}"
shellcheck -x "${host_scripts[@]}"

echo "==> device scripts (sh): ${#device_scripts[@]}"
if [ "${#device_scripts[@]}" -gt 0 ]; then
	shellcheck -s sh "${device_scripts[@]}"
fi

echo "lint tests: PASS"
