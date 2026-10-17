#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build every package under packages/ into an .ipk with the official
# OpenWrt SDK (in Docker).
#
#   scripts/build-packages.sh
#
# Output: out/packages/*.ipk

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/config/openwrt.env"

IMAGE="openwrt/sdk:${OPENWRT_TARGET}-${OPENWRT_SUBTARGET}-${OPENWRT_VERSION}"
OUT="$ROOT/out/packages"

PKGS=""
for dir in "$ROOT"/packages/*/; do
	PKGS+="$(basename "$dir") "
done

echo "==> building the web UI into packages/supacudy-ui/htdocs"
# scripts/test.sh builds it once up front because the e2e tests serve it
# while this runs.
if [ -z "${WEB_ALREADY_BUILT:-}" ]; then
	(cd "$ROOT/web" && { [ -d node_modules ] || npm ci --no-audit --no-fund; } && npm run build)
fi

# The SDK step is slow under amd64 emulation, so skip it when nothing that
# goes into the packages has changed. FORCE=1 rebuilds anyway.
STAMP="$OUT/.inputs.sha256"
inputs_hash() {
	(cd "$ROOT" && find packages config/openwrt.env scripts/build-packages.sh -type f -print0 |
		LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
}
HASH="$(inputs_hash)"
if [ -z "${FORCE:-}" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$HASH" ] &&
	ls "$OUT"/*.ipk >/dev/null 2>&1; then
	echo "==> packages are up to date (inputs unchanged), skipping the SDK"
	ls -1 "$OUT"
	exit 0
fi

rm -rf "$OUT"
mkdir -p "$OUT"
# The container runs as an unprivileged user with a different uid.
chmod a+rwx "$OUT"

echo "==> $IMAGE"
echo "==> packages: $PKGS"

docker run --rm --platform linux/amd64 \
	-v "$ROOT/packages:/feed:ro" \
	-v "$OUT:/out" \
	-e PKGS="$PKGS" \
	"$IMAGE" bash -euc '
		# Only our own feed: the packages are architecture independent and
		# need nothing compiled from the official feeds. The SDK then warns
		# that dependencies such as rpcd "do not exist"; that is expected,
		# the Depends: field of each .ipk is still written correctly.
		echo "src-link supacudy /feed" > feeds.conf
		./scripts/feeds update supacudy
		./scripts/feeds install -a -p supacudy

		for p in $PKGS; do
			echo "CONFIG_PACKAGE_$p=m" >> .config
		done
		make defconfig >/dev/null

		for p in $PKGS; do
			make "package/$p/compile" -j1
		done

		find bin/packages -name "*.ipk" -path "*/supacudy/*" -exec cp {} /out/ \;
	'

echo "$HASH" > "$STAMP"
echo "==> packages in ${OUT#"$ROOT"/}/"
ls -1 "$OUT"
