#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Run SupaCudy in a QEMU virtual machine with an emulated network around it
# (see docs/emulator.md).
#
#   scripts/emulator.sh build      build packages and the emulator image
#   scripts/emulator.sh image      rebuild only the image from out/packages
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

STATE="$ROOT/out/emulator"
DISK="$STATE/disk.img"
PIDFILE="$STATE/qemu.pid"
CONSOLE="$STATE/console.log"
IMAGE_GZ="$ROOT/out/images/emulator/openwrt-${OPENWRT_VERSION}-supacudy-armsr-armv8-generic-ext4-combined-efi.img.gz"

KEY="$STATE/id_ed25519"
HTTP_PORT="${EMU_HTTP_PORT:-8088}"
SSH_PORT="${EMU_SSH_PORT:-2222}"
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
	mkdir -p "$STATE"
	[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C supacudy-emulator -f "$KEY"
	rm -rf "$STATE/overlay"
	cp -RP "$ROOT/emulator/files" "$STATE/overlay"
	mkdir -p "$STATE/overlay/etc/dropbear"
	cp "$KEY.pub" "$STATE/overlay/etc/dropbear/authorized_keys"
	chmod 600 "$STATE/overlay/etc/dropbear/authorized_keys"
	"$ROOT/scripts/build-image.sh" emulator
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

	local accel
	read -r -a accel <<< "$(accelerator)"

	: > "$CONSOLE"
	qemu-system-aarch64 \
		-M virt "${accel[@]}" -smp 2 -m 512 \
		-bios "$(firmware)" \
		-drive "file=$DISK,format=raw,if=virtio" \
		-netdev "user,id=wan,net=10.250.2.0/24" \
		-device virtio-net-pci,netdev=wan,mac=52:54:00:fa:02:01 \
		-netdev "user,id=mgmt,net=10.250.3.0/24,restrict=on,hostfwd=tcp:127.0.0.1:$HTTP_PORT-10.250.3.15:80,hostfwd=tcp:127.0.0.1:$SSH_PORT-10.250.3.15:22" \
		-device virtio-net-pci,netdev=mgmt,mac=52:54:00:fa:03:01 \
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

cmd_ssh() {
	# Throwaway VM with a test password: skip host-key bookkeeping.
	exec ssh -q -p "$SSH_PORT" -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR root@127.0.0.1 "$@"
}

case "${1:-}" in
	build) cmd_build ;;
	image) cmd_image ;;
	start) cmd_start "${2:-}" ;;
	stop) cmd_stop ;;
	status) cmd_status ;;
	ssh) shift; cmd_ssh "$@" ;;
	console) exec tail -f "$CONSOLE" ;;
	*) sed -n '5,14p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1 ;;
esac
