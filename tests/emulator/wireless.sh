#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for Wi-Fi: settings reach the radios, the phone follows
# password changes, and the guest network is really isolated. Sourced by
# run.sh.

RADIO0='"radio":"radio0","enabled":true,"channel":"6","width":20,"txpower":"max","hidden":false'
RADIO1='"radio":"radio1","enabled":true,"channel":"36","width":20,"txpower":"max","hidden":false'
MAIN_KEY='"ssid":"SupaCudy-Emu","encryption":"psk2","key":"supacudy-wifi"'
GUEST='"radio":"radio0","ssid":"SupaCudy-Guest","encryption":"psk2","key":"guest-pass-1","hidden":false'
IN_VISITOR="ip netns exec visitor"
PHONE=02:00:00:00:02:00

check "the radios use the CN regulatory domain from first boot" \
	"[ \"\$(uci get wireless.radio0.country)\" = CN ] && [ \"\$(uci get wireless.radio1.country)\" = CN ] && iw reg get | grep -q 'country CN'"
check "only radios that exist are listed" \
	"ubus call supacudy wifi_get | tr -d '\n\t ' | grep -q '\"name\":\"radio0\",\"band\":\"2g\"' &&
	 ubus call supacudy wifi_get | tr -d '\n\t ' | grep -q '\"name\":\"radio1\",\"band\":\"5g\"' &&
	 ! ubus call supacudy wifi_get | grep -q radio2"
# CN allows 36-64 (52-64 with radar detection) and 149-165; 160 MHz fits 36-64 only.
check "5 GHz offers the CN channels and the widths they allow" \
	"ubus call supacudy wifi_get | tr -d '\n\t ' | grep -q '\"band\":\"5g\",[^}]*\"channels\":\[36,40,44,48,52,56,60,64,149,153,157,161,165\],[^}]*\"widths\":\[20,40,80,160\]'"

check "renaming the 5 GHz network reaches the radio" "
	ubus call supacudy wifi_set '{$RADIO1,\"ssid\":\"Emu-Renamed\",\"encryption\":\"sae-mixed\",\"key\":\"supacudy-wifi\"}' | grep -q applied
	for i in 1 2 3 4 5 6 7 8 9 10; do iw dev phy1-ap0 info 2>/dev/null | grep -q 'ssid Emu-Renamed' && exit 0; sleep 2; done; exit 1"
check "WPA3 mixed mode turns on management frame protection" \
	"[ \"\$(uci get wireless.default_radio1.ieee80211w)\" = 1 ]"
check "channel, width and power reach the radio" "
	ubus call supacudy wifi_set '{\"radio\":\"radio1\",\"enabled\":true,\"channel\":\"40\",\"width\":80,\"txpower\":\"medium\",\"hidden\":false,\"ssid\":\"SupaCudy-Emu-5G\",\"encryption\":\"psk2\",\"key\":\"supacudy-wifi\"}' | grep -q applied
	for i in 1 2 3 4 5 6 7 8 9 10; do iw dev phy1-ap0 info 2>/dev/null | grep -q 'width: 80 MHz' && break; sleep 2; done
	iw dev phy1-ap0 info | grep -q 'channel 40' && iw dev phy1-ap0 info | grep -q 'txpower 17.00 dBm' &&
	ubus call supacudy wifi_get | tr -d '\n\t ' | grep -q '\"band\":\"5g\",[^}]*\"txpower\":\"medium\"'"
check "5 GHz is restored" \
	"ubus call supacudy wifi_set '{$RADIO1,\"ssid\":\"SupaCudy-Emu-5G\",\"encryption\":\"psk2\",\"key\":\"supacudy-wifi\"}' | grep -q applied"

check "a channel outside the regulatory list is refused" \
	"ubus call supacudy wifi_set '{\"radio\":\"radio1\",\"enabled\":true,\"channel\":\"100\",\"width\":20,\"txpower\":\"max\",\"hidden\":false,$MAIN_KEY}' | grep -q channel_unavailable"
check "a width the chosen channel cannot carry is refused" \
	"ubus call supacudy wifi_set '{\"radio\":\"radio1\",\"enabled\":true,\"channel\":\"149\",\"width\":160,\"txpower\":\"max\",\"hidden\":false,$MAIN_KEY}' | grep -q width_unavailable"
check "160 MHz is accepted on a channel whose block allows it" \
	"ubus call supacudy wifi_set '{\"radio\":\"radio1\",\"enabled\":true,\"channel\":\"36\",\"width\":160,\"txpower\":\"max\",\"hidden\":false,$MAIN_KEY}' | grep -q applied &&
	 uci get wireless.radio1.htmode | grep -q '160\$' &&
	 ubus call supacudy wifi_set '{$RADIO1,\"ssid\":\"SupaCudy-Emu-5G\",\"encryption\":\"psk2\",\"key\":\"supacudy-wifi\"}' | grep -q applied"
check "a short password is refused" \
	"ubus call supacudy wifi_set '{$RADIO0,\"ssid\":\"x\",\"encryption\":\"psk2\",\"key\":\"short\"}' | grep -q key_invalid"
check "an over-long SSID is refused" \
	"ubus call supacudy wifi_set '{$RADIO0,\"ssid\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"encryption\":\"psk2\",\"key\":\"12345678\"}' | grep -q ssid_length"
check "an unknown radio reports not found" \
	"! ubus call supacudy wifi_set '{\"radio\":\"radio9\",\"enabled\":true,\"channel\":\"auto\",\"width\":20,\"txpower\":\"max\",\"hidden\":false,$MAIN_KEY}'"

check "changing the password disconnects the phone" "
	ubus call supacudy wifi_set '{$RADIO0,\"ssid\":\"SupaCudy-Emu\",\"encryption\":\"psk2\",\"key\":\"another-password\"}' | grep -q applied
	for i in \$(seq 15); do iw dev phy0-ap0 station dump | grep -q '$PHONE' || exit 0; sleep 2; done; exit 1"
check "restoring the password lets the phone back in" "
	ubus call supacudy wifi_set '{$RADIO0,$MAIN_KEY}' | grep -q applied
	for i in \$(seq 20); do iw dev phy0-ap0 station dump 2>/dev/null | grep -q '$PHONE' && exit 0; sleep 2; done; exit 1"

check "enabling the guest network creates its own subnet" "
	ubus call supacudy guest_set '{\"enabled\":true,$GUEST}' | grep -q '192.168.201.0/24'
	for i in \$(seq 15); do ip -4 addr show br-guest 2>/dev/null | grep -q 192.168.201.1/24 && exit 0; sleep 2; done; exit 1"
eventually "a visitor joins the guest network and gets a guest address" \
	"$IN_VISITOR ip -4 addr show vi0 | grep -q 'inet 192.168.201.'"
check "the visitor appears as a guest client" \
	"ubus call supacudy clients_list | tr -d '\n\t ' | grep -q '\"hostname\":\"Guest-Tablet\",[^}]*\"network\":\"guest\"'"
check "the visitor can use the internet" "$IN_VISITOR ping -c1 -W3 1.1.1.1"
check "the visitor can resolve names through the router" "$IN_VISITOR nslookup example.com 192.168.201.1"
check "the visitor cannot reach the laptop on the LAN" "! $IN_VISITOR ping -c1 -W3 192.168.200.113"
check "the visitor cannot open the admin page" \
	"! $IN_VISITOR wget -q -O /dev/null -T 3 http://192.168.201.1/supacudy/ && ! $IN_VISITOR wget -q -O /dev/null -T 3 http://192.168.200.1/supacudy/"
check "disabling the guest network drops the visitor" "
	ubus call supacudy guest_set '{\"enabled\":false,$GUEST}' | grep -q applied
	for i in \$(seq 15); do ! iw dev | grep -q 'ssid SupaCudy-Guest' && exit 0; sleep 2; done; exit 1"
