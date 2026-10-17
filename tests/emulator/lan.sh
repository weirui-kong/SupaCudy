#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for LAN addressing and DHCP reservations: settings reach
# dnsmasq and the clients. Sourced by run.sh.

NAS=02:5c:00:00:00:12
POOL='"ipaddr":"192.168.200.1","netmask":"255.255.255.0","dhcp_enabled":true'

check "lan_get reports the emulator LAN" \
	"ubus call supacudy lan_get | grep -q '\"ipaddr\": \"192.168.200.1\"'"

check "changing the pool reaches dnsmasq" "
	ubus call supacudy lan_set '{$POOL,\"start\":120,\"limit\":30,\"leasetime\":\"6h\"}' | grep -q applied
	for i in \$(seq 15); do grep -q 'dhcp-range=set:lan,192.168.200.120,192.168.200.149,255.255.255.0,6h' /var/etc/dnsmasq.conf.* && exit 0; sleep 2; done; exit 1"
check "the pool is restored" "
	ubus call supacudy lan_set '{$POOL,\"start\":100,\"limit\":150,\"leasetime\":\"12h\"}' | grep -q applied
	for i in \$(seq 15); do grep -q 'dhcp-range=set:lan,192.168.200.100,192.168.200.249' /var/etc/dnsmasq.conf.* && exit 0; sleep 2; done; exit 1"

check "a subnet overlapping another network is refused" \
	"ubus call supacudy lan_set '{\"ipaddr\":\"10.250.3.1\",\"netmask\":\"255.255.255.0\",\"dhcp_enabled\":true,\"start\":100,\"limit\":100,\"leasetime\":\"12h\"}' | grep -q subnet_conflict"
check "a public subnet is refused" \
	"ubus call supacudy lan_set '{\"ipaddr\":\"8.8.8.1\",\"netmask\":\"255.255.255.0\",\"dhcp_enabled\":true,\"start\":100,\"limit\":100,\"leasetime\":\"12h\"}' | grep -q not_private"
check "a pool larger than the subnet is refused" \
	"ubus call supacudy lan_set '{$POOL,\"start\":200,\"limit\":100,\"leasetime\":\"12h\"}' | grep -q pool_out_of_range"
check "refused changes leave the config untouched" \
	"[ \"\$(uci get network.lan.ipaddr)\" = 192.168.200.1 ] && [ \"\$(uci get dhcp.lan.start)\" = 100 ]"

check "a reservation is written for dnsmasq" "
	ubus call supacudy reservation_set '{\"mac\":\"$NAS\",\"ip\":\"192.168.200.60\",\"name\":\"nas\"}' | grep -q 192.168.200.60
	sleep 3
	grep -q '$NAS,192.168.200.60,nas' /var/etc/dnsmasq.conf.* || grep -rq '$NAS' /tmp/hosts /var/etc/dnsmasq.conf.*"
# SIGUSR2 releases the lease and SIGUSR1 asks for a new one. The bracket
# keeps pgrep from matching the shell running this check.
check "the NAS gets its reserved address after renewing" "
	pid=\$(pgrep -f '[h]ostname:Home-NAS')
	kill -USR2 \$pid; sleep 1; kill -USR1 \$pid
	for i in 1 2 3 4 5 6 7 8 9 10; do
		ip netns exec nas ip -4 addr show eth0 | grep -q 192.168.200.60 && exit 0
		sleep 2
	done
	exit 1"
check "a reservation outside the LAN is refused" \
	"ubus call supacudy reservation_set '{\"mac\":\"$NAS\",\"ip\":\"10.0.0.5\",\"name\":\"\"}' | grep -q outside_lan"
check "reserving the router's own address is refused" \
	"ubus call supacudy reservation_set '{\"mac\":\"$NAS\",\"ip\":\"192.168.200.1\",\"name\":\"\"}' | grep -q router_address"
check "an address reserved by another device is refused" \
	"ubus call supacudy reservation_set '{\"mac\":\"02:5c:00:00:00:99\",\"ip\":\"192.168.200.60\",\"name\":\"\"}' | grep -q ip_taken"
check "deleting a reservation removes it" \
	"ubus call supacudy reservation_delete '{\"mac\":\"$NAS\"}' | grep -q deleted && ! uci show dhcp | grep -q '$NAS'"
check "deleting an unknown reservation reports not found" \
	"! ubus call supacudy reservation_delete '{\"mac\":\"$NAS\"}'"
