#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for port forwarding. The "internet" side is the hotel
# network: the router joins it as a repeater (wwan is in the WAN zone), and
# the hotel namespace fetches from the router's address there. A small web
# server runs in the laptop namespace. Sourced by run.sh.

UP="ip netns exec upstream"
LAPTOP="ip netns exec laptop"
WWAN_IP="ubus call network.interface.wwan status | jsonfilter -e '@[\"ipv4-address\"][0].address'"
LAPTOP_IP="$LAPTOP ip -4 -o addr show eth0 | sed 's#.* inet \\([0-9.]*\\)/.*#\\1#'"
fetch() { echo "$UP uclient-fetch -q -T 3 -O - http://\$($WWAN_IP):$1/"; }
SSH_BANNER="sleep 2 | $UP nc \$($WWAN_IP) 22 2>/dev/null | head -c 7 | grep -q SSH-2.0"
wan_access() { echo "ubus call supacudy wan_access_set '{\"webui\":$1,\"ssh\":$2}' | grep -q applied"; }

check "the router joins the hotel network" \
	"ubus call supacudy repeater_connect '{\"ssid\":\"Hotel-WiFi\",\"bssid\":\"\",\"encryption\":\"psk2\",\"key\":\"hotel-guest\",\"band\":\"2g\",\"save\":false}' | grep -q applied"
eventually "the repeater has an address in the hotel network" "$WWAN_IP | grep -q '^10.250.11.'"

check "out of the box the web UI is open to the WAN and SSH is not" \
	"ubus call supacudy wan_access_get | jsonfilter -e @.webui | grep -qx true &&
	 ubus call supacudy wan_access_get | jsonfilter -e @.ssh | grep -qx false"
eventually "the hotel reaches the web UI" "$(fetch 80) | grep -qi html"
check "the hotel cannot reach SSH" "! $SSH_BANNER"
check "a WAN access change without both switches is rejected as invalid" \
	"! ubus call supacudy wan_access_set '{\"webui\":true}' && ! ubus call supacudy wan_access_set '{\"webui\":1,\"ssh\":false}'"
check "SSH is opened to the WAN and the web UI closed" "$(wan_access false true)"
eventually "the hotel reaches SSH" "$SSH_BANNER"
eventually "the web UI is closed to the hotel" "! $(fetch 80)"
check "SSH is closed again" "$(wan_access false false)"
eventually "the hotel can no longer reach SSH" "! $SSH_BANNER"
check "a web server runs on the laptop" \
	"mkdir -p /tmp/laptop-www && echo hello-from-laptop > /tmp/laptop-www/index.html &&
	 $LAPTOP uhttpd -p 0.0.0.0:8080 -h /tmp/laptop-www && $LAPTOP uclient-fetch -q -O - http://127.0.0.1:8080/ | grep -q hello"
check "without a forward the hotel cannot reach it" "! $(fetch 8088)"
check "a port forward to the laptop is added" \
	"ubus call supacudy forward_set \"{\\\"id\\\":\\\"\\\",\\\"name\\\":\\\"Laptop web\\\",\\\"proto\\\":\\\"tcp\\\",\\\"external_port\\\":\\\"8088\\\",\\\"internal_ip\\\":\\\"\$($LAPTOP_IP)\\\",\\\"internal_port\\\":\\\"8080\\\",\\\"enabled\\\":true}\" | jsonfilter -e @.id > /tmp/fwd-id"
eventually "the hotel reaches the laptop through the forward" "$(fetch 8088) | grep -q hello-from-laptop"
check "an overlapping forward is refused" \
	"ubus call supacudy forward_set '{\"id\":\"\",\"name\":\"Clash\",\"proto\":\"tcp udp\",\"external_port\":\"8000-8100\",\"internal_ip\":\"192.168.200.50\",\"internal_port\":\"\",\"enabled\":true}' | grep -q port_in_use"
check "a forward to an address outside the LAN is refused" \
	"ubus call supacudy forward_set '{\"id\":\"\",\"name\":\"Out\",\"proto\":\"tcp\",\"external_port\":\"9000\",\"internal_ip\":\"10.250.11.5\",\"internal_port\":\"\",\"enabled\":true}' | grep -q not_lan"
check "mismatched port ranges are rejected as invalid" \
	"! ubus call supacudy forward_set '{\"id\":\"\",\"name\":\"R\",\"proto\":\"tcp\",\"external_port\":\"9000-9010\",\"internal_ip\":\"192.168.200.50\",\"internal_port\":\"7000\",\"enabled\":true}'"
check "the forward is turned off" \
	"ubus call supacudy forward_set \"{\\\"id\\\":\\\"\$(cat /tmp/fwd-id)\\\",\\\"name\\\":\\\"Laptop web\\\",\\\"proto\\\":\\\"tcp\\\",\\\"external_port\\\":\\\"8088\\\",\\\"internal_ip\\\":\\\"\$($LAPTOP_IP)\\\",\\\"internal_port\\\":\\\"8080\\\",\\\"enabled\\\":false}\" | grep -q id"
eventually "the hotel can no longer reach the laptop" "! $(fetch 8088)"

check "the laptop becomes the DMZ host" \
	"ubus call supacudy dmz_set \"{\\\"enabled\\\":true,\\\"ip\\\":\\\"\$($LAPTOP_IP)\\\"}\" | grep -q applied"
eventually "any port reaches the DMZ host" "$(fetch 8080) | grep -q hello-from-laptop"
check "the DMZ is turned off" "ubus call supacudy dmz_set '{\"enabled\":false,\"ip\":\"\"}' | grep -q applied"
eventually "the DMZ host is closed again" "! $(fetch 8080)"

check "a port is opened on the router" \
	"ubus call supacudy open_port_set '{\"id\":\"\",\"name\":\"Web admin\",\"proto\":\"tcp\",\"port\":\"80\",\"enabled\":true}' | jsonfilter -e @.id > /tmp/open-id"
eventually "the hotel reaches the router's own web server" "$(fetch 80) | grep -qi html"
check "the open port is closed and the rest cleaned up" "
	ubus call supacudy open_port_delete \"{\\\"id\\\":\\\"\$(cat /tmp/open-id)\\\"}\" | grep -q deleted &&
	ubus call supacudy forward_delete \"{\\\"id\\\":\\\"\$(cat /tmp/fwd-id)\\\"}\" | grep -q deleted &&
	kill \$(pgrep -f '[u]httpd -p 0.0.0.0:8080') && ubus call supacudy repeater_disconnect | grep -q applied"
eventually "the router's web server is closed to the hotel again" "! $(fetch 80) && ! uci show firewall | grep -q sc_"
check "WAN access is back to the defaults" \
	"$(wan_access true false) && [ \"\$(uci get firewall.supacudy_wan_webui.enabled)\" = 1 ] &&
	 [ \"\$(uci get firewall.supacudy_wan_ssh.enabled)\" = 0 ]"
