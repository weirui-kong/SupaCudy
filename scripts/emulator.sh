#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Run SupaCudy in a QEMU virtual machine with an emulated network around it
# (see docs/emulator.md).
#
#   scripts/emulator.sh build      build packages and the emulator image
#   scripts/emulator.sh image      rebuild only the image from out/packages
#                                  (--check: exit 0 if it is up to date)
#   scripts/emulator.sh deploy     push the current code into the running VM
#   scripts/emulator.sh start      boot the VM (add --fresh to reset its disk)
#   scripts/emulator.sh stop
#   scripts/emulator.sh status
#   scripts/emulator.sh ssh [cmd]  shell into the VM
#   scripts/emulator.sh console    follow the serial console log
#
# QEMU user-mode networking only: no host interfaces, routes or system
# settings are touched, and the forwarded ports listen on 127.0.0.1 only.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/config/openwrt.env"

# EMU_STATE, EMU_HTTP_PORT, EMU_SSH_PORT and EMU_ADGUARD_PORT allow a second, independent VM
# (the emulator tests use one so a VM kept open for manual checks is left alone).
STATE="${EMU_STATE:-$ROOT/out/emulator}"
DISK="$STATE/disk.img"
PIDFILE="$STATE/qemu.pid"
CONSOLE="$STATE/console.log"
IMAGE_GZ="$ROOT/out/images/emulator/openwrt-${OPENWRT_VERSION}-supacudy-armsr-armv8-generic-ext4-combined-efi.img.gz"

# Shared by all instances: the public half is baked into the image.
KEY="$ROOT/out/emulator/id_ed25519"
HTTP_PORT="${EMU_HTTP_PORT:-8088}"
SSH_PORT="${EMU_SSH_PORT:-2222}"
# AdGuard Home's own page, linked from SupaCudy on the same host name.
ADGUARD_PORT="${EMU_ADGUARD_PORT:-3000}"
URL="http://127.0.0.1:$HTTP_PORT/supacudy/"

running() {
	[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

firmware() {
	local prefix
	for prefix in "$(brew --prefix 2>/dev/null || true)/share/qemu" /usr/share/qemu /usr/share/AAVMF /usr/share/qemu-efi-aarch64; do
		for name in edk2-aarch64-code.fd AAVMF_CODE.fd QEMU_EFI.fd; do
			[ -f "$prefix/$name" ] && { echo "$prefix/$name"; return; }
		done
	done
	echo "No aarch64 UEFI firmware found (install QEMU: brew install qemu)." >&2
	exit 1
}

accelerator() {
	case "$(uname -s)-$(uname -m)" in
		Darwin-arm64) echo "-accel hvf -cpu host" ;;
		Linux-aarch64) [ -w /dev/kvm ] && echo "-accel kvm -cpu host" || echo "-accel tcg -cpu cortex-a72" ;;
		*) echo "-accel tcg -cpu cortex-a72" ;;
	esac
}

# The image overlay is emulator/files plus a throwaway SSH key, so scripts
# and tests can log in without the password.
cmd_build() {
	"$ROOT/scripts/build-packages.sh"
	cmd_image
}

cmd_image() {
	mkdir -p "$ROOT/out/emulator"
	[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C supacudy-emulator -f "$KEY"
	local overlay="$ROOT/out/emulator/overlay"
	rm -rf "$overlay"
	cp -RP "$ROOT/emulator/files" "$overlay"
	mkdir -p "$overlay/etc/dropbear"
	cp "$KEY.pub" "$overlay/etc/dropbear/authorized_keys"
	chmod 600 "$overlay/etc/dropbear/authorized_keys"
	"$ROOT/scripts/build-image.sh" ${1:+"$1"} emulator
}

cmd_start() {
	if running; then
		echo "Already running: $URL"
		return
	fi
	command -v qemu-system-aarch64 >/dev/null || { echo "QEMU is not installed (brew install qemu)." >&2; exit 1; }
	[ -f "$IMAGE_GZ" ] || { echo "No emulator image. Run: scripts/emulator.sh build" >&2; exit 1; }

	mkdir -p "$STATE"
	if [ "${1:-}" = --fresh ] || [ ! -f "$DISK" ] || [ "$IMAGE_GZ" -nt "$DISK" ]; then
		echo "==> preparing a fresh disk from the image"
		gunzip -c "$IMAGE_GZ" > "$DISK" || true  # gunzip warns about trailing padding
	fi

	# usb-net plays a phone sharing its connection over USB (RNDIS), on an
	# isolated link with its own DHCP: see docs/emulator.md.
	local accel
	read -r -a accel <<< "$(accelerator)"

	: > "$CONSOLE"
	qemu-system-aarch64 \
		-M virt "${accel[@]}" -smp 2 -m 512 \
		-bios "$(firmware)" \
		-drive "file=$DISK,format=raw,if=virtio" \
		-netdev "user,id=wan,net=10.250.2.0/24" \
		-device virtio-net-pci,netdev=wan,mac=52:54:00:fa:02:01 \
		-netdev "user,id=mgmt,net=10.250.3.0/24,restrict=on,hostfwd=tcp:127.0.0.1:$HTTP_PORT-10.250.3.15:80,hostfwd=tcp:127.0.0.1:$SSH_PORT-10.250.3.15:22,hostfwd=tcp:127.0.0.1:$ADGUARD_PORT-10.250.3.15:3000" \
		-device virtio-net-pci,netdev=mgmt,mac=52:54:00:fa:03:01 \
		-device qemu-xhci \
		-netdev "user,id=phone,net=10.250.42.0/24" \
		-device usb-net,netdev=phone \
		-display none -serial "file:$CONSOLE" \
		-daemonize -pidfile "$PIDFILE"

	echo "==> waiting for the web UI"
	# Generous: without hardware acceleration (CI) the boot takes minutes.
	for _ in $(seq 300); do
		if curl -fsS -o /dev/null "$URL" 2>/dev/null; then
			echo "Up: $URL  (root / supacudy-test)"
			echo "SSH: scripts/emulator.sh ssh"
			return
		fi
		sleep 1
	done
	echo "The VM did not come up in time; see $CONSOLE" >&2
	exit 1
}

cmd_stop() {
	if running; then
		kill "$(cat "$PIDFILE")"
		echo "Stopped."
	else
		echo "Not running."
	fi
	rm -f "$PIDFILE"
}

cmd_status() {
	if running; then echo "Running: $URL"; else echo "Not running."; fi
}

# Hot deploy: builds the UI and copies package files into the running VM,
# keeping its state. Config files are only installed when missing, like
# opkg does for conffiles. New package dependencies need `build` instead.
cmd_deploy() {
	running || { echo "Not running. Start it with: scripts/emulator.sh start" >&2; exit 1; }

	local stage
	stage="$(mktemp -d)"
	trap 'rm -rf "$stage"' RETURN
	cp -RP "$ROOT"/packages/supacudy-base/files/. "$stage/"
	cp -RP "$ROOT"/packages/supacudy-rpcd/files/. "$stage/"
	cp -RP "$ROOT"/packages/supacudy-ui/files/. "$stage/"
	# Built straight into the staging area: scripts/test.sh runs the web
	# e2e tests from packages/supacudy-ui/htdocs at the same time.
	(cd "$ROOT/web" && npx vite build --outDir "$stage/www/supacudy" --emptyOutDir >/dev/null)
	mkdir -p "$stage/usr/share/supacudy-deploy"
	mv "$stage/etc/config" "$stage/usr/share/supacudy-deploy/config"
	echo "dev-$(date +%H%M%S)" > "$stage/etc/supacudy_version"

	# shellcheck disable=SC2016 # expanded by the VM's shell, not here
	# Top-level entries are listed so the archive carries no "./" entry,
	# which would apply the temporary directory's mode to the VM's /.
	(cd "$stage" && shopt -s dotglob && COPYFILE_DISABLE=1 tar --uid 0 --gid 0 -cf - -- *) |
		cmd_ssh_quiet 'rm -rf /www/supacudy/assets && tar -C / -xf - &&
			for f in /usr/share/supacudy-deploy/config/*; do
				[ -e "/etc/config/${f##*/}" ] || cp "$f" /etc/config/
			done
			rm -rf /usr/share/supacudy-deploy
			# As on boot: each first-boot script runs once and is removed.
			for f in /etc/uci-defaults/*; do
				[ -f "$f" ] && ( . "$f" ) && rm -f "$f"
			done
			/etc/init.d/uhttpd restart
			for svc in /etc/init.d/supacudy*; do
				[ "$svc" = /etc/init.d/supacudy-emulator ] && continue
				$svc enable
				$svc restart
			done
			# reload re-reads plugins and modules but keeps login sessions.
			/etc/init.d/rpcd reload
			for i in 1 2 3 4 5 6 7 8 9 10; do
				ubus call supacudy info >/dev/null 2>&1 && break
				sleep 1
			done'
	echo "Deployed: $URL"
}

cmd_ssh_quiet() {
	ssh -q -p "$SSH_PORT" -i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@127.0.0.1 "$@"
}

cmd_ssh() {
	# Throwaway VM with a test password: skip host-key bookkeeping.
	exec ssh -q -p "$SSH_PORT" -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR root@127.0.0.1 "$@"
}

case "${1:-}" in
	build) cmd_build ;;
	image) cmd_image "${2:-}" ;;
	deploy) cmd_deploy ;;
	start) cmd_start "${2:-}" ;;
	stop) cmd_stop ;;
	status) cmd_status ;;
	ssh) shift; cmd_ssh "$@" ;;
	console) exec tail -f "$CONSOLE" ;;
	*) sed -n '5,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1 ;;
esac
