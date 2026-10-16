#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Push the SupaCudy files straight onto a running OpenWrt router, without
# building or flashing an image. Meant for the edit -> reload loop.
#
#   scripts/deploy-dev.sh [user@host]      (default: root@192.168.1.1)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-root@192.168.1.1}"

# Keep macOS from adding ._* resource-fork files to the tar streams.
export COPYFILE_DISABLE=1

# Files must land owned by root, not by the local user's uid.
if tar --version 2>/dev/null | grep -q bsdtar; then
	TAR_OWNER=(--uid 0 --gid 0)
else
	TAR_OWNER=(--owner=0 --group=0)
fi

# Stream the contents of a local directory into a directory on the router.
# tar over ssh works with dropbear, which has no sftp server (so plain scp
# often fails). The top-level entries are listed explicitly so the
# destination directory itself (e.g. /) keeps its permissions.
push() {
	local src="$1" dest="$2"
	echo "==> ${src#"$ROOT"/} -> $HOST:$dest"
	(cd "$src" && tar "${TAR_OWNER[@]}" -cf - $(ls -A)) |
		ssh "$HOST" "mkdir -p '$dest' && tar -C '$dest' -xf -"
}

push "$ROOT/packages/supacudy-base/files" /
push "$ROOT/packages/supacudy-rpcd/files" /
push "$ROOT/packages/supacudy-ui/htdocs" /www/supacudy

echo "==> restarting rpcd"
ssh "$HOST" 'echo dev > /etc/supacudy_version && /etc/init.d/rpcd restart'

echo "Done. Open http://${HOST#*@}/supacudy/"
