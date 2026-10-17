#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for remote access through Tailscale. Signing in needs a
# Tailscale account and the internet, so only the router's side is checked:
# the daemon, the firewall zone and sharing the LAN. Sourced by run.sh.

GET="ubus call supacudy tailscale_get"

check "Tailscale is installed and off by default" \
	"$GET | jsonfilter -e @.installed | grep -q true && $GET | jsonfilter -e @.enabled | grep -q false &&
	 ! pgrep -f '[t]ailscaled'"
check "malformed settings are rejected as invalid" "! ubus call supacudy tailscale_set '{\"enabled\":\"yes\",\"share_lan\":false}'"
check "signing out while off is refused" "ubus call supacudy tailscale_logout | grep -q tailscale_not_running"
check "Tailscale is turned on" "ubus call supacudy tailscale_set '{\"enabled\":true,\"share_lan\":false}' | grep -q applied"
eventually "tailscaled runs and answers" "pgrep -f '[t]ailscaled' && $GET | jsonfilter -e @.state | grep -q ."
eventually "its interface gets a zone that accepts input but does not reach the LAN" \
	"[ \"\$(uci get firewall.supacudy_ts.device)\" = tailscale0 ] && [ \"\$(uci get firewall.supacudy_ts.input)\" = ACCEPT ] &&
	 ! uci -q get firewall.supacudy_ts_lan && nft list chain inet fw4 forward | grep -q tailscale0"
check "the LAN is shared" "ubus call supacudy tailscale_set '{\"enabled\":true,\"share_lan\":true}' | grep -q applied"
eventually "the zone may forward to the LAN and the LAN subnet is offered" \
	"[ \"\$(uci get firewall.supacudy_ts_lan.dest)\" = lan ] && $GET | jsonfilter -e @.lan | grep -qx 192.168.200.0/24 &&
	 tailscale debug prefs | grep -q 192.168.200.0/24"
check "Tailscale is turned off" "ubus call supacudy tailscale_set '{\"enabled\":false,\"share_lan\":false}' | grep -q applied"
eventually "the daemon stops and the zone is gone" \
	"! pgrep -f '[t]ailscaled' && ! uci -q get firewall.supacudy_ts && ! uci -q get firewall.supacudy_ts_lan &&
	 ! nft list chain inet fw4 forward | grep -q tailscale0"
