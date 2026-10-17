#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for the OpenVPN client against the scenario's server
# (10.250.10.2:1194, tunnel 10.250.31.0/24, test-only certificates).
# Sourced by run.sh.

LAPTOP="ip netns exec laptop"
UNSAFE='{"id":"","name":"Evil","config":"client\nremote 10.250.10.2 1194\nup /bin/touch /tmp/pwned\n","username":"","password":""}'

check "a configuration that runs programs is refused" \
	"ubus call supacudy vpn_ovpn_set '$UNSAFE' | grep -q '\"directive\": \"up\"' && ! uci show supacudy | grep -q ovpn_profile"
check "a password without a user name is refused" \
	"ubus call supacudy vpn_ovpn_set '{\"id\":\"\",\"name\":\"x\",\"config\":\"remote a 1\",\"username\":\"\",\"password\":\"p\"}' | grep -q '\"field\": \"username\"'"
vm 'cat > /tmp/ovpn-add.uc' < "$(dirname "${BASH_SOURCE[0]}")/ovpn-add.uc"
check "the provider's profile is saved" "ucode /tmp/ovpn-add.uc > /tmp/ovpn-id && grep -q '^cfg' /tmp/ovpn-id"
check "the saved file is private, uses the fixed device and drops the provider's dev line" \
	"f=/etc/supacudy/ovpn/\$(cat /tmp/ovpn-id).ovpn && ls -l \$f | grep -q '^-rw-------' &&
	 grep -q '^dev ovpnc$' \$f && [ \"\$(grep -c '^dev ' \$f)\" = 1 ] && grep -q 'BEGIN' \$f"
check "the profile lists its server" \
	"ubus call supacudy vpn_get | grep -q '\"remote\": \"10.250.10.2:1194\"'"
check "the DNS server named in the file is kept with the profile" \
	"[ \"\$(uci get supacudy.\$(cat /tmp/ovpn-id).dns)\" = 10.250.31.53 ]"

check "connecting is accepted" "ubus call supacudy vpn_connect \"{\\\"id\\\":\\\"\$(cat /tmp/ovpn-id)\\\"}\" | grep -q applied"
eventually "the tunnel gets an address from the server" \
	"ip -4 addr show ovpnc | grep -q 'inet 10.250.31.' && ubus call supacudy vpn_get | jsonfilter -e @.status.connected | grep -q true"
eventually "LAN devices reach the server through the tunnel" "$LAPTOP ping -c1 -W2 10.250.31.1"
# OpenVPN hands over the file's own dhcp-option lines with the pushed ones.
eventually "lookups go to the file's DNS server and the one the server pushed" \
	"uci get supacudy.vpn.pushed_dns | grep -qw 10.250.31.1 &&
	 uci get dhcp.@dnsmasq[0].server | grep -q 10.250.31.53 && uci get dhcp.@dnsmasq[0].server | grep -q 10.250.31.1 &&
	 [ \"\$(uci get dhcp.@dnsmasq[0].noresolv)\" = 1 ] && grep -q '^server=10.250.31.1$' /var/etc/dnsmasq.conf.*"
check "choosing devices is ignored for OpenVPN, without restarting the tunnel" \
	"pgrep -f '^/usr/sbin/[o]penvpn .*supacudy' > /tmp/ovpn-pid &&
	 ubus call supacudy vpn_options '{\"kill_switch\":false,\"allow_lan\":true,\"route_mode\":\"selected\",\"devices\":[],\"destinations\":[]}' | grep -q applied &&
	 sleep 4 && ! ip rule | grep -q 'fwmark 0x100' && [ \"\$(pgrep -f '^/usr/sbin/[o]penvpn .*supacudy')\" = \"\$(cat /tmp/ovpn-pid)\" ]"
eventually "LAN devices still reach the server through the tunnel" "$LAPTOP ping -c1 -W2 10.250.31.1"
check "devices go back to all" \
	"ubus call supacudy vpn_options '{\"kill_switch\":false,\"allow_lan\":true,\"route_mode\":\"all\",\"devices\":[],\"destinations\":[]}' | grep -q applied"

check "disconnecting is accepted" "ubus call supacudy vpn_disconnect | grep -q applied"
eventually "the OpenVPN client stops" "! ip link show ovpnc && [ \"\$(uci get openvpn.supacudy.enabled)\" = 0 ]"
check "the VPN's DNS servers are dropped again" \
	"! uci -q get supacudy.vpn.pushed_dns && ! uci -q get dhcp.@dnsmasq[0].server | grep -q 10.250.31. &&
	 ! uci -q get dhcp.@dnsmasq[0].noresolv"
check "deleting the profile removes its files" \
	"id=\$(cat /tmp/ovpn-id) && ubus call supacudy vpn_profile_delete \"{\\\"id\\\":\\\"\$id\\\"}\" | grep -q deleted &&
	 ! ls /etc/supacudy/ovpn/\$id.* 2>/dev/null"
