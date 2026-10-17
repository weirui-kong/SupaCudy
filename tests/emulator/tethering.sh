#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for USB tethering. QEMU's usb-net device plays a phone
# sharing its connection (RNDIS) on 10.250.42.0/24. Sourced by run.sh.

check "the phone's USB network device is detected" \
	"ubus call supacudy internet_status | jsonfilter -e @.tethering.available | grep -q true"
check "tethering starts off" \
	"ubus call supacudy internet_status | jsonfilter -e @.tethering.enabled | grep -q false && ! uci -q get network.tethering"
check "a non-boolean switch is rejected as invalid" "! ubus call supacudy tethering_set '{\"enabled\":\"yes\"}'"
check "tethering is turned on" "ubus call supacudy tethering_set '{\"enabled\":true}' | grep -q applied"
eventually "the router gets an address from the phone, behind Ethernet and the repeater" \
	"ubus call supacudy internet_status | jsonfilter -e @.tethering.ipaddr | grep -q '^10.250.42.' &&
	 ip route show default | grep -q 'via 10.250.42.2 .*metric 30' && uci get firewall.@zone[1].network | grep -q tethering"
check "re-plugging the phone points the interface at its device again" \
	"uci set network.tethering.device=gone0 && uci commit network &&
	 dev=\$(ubus call supacudy internet_status | jsonfilter -e @.tethering.device) &&
	 ACTION=add DEVICENAME=\$dev sh /etc/hotplug.d/net/30-supacudy-tethering && [ \"\$(uci get network.tethering.device)\" = \"\$dev\" ]"
check "tethering is turned off" "ubus call supacudy tethering_set '{\"enabled\":false}' | grep -q applied"
eventually "the phone's route and interface are gone" \
	"! uci -q get network.tethering && ! ip route | grep -q 10.250.42. && ! uci get firewall.@zone[1].network | grep -q tethering"
