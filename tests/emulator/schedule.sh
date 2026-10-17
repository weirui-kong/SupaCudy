#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for schedules and parental controls. The parental window is
# built around the VM's current time so the result does not depend on when
# the tests run. Sourced by run.sh.

LAPTOP="ip netns exec laptop"
# Escaped for the JSON inside the double-quoted remote command.
ALL_DAYS='\"sun\",\"mon\",\"tue\",\"wed\",\"thu\",\"fri\",\"sat\"'
# Start an hour ago and end in an hour (wrapping at midnight as needed).
WINDOW="s=\$(date -d @\$((\$(date +%s) - 3600)) +%H:%M); e=\$(date -d @\$((\$(date +%s) + 3600)) +%H:%M)"
LATER="s=\$(date -d @\$((\$(date +%s) + 7200)) +%H:%M); e=\$(date -d @\$((\$(date +%s) + 10800)) +%H:%M)"
parental() {
	echo "$1; ubus call supacudy parental_set \"{\\\"id\\\":\\\"$2\\\",\\\"name\\\":\\\"Bedtime\\\",\\\"macs\\\":[\\\"02:5c:00:00:00:11\\\"],\\\"days\\\":[$ALL_DAYS],\\\"start\\\":\\\"\$s\\\",\\\"end\\\":\\\"\$e\\\",\\\"enabled\\\":true}\""
}

check "a weekly reboot is written to cron" "
	ubus call supacudy schedule_set '{\"kind\":\"reboot\",\"enabled\":true,\"days\":[\"mon\",\"thu\"],\"start\":\"04:15\",\"end\":\"\"}' | grep -q applied &&
	grep -qx '15 4 \* \* 1,4 /sbin/reboot' /etc/crontabs/root"
check "Wi-Fi off at night ends the next morning" "
	ubus call supacudy schedule_set '{\"kind\":\"wifi_off\",\"enabled\":true,\"days\":[\"sat\"],\"start\":\"23:30\",\"end\":\"07:00\"}' | grep -q applied &&
	grep -qx '30 23 \* \* 6 /sbin/wifi down' /etc/crontabs/root && grep -qx '0 7 \* \* 0 /sbin/wifi up' /etc/crontabs/root"
check "other crontab lines are kept" "
	echo '5 5 * * * /bin/true # mine' >> /etc/crontabs/root &&
	ubus call supacudy schedule_set '{\"kind\":\"reboot\",\"enabled\":false,\"days\":[\"mon\"],\"start\":\"04:15\",\"end\":\"\"}' | grep -q applied &&
	grep -q '# mine' /etc/crontabs/root && ! grep -q /sbin/reboot /etc/crontabs/root"
check "an invalid time is rejected" \
	"! ubus call supacudy schedule_set '{\"kind\":\"reboot\",\"enabled\":true,\"days\":[\"mon\"],\"start\":\"25:00\",\"end\":\"\"}'"
check "schedules are cleared" "
	ubus call supacudy schedule_set '{\"kind\":\"wifi_off\",\"enabled\":false,\"days\":[\"sat\"],\"start\":\"23:30\",\"end\":\"07:00\"}' | grep -q applied &&
	! grep -q supacudy /etc/crontabs/root && sed -i '/# mine/d' /etc/crontabs/root"

eventually "the laptop is online before parental controls" "$LAPTOP ping -c1 -W2 10.250.2.2"
check "a parental rule covering now is added" "$(parental "$WINDOW" '') | jsonfilter -e @.id > /tmp/parental-id"
eventually "the laptop is offline during the window" "! $LAPTOP ping -c1 -W2 10.250.2.2"
check "other devices stay online" "ip netns exec nas ping -c1 -W2 10.250.2.2"
check "the window moves to later today" "$(parental "$LATER" "\$(cat /tmp/parental-id)") | grep -q sc_parental"
eventually "the laptop is online outside the window" "$LAPTOP ping -c1 -W2 10.250.2.2"
check "the rule is deleted" \
	"ubus call supacudy parental_delete \"{\\\"id\\\":\\\"\$(cat /tmp/parental-id)\\\"}\" | grep -q deleted && ! uci show firewall | grep -q sc_parental"

check "software flow offloading is turned on" \
	"ubus call supacudy offload_set '{\"mode\":\"software\"}' | grep -q applied"
eventually "the firewall offloads established connections" "fw4 print | grep -q 'flow offload @ft'"
check "offloading is turned off" "ubus call supacudy offload_set '{\"mode\":\"off\"}' | grep -q applied"
eventually "nothing is offloaded any more" "! fw4 print | grep -q 'flow offload @ft'"
