#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build a firmware image with the official OpenWrt ImageBuilder (in Docker),
# from the packages in out/packages/ plus the official package feeds.
#
#   scripts/build-image.sh <profile>      e.g. cudy-tr3000-256mb-v1 (see profiles/)
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
# shellcheck source=profiles/cudy-tr3000-256mb-v1.conf # the profile is picked at run time
. "$CONF"

# A profile may build for another target (the emulator) and add a file overlay.
TARGET="${TARGET:-$OPENWRT_TARGET}"
SUBTARGET="${SUBTARGET:-$OPENWRT_SUBTARGET}"
FILES_DIR="${FILES:+$ROOT/$FILES}"

IMAGE="openwrt/imagebuilder:${TARGET}-${SUBTARGET}-${OPENWRT_VERSION}"
PKG_DIR="$ROOT/out/packages"
OUT="$ROOT/out/images/$NAME"

if ! ls "$PKG_DIR"/*.ipk >/dev/null 2>&1; then
	echo "No packages in out/packages/. Run scripts/build-packages.sh first." >&2
	exit 1
fi

# Skip the slow ImageBuilder run when nothing that goes into the image has
# changed. FORCE=1 rebuilds anyway.
STAMP="$OUT/.inputs.sha256"
inputs_hash() {
	(
		cd "$ROOT"
		{
			find out/packages -name '*.ipk' -print0
			find profiles/common.conf "profiles/$NAME.conf" config/openwrt.env scripts/build-image.sh -print0
			if [ -n "$FILES_DIR" ]; then find "$FILES_DIR" \( -type f -o -type l \) -print0; fi
		} | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1
	)
}
HASH="$(inputs_hash)"
if [ -z "${FORCE:-}" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$HASH" ]; then
	echo "==> image is up to date (inputs unchanged), skipping the ImageBuilder"
	ls -1 "$OUT"
	exit 0
fi

# Downloaded official packages are kept between runs in a Docker volume.
# A host bind mount stalled opkg and gzip under amd64 emulation on macOS.
CACHE_VOLUME="supacudy-imagebuilder-dl-${TARGET}-${SUBTARGET}-${OPENWRT_VERSION}"
# A new volume belongs to root, but the ImageBuilder runs unprivileged.
docker run --rm --platform linux/amd64 --user 0 -v "$CACHE_VOLUME:/dl" "$IMAGE" chmod a+rwx /dl

rm -rf "$OUT"
mkdir -p "$OUT"
# The container runs as an unprivileged user with a different uid.
chmod a+rwx "$OUT"

PACKAGES="$(echo "$COMMON_PACKAGES $DEVICE_PACKAGES" | xargs)"

echo "==> $IMAGE, profile $PROFILE, mirror $OPENWRT_MIRROR"
echo "==> packages: $PACKAGES"

FILES_MOUNT=()
[ -n "$FILES_DIR" ] && FILES_MOUNT=(-v "$FILES_DIR:/overlay:ro")

# The download step occasionally stalls on slow mirrors. A timeout plus one
# retry keeps runs from hanging.
build() {
	docker run --rm --platform linux/amd64 \
		-v "$PKG_DIR:/supacudy:ro" \
		-v "$OUT:/out" \
		-v "$CACHE_VOLUME:/builder/dl" \
		${FILES_MOUNT[@]+"${FILES_MOUNT[@]}"} \
		-e PROFILE="$PROFILE" \
		-e PACKAGES="$PACKAGES" \
		-e OVERLAY="${FILES_DIR:+1}" \
		-e MIRROR="$OPENWRT_MIRROR" \
		-e ROOTFS_PARTSIZE="${ROOTFS_PARTSIZE:-}" \
		"$IMAGE" bash -euc '
			# Some image tags ship only a setup script that downloads the ImageBuilder.
			[ -f Makefile ] || ./setup.sh
			cp /supacudy/*.ipk packages/
			sed -i "s#https://downloads.openwrt.org#${MIRROR%/}#" repositories.conf
			if [ -n "$ROOTFS_PARTSIZE" ]; then
				sed -i "s/^CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE/" .config
			fi
			timeout 1200 make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" \
				${OVERLAY:+FILES=/overlay} EXTRA_IMAGE_NAME=supacudy BIN_DIR=/out
		'
}

if ! build; then
	echo "==> ImageBuilder failed or timed out; retrying once" >&2
	build
fi

echo "$HASH" > "$STAMP"
echo "==> images in ${OUT#"$ROOT"/}/"
ls -1 "$OUT"
