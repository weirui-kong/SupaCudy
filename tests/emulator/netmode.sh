#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for the operating mode. In access point mode the WAN port
# (QEMU's NAT network, 10.250.2.0/24) joins the LAN and the router takes a
# fixed address there; the tests reach the VM through the management port
# throughout. Runs just before the reboot, which tidies up the LAN clients.
# Sourced by run.sh.

AP='{"mode":"ap","ipaddr":"10.250.2.50","netmask":"255.255.255.0","gateway":"10.250.2.2","dns":["10.250.2.3"]}'

check "a gateway outside the address's network is refused" \
	"ubus call supacudy netmode_set '{\"mode\":\"ap\",\"ipaddr\":\"10.250.2.50\",\"netmask\":\"255.255.255.0\",\"gateway\":\"10.250.9.1\",\"dns\":[]}' | grep -q gateway_outside"
check "the main router's network is suggested" \
	"ubus call supacudy netmode_get | jsonfilter -e @.upstream.gateway | grep -qx 10.250.2.2"
check "access point mode is accepted" "ubus call supacudy netmode_set '$AP' | grep -q applied"
eventually "the WAN port is in the LAN bridge, which has the fixed address" \
	"[ \"\$(basename \"\$(readlink /sys/class/net/eth0/master)\")\" = br-lan ] &&
	 ip -4 addr show br-lan | grep -q 'inet 10.250.2.50/24' && ip route show default | grep -q 'via 10.250.2.2 dev br-lan'"
check "the router no longer hands out addresses or routes the WAN" \
	"[ \"\$(uci get dhcp.lan.ignore)\" = 1 ] && [ \"\$(uci get network.wan.disabled)\" = 1 ] &&
	 ubus call supacudy netmode_get | jsonfilter -e @.mode | grep -qx ap"
check "the WAN port cannot be reassigned in access point mode" \
	"ubus call supacudy wan_port_set '{\"as_lan\":true}' | grep -q ap_mode"
check "router mode is restored" "ubus call supacudy netmode_set '{\"mode\":\"router\",\"ipaddr\":\"\",\"netmask\":\"\",\"gateway\":\"\",\"dns\":[]}' | grep -q applied"
eventually "the LAN, DHCP and WAN are as before" \
	"ip -4 addr show br-lan | grep -q 'inet 192.168.200.1/24' && [ ! -e /sys/class/net/eth0/master ] &&
	 ! uci -q get dhcp.lan.ignore && ! uci -q get network.lan.gateway &&
	 ubus call network.interface.wan status | jsonfilter -e @.up | grep -q true"
