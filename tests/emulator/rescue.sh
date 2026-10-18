#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for rescue mode. The watcher is stopped and ticked by hand
# so the checks do not wait for its 30 s rhythm. Two cases: access point
# mode whose main router disappears (WAN link down), and no Wi-Fi network
# with no cable plugged in. Afterwards the saved settings must be exactly as
# before: rescue mode is runtime only. Sourced by run.sh.

TICK="ucode /usr/libexec/supacudy/rescue.uc"
STATE=/var/run/supacudy/rescue.json
LAPTOP="ip netns exec laptop"
PHONE="ip netns exec phone"
AP='{"mode":"ap","ipaddr":"10.250.2.50","netmask":"255.255.255.0","gateway":"10.250.2.2","dns":["10.250.2.3"]}'
ROUTER='{"mode":"router","ipaddr":"","netmask":"","gateway":"","dns":[]}'
# The bracket keeps pgrep from matching the shell running the check.
# The watcher counts DHCP probes with 2 s timeouts, which emulation without
# acceleration misses now and then.
# shellcheck disable=SC2034 # read by timed() in lib.sh
TIMED_REASON="counts the watcher's DHCP probes"
RENEW_LAPTOP="pid=\$(pgrep -f '[h]ostname:Work-Laptop'); kill -USR2 \$pid; sleep 1; kill -USR1 \$pid"

check "the watcher runs and is quiet while all is well" \
	"pgrep -f '[r]escue-watch' && /etc/init.d/supacudy-rescue stop && $TICK && grep -q '\"active\": *false' $STATE &&
	 ubus call supacudy setup_status | grep -q '\"active\": false'"
check "access point mode is set up" "ubus call supacudy netmode_set '$AP' | grep -q applied"
eventually "the main router answers DHCP" "uci -q get supacudy.netmode.mode | grep -qx ap && $TICK && grep -q '\"dhcp_misses\": *0' $STATE"
check "the uci configuration is saved for comparison" "uci export network > /tmp/net.before; uci export dhcp > /tmp/dhcp.before; uci export wireless > /tmp/wifi.before"
timed check "the main router disappears" "ip link set eth0 down"
timed check "one missed probe is not enough" "$TICK && ! ip -4 addr show br-lan | grep -q 192.168.200.1"
timed check "the second one starts rescue DHCP" \
	"$TICK && ip -4 addr show br-lan | grep -q 'inet 192.168.200.1/24' && pgrep -f '[r]escue-dnsmasq.pid' &&
	 ubus call supacudy rescue_get | grep -q '\"address\": \"192.168.200.1\"'"
timed eventually "the laptop gets a rescue address and opens the admin page" \
	"$RENEW_LAPTOP; sleep 3; $LAPTOP ip -4 addr show eth0 | grep -q 'inet 192.168.200.' &&
	 $LAPTOP uclient-fetch -q -O - http://192.168.200.1/supacudy/ | grep -q '<title>SupaCudy'"
timed check "the main router comes back" "ip link set eth0 up && sleep 5"
timed check "rescue mode ends after two good checks" \
	"$TICK && $TICK && grep -q '\"active\": *false' $STATE && ! ip -4 addr show br-lan | grep -q 192.168.200.1 &&
	 ! pgrep -f '[r]escue-dnsmasq.pid'"
check "the saved configuration is untouched" \
	"uci export network | cmp -s - /tmp/net.before && uci export dhcp | cmp -s - /tmp/dhcp.before &&
	 uci export wireless | cmp -s - /tmp/wifi.before && [ -z \"\$(uci changes)\" ]"
check "router mode is restored" "ubus call supacudy netmode_set '$ROUTER' | grep -q applied"
eventually "the LAN is back on its own address" "ip -4 addr show br-lan | grep -q 'inet 192.168.200.1/24 brd' && [ ! -e /sys/class/net/eth0/master ]"

timed check "Wi-Fi is off and no cable is plugged in" "
	uci set wireless.radio0.disabled=1 && uci set wireless.radio1.disabled=1 && uci commit wireless && wifi reload && sleep 8 &&
	$LAPTOP ip link set eth0 down && ip netns exec nas ip link set eth0 down"
timed check "nothing happens before the third check" "$TICK && $TICK && ! iw dev sc-rescue info 2>/dev/null"
timed check "the third check starts the rescue network" \
	"$TICK && ubus call supacudy rescue_get | grep -q '\"ssid\": \"SupaCudy-Rescue\"'"
timed eventually "the open rescue network is on the air" "iw dev sc-rescue info | grep -q 'ssid SupaCudy-Rescue'"
timed check "a phone tries to join the open rescue network" "
	$PHONE iw dev ph1 del 2>/dev/null; phy=\$($PHONE iw dev ph0 info | sed -n 's/.*wiphy \\([0-9]*\\).*/phy\\1/p') && $PHONE iw phy \$phy interface add ph1 type managed &&
	printf 'network={\\n ssid=\"SupaCudy-Rescue\"\\n key_mgmt=NONE\\n}\\n' > /tmp/rescue-wpa.conf &&
	$PHONE wpa_supplicant -B -i ph1 -c /tmp/rescue-wpa.conf -P /tmp/rescue-wpa.pid >/dev/null"
# Association takes a few seconds on the emulated radio.
timed eventually "the phone is associated with the rescue network" "$PHONE iw dev ph1 link | grep -q 'SSID: SupaCudy-Rescue'"
timed check "the phone gets an address from the rescue network" \
	"$PHONE udhcpc -i ph1 -n -q -t 10 -s /bin/true 2>&1 | grep -q 'obtained from 192.168.200.1'"
timed check "the phone's extra interface is removed" "kill \$(cat /tmp/rescue-wpa.pid); $PHONE iw dev ph1 del"
timed check "cables and Wi-Fi come back" "
	$LAPTOP ip link set eth0 up && ip netns exec nas ip link set eth0 up &&
	uci -q delete wireless.radio0.disabled; uci -q delete wireless.radio1.disabled; uci commit wireless && wifi reload && sleep 10"
timed check "the rescue network goes away" "$TICK && $TICK && ! iw dev sc-rescue info 2>/dev/null && grep -q '\"active\": *false' $STATE"
check "the watcher is started again" "/etc/init.d/supacudy-rescue start && sleep 1 && pgrep -f '[r]escue-watch'"
