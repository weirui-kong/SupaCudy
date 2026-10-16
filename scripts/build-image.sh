#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build a firmware image with the official OpenWrt ImageBuilder (in Docker),
# from the packages in out/packages/ plus the official package feeds.
#
#   scripts/build-image.sh <profile>      e.g. cudy-tr3000-v1 (see profiles/)
#
# Output: out/images/<profile>/

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"
CONF="$ROOT/profiles/$NAME.conf"

if [ -z "$NAME" ] || [ "$NAME" = common ] || [ ! -f "$CONF" ]; then
	echo "usage: $0 <profile>" >&2
	echo "profiles:" >&2
	for f in "$ROOT"/profiles/*.conf; do
		p="$(basename "$f" .conf)"
		[ "$p" = common ] || echo "  $p" >&2
	done
	exit 1
fi

. "$ROOT/config/openwrt.env"
. "$ROOT/profiles/common.conf"
# shellcheck source=profiles/cudy-tr3000-v1.conf # the profile is picked at run time
. "$CONF"

IMAGE="openwrt/imagebuilder:${OPENWRT_TARGET}-${OPENWRT_SUBTARGET}-${OPENWRT_VERSION}"
PKG_DIR="$ROOT/out/packages"
OUT="$ROOT/out/images/$NAME"

if ! ls "$PKG_DIR"/*.ipk >/dev/null 2>&1; then
	echo "No packages in out/packages/. Run scripts/build-packages.sh first." >&2
	exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
# The container runs as an unprivileged user with a different uid.
chmod a+rwx "$OUT"

PACKAGES="$(echo "$COMMON_PACKAGES $DEVICE_PACKAGES" | xargs)"

echo "==> $IMAGE, profile $PROFILE"
echo "==> packages: $PACKAGES"

docker run --rm --platform linux/amd64 \
	-v "$PKG_DIR:/supacudy:ro" \
	-v "$OUT:/out" \
	-e PROFILE="$PROFILE" \
	-e PACKAGES="$PACKAGES" \
	"$IMAGE" bash -euc '
		# Some image tags ship only a setup script that downloads the ImageBuilder.
		[ -f Makefile ] || ./setup.sh
		cp /supacudy/*.ipk packages/
		make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" \
			EXTRA_IMAGE_NAME=supacudy BIN_DIR=/out
	'

echo "==> images in ${OUT#"$ROOT"/}/"
ls -1 "$OUT"
