#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for clients: the real effect of naming, blocking, rate
# limiting and counters on the emulated laptop. Sourced by run.sh.

LAPTOP=02:5c:00:00:00:11
IN_LAPTOP="ip netns exec laptop"

eventually "clients_list reports the laptop, NAS and phone online" \
	"ubus call supacudy clients_list | grep -c '\"online\": true' | awk '{ exit !(\$1 >= 3) }'"
check "the phone is reported as a 2.4 GHz Wi-Fi client" \
	"ubus call supacudy clients_list | tr -d '\n\t ' | grep -q '\"mac\":\"02:00:00:00:02:00\",[^}]*\"connection\":\"wifi\",\"band\":\"2g\"'"
check "WAN-side neighbours are not listed as clients" \
	"! ubus call supacudy clients_list | grep -q '10.250.2.'"
eventually "traffic counters grow for the laptop" \
	"ubus call supacudy clients_list | tr -d '\n\t ' | grep -Eq '\"mac\":\"$LAPTOP\"[^}]*\"tx_bytes\":[1-9]'"

check "renaming persists in UCI" \
	"ubus call supacudy client_set '{\"mac\":\"$LAPTOP\",\"name\":\"Office laptop\",\"type\":\"laptop\"}' &&
	 uci get supacudy.c_025c00000011.name | grep -qx 'Office laptop'"
check "an unknown device type is rejected" \
	"! ubus call supacudy client_set '{\"mac\":\"$LAPTOP\",\"name\":\"x\",\"type\":\"spaceship\"}'"
check "a malformed MAC is rejected" \
	"! ubus call supacudy client_block '{\"mac\":\"not-a-mac\",\"blocked\":true}'"

check "the laptop reaches the internet before blocking" "$IN_LAPTOP ping -c1 -W3 1.1.1.1"
check "blocking cuts the laptop off the internet" \
	"ubus call supacudy client_block '{\"mac\":\"$LAPTOP\",\"blocked\":true}' && ! $IN_LAPTOP ping -c1 -W3 1.1.1.1"
check "a blocked laptop still reaches the router" \
	"$IN_LAPTOP wget -q -O /dev/null -T 5 http://192.168.200.1/supacudy/"
check "blocking survives a policy reload" \
	"/etc/init.d/supacudy reload && ! $IN_LAPTOP ping -c1 -W3 1.1.1.1"
check "unblocking restores internet access" \
	"ubus call supacudy client_block '{\"mac\":\"$LAPTOP\",\"blocked\":false}' && $IN_LAPTOP ping -c1 -W3 1.1.1.1"

check "a download limit slows the laptop down" "
	dd if=/dev/urandom of=/www/emu-limit.bin bs=1k count=300 2>/dev/null
	ubus call supacudy client_limit '{\"mac\":\"$LAPTOP\",\"up\":0,\"down\":100}' >/dev/null
	t0=\$(date +%s); $IN_LAPTOP wget -q -O /dev/null -T 30 http://192.168.200.1/emu-limit.bin; t1=\$(date +%s)
	ubus call supacudy client_limit '{\"mac\":\"$LAPTOP\",\"up\":0,\"down\":0}' >/dev/null
	t2=\$(date +%s); $IN_LAPTOP wget -q -O /dev/null -T 30 http://192.168.200.1/emu-limit.bin; t3=\$(date +%s)
	rm -f /www/emu-limit.bin
	[ \$((t1 - t0)) -ge 2 ] && [ \$((t3 - t2)) -le 1 ]"
check "out-of-range limits are rejected" \
	"! ubus call supacudy client_limit '{\"mac\":\"$LAPTOP\",\"up\":-1,\"down\":0}'"

check "resetting the counters zeroes them" \
	"ubus call supacudy clients_reset_counters >/dev/null &&
	 ubus call supacudy clients_list | tr -d '\n\t ' | grep -Eq '\"mac\":\"$LAPTOP\"[^}]*\"tx_bytes\":[0-9]{1,4},'"
