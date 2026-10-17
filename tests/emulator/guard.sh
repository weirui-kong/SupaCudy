#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for the login protection. The failed logins come from the
# laptop namespace, a LAN client, so the host running the tests is never
# banned. Sourced by run.sh.

ADMIN="supacudy-test"
LAPTOP="ip netns exec laptop"
LAPTOP_IP="\$($LAPTOP ip -4 -o addr show dev eth0 | sed -n 's/.* inet \\([0-9.]*\\).*/\\1/p')"
GET="ubus call supacudy guard_get"
cgi_login() { echo "$LAPTOP curl -s -m 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{\"password\":\"$1\"}' http://192.168.200.1/cgi-bin/supacudy-login"; }
WEB_OPEN="$LAPTOP curl -s -m 15 -o /dev/null http://192.168.200.1/supacudy/"
SSH_OPEN="sleep 1 | $LAPTOP nc 192.168.200.1 22 2>/dev/null | head -c 7 | grep -q SSH-2.0"
BANNED="$GET | jsonfilter -e '@.banned[*].ip' | grep -qx $LAPTOP_IP"
UNBAN="ubus call supacudy guard_unban \"{\\\"ip\\\":\\\"$LAPTOP_IP\\\"}\" | grep -q applied"
guard() { echo "ubus call supacudy guard_set '{\"enabled\":$1,\"attempts\":$2,\"window\":$3,\"ban\":$4}' | grep -q applied"; }
AGH_FAIL="logger -t 'AdGuardHome[4242]' \"2026/10/18 00:00:00.000000 [error] POST 192.168.200.1:3000 /control/login: from ip $LAPTOP_IP: invalid username or password\""

# An earlier suite may have unplugged the laptop, which drops its default
# route until the DHCP client renews.
eventually "the laptop is back on the LAN and online" \
	"kill -USR1 \$(pgrep -f '[h]ostname:Work-Laptop'); sleep 2;
	 $LAPTOP ping -c1 -W2 192.168.200.1 && $LAPTOP ping -c1 -W2 10.250.2.2"
check "login protection is on out of the box: 3 failures in 30 minutes ban for 120" \
	"$GET | jsonfilter -e @.enabled | grep -qx true && $GET | jsonfilter -e @.attempts | grep -qx 3 &&
	 $GET | jsonfilter -e @.window | grep -qx 30 && $GET | jsonfilter -e @.ban | grep -qx 120"
eventually "the ban covers SSH, the web UI and AdGuard Home's page only" \
	"pgrep -f '[l]ogin-guard.uc' && nft list chain inet supacudy_guard input | grep -q 'tcp dport { 22, 80, 443, 3000 }'"
check "anonymous session.login on /ubus is closed, even with the right password" \
	"curl -s -m 15 http://127.0.0.1/ubus -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"00000000000000000000000000000000\",\"session\",\"login\",{\"username\":\"root\",\"password\":\"$ADMIN\"}]}' | grep -q '\"code\":-32002'"
check "the login CGI logs in with the right password" "[ \"\$($(cgi_login "$ADMIN"))\" = 200 ]"

check "two wrong passwords are refused but not enough for a ban" \
	"[ \"\$($(cgi_login wrong-1))\" = 403 ] && [ \"\$($(cgi_login wrong-2))\" = 403 ] && sleep 2 && ! $BANNED && $WEB_OPEN"
check "a successful login in between starts the count again" \
	"[ \"\$($(cgi_login "$ADMIN"))\" = 200 ] && $(cgi_login wrong-3) >/dev/null && $(cgi_login wrong-4) >/dev/null && sleep 2 && ! $BANNED"
check "the third failure in a row bans the laptop" "$(cgi_login wrong-5) >/dev/null; sleep 2; $BANNED"
check "the banned laptop can reach neither the web UI nor SSH" "! $WEB_OPEN && ! $SSH_OPEN"
check "it keeps its internet access and the router's DNS" \
	"$LAPTOP ping -c1 -W2 10.250.2.2 && $LAPTOP nslookup example.org 192.168.200.1 >/dev/null"
check "the ban lasts 120 minutes" \
	"expires=\$($GET | jsonfilter -e '@.banned[0].expires'); [ \"\$expires\" -gt 7000 ] && [ \"\$expires\" -le 7200 ]"
check "changing the numbers keeps the current ban" "$(guard true 5 10 60) && sleep 2 && $BANNED && ! $WEB_OPEN"
check "unbanning lets the laptop in again" "$UNBAN && ! $BANNED && $WEB_OPEN && $SSH_OPEN"
check "unbanning an address that is not banned reports not found" \
	"! ubus call supacudy guard_unban '{\"ip\":\"203.0.113.77\"}'"

check "with one failure enough, the numbers take effect without a restart" "$(guard true 1 30 1)"
check "a wrong SSH password counts" \
	"$LAPTOP env DROPBEAR_PASSWORD=wrong-ssh dbclient -y -y root@192.168.200.1 true </dev/null >/dev/null 2>&1; sleep 2; $BANNED"
check "a ban of one minute expires within a minute" \
	"expires=\$($GET | jsonfilter -e '@.banned[0].expires'); [ \"\$expires\" -le 60 ] && $UNBAN"
check "a wrong LuCI password counts" \
	"$LAPTOP curl -s -m 15 -o /dev/null -d 'luci_username=root&luci_password=wrong-luci' http://192.168.200.1/cgi-bin/luci/; sleep 2; $BANNED && $UNBAN"
check "a failed AdGuard Home login counts" "$AGH_FAIL; sleep 2; $BANNED && $UNBAN"
check "the router's own local logins are never banned" \
	"for i in 1 2 3; do curl -s -m 15 -o /dev/null -d '{\"password\":\"local-wrong\"}' http://127.0.0.1/cgi-bin/supacudy-login; done;
	 sleep 2; ! $GET | jsonfilter -e '@.banned[*].ip' | grep -q '^127\\.'"

check "settings out of range are rejected as invalid" \
	"! ubus call supacudy guard_set '{\"enabled\":true,\"attempts\":0,\"window\":30,\"ban\":120}' &&
	 ! ubus call supacudy guard_set '{\"enabled\":true,\"attempts\":3,\"window\":30,\"ban\":99999}' &&
	 ! ubus call supacudy guard_set '{\"enabled\":true,\"attempts\":3}'"
check "turning it off lifts the protection" "$AGH_FAIL; sleep 2; $BANNED && $(guard false 1 30 1)"
eventually "the firewall table is gone and the laptop gets in" "! nft list table inet supacudy_guard 2>/dev/null && $WEB_OPEN"
check "while off, failures ban nobody" "$AGH_FAIL; sleep 2; $WEB_OPEN"
check "the defaults are back" "$(guard true 3 30 120)"
eventually "the protection runs again" "pgrep -f '[l]ogin-guard.uc' && nft list table inet supacudy_guard >/dev/null && ! $BANNED"
