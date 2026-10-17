#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for the WireGuard client against the scenario's server in
# the upstream namespace (test-only keys, see docs/emulator.md). Targets are
# inside the VM: the server's tunnel address 10.250.30.1 is only reachable
# through the tunnel, the QEMU gateway 10.250.2.2 only around it.
# Sourced by run.sh.

PROFILE='"name":"Emu VPN","private_key":"oGwIsQXePkq1NIVJdElbnzYDLLHMwFq5A+5Ilruz11s=","public_key":"qrYCfRcXMOaEA2xznhSAKdDiPRWAHe6VeBTg4Jqawzg=","preshared_key":"irMdu0PKEDRBjbj/oi0azFqXoQ6PlS7h9dY2NMRHFp8=","addresses":["10.250.30.2/32"],"dns":["10.250.2.3"],"endpoint_host":"10.250.10.2","endpoint_port":51820,"allowed_ips":["0.0.0.0/0"],"keepalive":25,"mtu":0'
LAPTOP="ip netns exec laptop"
SERVER="ip netns exec upstream"
DNSMASQ_CONF="/var/etc/dnsmasq.conf.*"
KEEPALIVE_40="${PROFILE/\"keepalive\":25/\"keepalive\":40}"
BAD_KEY="${PROFILE/qrYCfRcXMOaEA2xznhSAKdDiPRWAHe6VeBTg4Jqawzg=/short}"
BAD_ADDRESS="${PROFILE/10.250.30.2\/32/10.250.30.2}"
NAS="ip netns exec nas"
LAPTOP_MAC=02:5c:00:00:00:11
options() {
	echo "ubus call supacudy vpn_options '{\"kill_switch\":$1,\"allow_lan\":$2,\"route_mode\":\"${3:-all}\",\"devices\":[${4:-}],\"destinations\":[${5:-}]}' | grep -q applied"
}

check "a malformed key is refused with the field" \
	"ubus call supacudy vpn_profile_set '{\"id\":\"\",$BAD_KEY}' | grep -q '\"field\": \"public_key\"'"
check "an address without a prefix is refused" \
	"ubus call supacudy vpn_profile_set '{\"id\":\"\",$BAD_ADDRESS}' | grep -q '\"field\": \"addresses\"'"
check "connecting an unknown profile reports not found" \
	"! ubus call supacudy vpn_connect '{\"id\":\"nope\"}'"
check "the profile is saved" \
	"ubus call supacudy vpn_profile_set '{\"id\":\"\",$PROFILE}' | jsonfilter -e @.id > /tmp/vpn-id && [ -s /tmp/vpn-id ]"
check "saved keys are not handed back to the UI" \
	"! ubus call supacudy vpn_get | grep -q oGwIsQXe && ubus call supacudy vpn_get | grep -q '\"has_preshared_key\": true'"

check "connecting is accepted" "ubus call supacudy vpn_connect \"{\\\"id\\\":\\\"\$(cat /tmp/vpn-id)\\\"}\" | grep -q applied"
eventually "the tunnel completes a handshake with the server" \
	"$SERVER wg show wg0 latest-handshakes | awk '{exit !(\$2 > 0)}' &&
	 ubus call supacudy vpn_get | jsonfilter -e @.status.handshake | grep -qv '^0$'"
eventually "all traffic is routed into the tunnel" "ip route show default | grep -q 'dev vpn'"
eventually "LAN devices reach the server's tunnel address" "$LAPTOP ping -c1 -W2 10.250.30.1"
check "IPv6 cannot bypass a tunnel without an IPv6 address" \
	"ubus call supacudy vpn_get | jsonfilter -e @.ipv6 | grep -qx blocked &&
	 [ \"\$(uci get firewall.supacudy_vpn_no6.family)\" = ipv6 ] && [ \"\$(uci get firewall.supacudy_vpn_no6.target)\" = REJECT ]"
eventually "the IPv6 block is loaded" "nft list ruleset | grep -q 'no IPv6 outside the tunnel'"
check "the profile's DNS server is used while connected" \
	"grep -q '^server=10.250.2.3$' $DNSMASQ_CONF && grep -q '^no-resolv$' $DNSMASQ_CONF"
check "the connected profile cannot be deleted" \
	"ubus call supacudy vpn_profile_delete \"{\\\"id\\\":\\\"\$(cat /tmp/vpn-id)\\\"}\" | grep -q profile_active"

VPN_ID="$(vm cat /tmp/vpn-id)"
check "editing the connected profile is accepted" \
	"ubus call supacudy vpn_profile_set '{\"id\":\"$VPN_ID\",$KEEPALIVE_40}' | grep -q '\"id\"'"
eventually "the new peer settings reach the running tunnel" "wg show vpn persistent-keepalive | grep -q '[[:space:]]40\$'"
check "the kill switch is turned on without the LAN exception" "$(options true false)"
check "the server goes away" "$SERVER ip link set wg0 down"
eventually "with the tunnel down, LAN devices cannot get around it" \
	"! $LAPTOP ping -c1 -W2 10.250.2.2"
check "the upstream network exception is turned on" "$(options true true)"
eventually "private upstream addresses are reachable again" "$LAPTOP ping -c1 -W2 10.250.2.2"
check "the kill switch is turned off" "$(options false true)"
check "the server comes back" "$SERVER ip link set wg0 up"
eventually "the tunnel recovers" "$LAPTOP ping -c1 -W2 10.250.30.1"

check "only the laptop is sent through the VPN" "$(options false true selected "\"$LAPTOP_MAC\"")"
eventually "the VPN's routes move to their own table with a rule for marked packets" \
	"! ip route show default | grep -q 'dev vpn' && ip route show table 100 | grep -q 'dev vpn' &&
	 ip rule | grep -q 'fwmark 0x100/0x100 lookup 100' && nft list set inet supacudy_vpnroute vpn_macs | grep -q $LAPTOP_MAC"
eventually "the laptop reaches the tunnel" "$LAPTOP ping -c1 -W2 10.250.30.1"
check "only the laptop's IPv6 is held back, not everyone's" \
	"! uci -q get firewall.supacudy_vpn_no6 && nft list table inet supacudy_vpnroute | grep -q 'meta nfproto ipv6'"
check "the NAS does not use the tunnel" "! $NAS ping -c1 -W2 10.250.30.1 && $NAS ping -c1 -W2 10.250.2.2"
eventually "the profile's DNS is not forced on everyone" "! grep -q '^server=10.250.2.3$' $DNSMASQ_CONF"
check "the kill switch is turned on for the laptop only" "$(options true false selected "\"$LAPTOP_MAC\"")"
check "the server goes away again" "$SERVER ip link set wg0 down"
eventually "the laptop is cut off while the NAS stays online" \
	"! $LAPTOP ping -c1 -W2 10.250.2.2 && $NAS ping -c1 -W2 10.250.2.2"
check "all devices use the VPN again" "$(options false true all)"
check "the server is back" "$SERVER ip link set wg0 up"
check "only the server's tunnel address and a website go through the VPN" "$(options false true selected '' '"10.250.30.1/32","vpn-test.example"')"
eventually "dnsmasq collects the website's addresses and the routes are marked" \
	"grep -q '^nftset=/vpn-test.example/4#inet#supacudy_vpnroute#vpn_dst' /var/etc/dnsmasq.conf.* &&
	 nft list set inet supacudy_vpnroute vpn_dst | grep -q 10.250.30.1"
eventually "the NAS reaches the tunnel address through the VPN" "$NAS ping -c1 -W2 10.250.30.1"
check "other destinations stay on the normal path" "$NAS ping -c1 -W2 10.250.2.2"
check "a malformed destination is refused" \
	"ubus call supacudy vpn_options '{\"kill_switch\":false,\"allow_lan\":true,\"route_mode\":\"selected\",\"devices\":[],\"destinations\":[\"not a host\"]}' | grep -q destination_invalid"
check "all devices use the VPN once more" "$(options false true all)"
eventually "the routes return to the main table" \
	"ip route show default | grep -q 'dev vpn' && ! ip rule | grep -q 'fwmark 0x100' && ! nft list table inet supacudy_vpnroute 2>/dev/null | grep -q vpn_macs"

check "disconnecting is accepted" "ubus call supacudy vpn_disconnect | grep -q applied"
check "the IPv6 block is lifted" "! uci -q get firewall.supacudy_vpn_no6 && ubus call supacudy vpn_get | grep -q '\"ipv6\": null'"
eventually "the tunnel, its DNS and its firewall changes are gone" \
	"! ip link show vpn && ! uci -q get network.vpn && ! grep -q '^server=10.250.2.3$' $DNSMASQ_CONF &&
	 ! uci show firewall | grep -q \"enabled='0'\" && ! uci -q get firewall.supacudy_vpn_lan"
eventually "LAN devices use the WAN directly again" "$LAPTOP ping -c1 -W2 10.250.2.2 && ! $LAPTOP ping -c1 -W2 10.250.30.1"
check "the profile is deleted" \
	"ubus call supacudy vpn_profile_delete \"{\\\"id\\\":\\\"\$(cat /tmp/vpn-id)\\\"}\" | grep -q deleted && ! uci show supacudy | grep -q wg_profile"
