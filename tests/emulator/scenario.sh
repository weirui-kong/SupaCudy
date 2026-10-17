#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for the emulated network itself, which every feature test
# relies on. Sourced by run.sh.

eventually "WAN has an address from the QEMU network" \
	"ip -4 addr show dev eth0 | grep -q 'inet 10.250.2.'"
eventually "WAN reaches the internet" \
	"ping -c1 -W3 1.1.1.1"
eventually "LAN is 192.168.200.1/24, outside the developer's ranges" \
	"ip -4 addr show dev br-lan | grep -q 'inet 192.168.200.1/24'"

eventually "router broadcasts the 2.4 GHz network" \
	"iw dev phy0-ap0 info | grep -q 'ssid SupaCudy-Emu$'"
eventually "router broadcasts the 5 GHz network" \
	"iw dev phy1-ap0 info | grep -q 'ssid SupaCudy-Emu-5G'"

eventually "wired laptop got a DHCP lease" "grep -q ' Work-Laptop ' /tmp/dhcp.leases"
eventually "wired NAS got a DHCP lease" "grep -q ' Home-NAS ' /tmp/dhcp.leases"
eventually "phone associated with the router over WPA2" \
	"iw dev phy0-ap0 station dump | grep -q '^Station 02:00:00:00:02:00'"
eventually "phone got a DHCP lease" "grep -q ' Pixel-Phone ' /tmp/dhcp.leases"
eventually "clients generate traffic" \
	"ip netns exec laptop cat /sys/class/net/eth0/statistics/tx_bytes | awk '{ exit !(\$1 > 10000) }'"

eventually "upstream offers Hotel-WiFi and Cafe-Free" \
	"ip netns exec upstream iw dev | grep -q 'ssid Hotel-WiFi' && ip netns exec upstream iw dev | grep -q 'ssid Cafe-Free'"
eventually "router scan sees both upstream hotspots" \
	"ubus call iwinfo scan '{\"device\":\"phy0-ap0\"}' | grep -q '\"Hotel-WiFi\"' && ubus call iwinfo scan '{\"device\":\"phy0-ap0\"}' | grep -q '\"Cafe-Free\"'"
eventually "upstream reaches the internet through the uplink" \
	"ip netns exec upstream ping -c1 -W3 1.1.1.1"

eventually "SupaCudy UI is served" \
	"wget -q -O - http://127.0.0.1/supacudy/ | grep -q '<title>SupaCudy</title>'"
if curl -fsS "http://127.0.0.1:$EMU_HTTP_PORT/supacudy/" | grep -q '<title>SupaCudy</title>'; then
	ok "UI reachable from the host on 127.0.0.1"
else
	not_ok "UI reachable from the host on 127.0.0.1"
fi
eventually "the supacudy API answers" "ubus call supacudy info"
eventually "the client policy tables are loaded" \
	"nft list table bridge supacudy_acct && nft list table inet supacudy_block"
