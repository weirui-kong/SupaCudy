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

echo "==> packages in ${OUT#"$ROOT"/}/"
ls -1 "$OUT"
