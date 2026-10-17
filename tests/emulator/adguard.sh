#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for AdGuard Home as the router's DNS. Blocking is checked
# with rules and a list served by the router itself, so no internet is
# needed. Sourced by run.sh.

LAPTOP="ip netns exec laptop"
TICK="ucode /usr/libexec/supacudy/rescue.uc"
GET="ubus call supacudy adguard_get"
LIST="http://127.0.0.1/ag-test-list.txt"
ADMIN="supacudy-test"
bcrypt() { (cd "$ROOT/web" && node -e 'import("bcryptjs").then((b) => console.log(b.default.hashSync(process.argv[1], 10)))' "$1"); }
ADMIN_HASH="$(bcrypt "$ADMIN")"
NEW_HASH="$(bcrypt emu-new-pass)"
NATIVE="curl -s -f -m 5 -u root:$ADMIN http://192.168.200.1:3000/control"
lookup() { echo "$LAPTOP nslookup $1 192.168.200.1 | grep Address | tail -1"; }
LOCAL_API="curl -s -f -m 5 -K /etc/supacudy/adguard.curl http://127.0.0.1:3000/control"
logging() { echo "ubus call supacudy adguard_logging_set '{\"statistics\":$1,\"querylog\":$2}' | grep -q applied"; }
logging_is() {
	echo "$GET | jsonfilter -e @.logging.statistics | grep -qx $1 && $GET | jsonfilter -e @.logging.querylog | grep -qx $2 &&
		$LOCAL_API/stats/config | jsonfilter -e @.enabled | grep -qx $1 && $LOCAL_API/querylog/config | jsonfilter -e @.enabled | grep -qx $2"
}

check "AdGuard Home is set up on first boot" \
	"[ \"\$(uci get supacudy.adguard.enabled)\" = 1 ] && [ \"\$(uci get dhcp.@dnsmasq[0].port)\" = 5353 ] &&
	 uci get dhcp.lan.dhcp_option | grep -q '6,0.0.0.0' && [ -f /etc/adguardhome.yaml ]"
eventually "AdGuard Home answers on port 53 and dnsmasq behind it" \
	"netstat -lnup | grep -q ':53 .*AdGuardHome' && netstat -lnup | grep -q ':5353 .*dnsmasq' &&
	 $GET | jsonfilter -e @.running | grep -q true"
check "its settings are read from AdGuard Home itself" \
	"$GET | jsonfilter -e @.protection | grep -q true && $GET | jsonfilter -e '@.filters[0].url' | grep -q filter_1.txt &&
	 ! uci -q get supacudy.adguard.protection"
# AdGuard Home rewrites the file in its own key order, so the whole section is read.
yaml_section_off() { echo "sed -n '/^$1:/,/^[a-z]/p' /etc/adguardhome.yaml | grep -qx '  enabled: false'"; }
check "statistics and the query log start off" "$(logging_is false false) && $(yaml_section_off querylog) && $(yaml_section_off statistics)"
check "a logging change with a missing switch is rejected as invalid" \
	"! ubus call supacudy adguard_logging_set '{\"statistics\":true}' && ! ubus call supacudy adguard_logging_set '{\"statistics\":1,\"querylog\":false}'"
check "statistics are turned on and the query log stays off" "$(logging true false) && $(logging_is true false)"
check "the query log is turned on, keeping the retention AdGuard Home had" \
	"before=\$($LOCAL_API/querylog/config | jsonfilter -e @.interval) && $(logging true true) && $(logging_is true true) &&
	 [ \"\$($LOCAL_API/querylog/config | jsonfilter -e @.interval)\" = \"\$before\" ]"
check "both are turned off again" "$(logging false false) && $(logging_is false false)"
check "a test host name is added" \
	"ubus call supacudy host_set '{\"id\":\"\",\"name\":\"ads.test\",\"ip\":\"192.168.200.77\"}' | jsonfilter -e @.id > /tmp/ag-host"
eventually "LAN devices resolve local names through AdGuard Home" "$(lookup ads.test) | grep -q 192.168.200.77"

check "a malformed rule is refused" \
	"ubus call supacudy adguard_rules_set '{\"rules\":[\"bad\\nrule\"]}' | grep -q rule_invalid"
check "a rules list that is not a list is rejected as invalid" "! ubus call supacudy adguard_rules_set '{\"rules\":\"x\"}'"
check "a blocking rule is added" "ubus call supacudy adguard_rules_set '{\"rules\":[\"||ads.test^\"]}' | grep -q applied"
check "AdGuard Home reports the rule" "$GET | jsonfilter -e '@.rules[0]' | grep -qx '||ads.test^'"
eventually "the name is blocked for LAN devices" "$(lookup ads.test) | grep -q 0.0.0.0"
check "blocking is paused" "ubus call supacudy adguard_protection '{\"enabled\":false}' | grep -q applied"
check "AdGuard Home reports the pause" "$GET | jsonfilter -e @.protection | grep -q false"
eventually "the name resolves while paused" "$(lookup ads.test) | grep -q 192.168.200.77"
check "blocking is resumed" "ubus call supacudy adguard_protection '{\"enabled\":true}' | grep -q applied"

check "a list address that is not http(s) is refused" \
	"ubus call supacudy adguard_list_add '{\"url\":\"ftp://h/x\",\"name\":\"x\"}' | grep -q filter_url_invalid"
check "a list that cannot be downloaded is refused" \
	"ubus call supacudy adguard_list_add '{\"url\":\"http://127.0.0.1/missing.txt\",\"name\":\"missing\"}' | grep -q adguard_refused"
check "a list is added" \
	"echo '||listed.test^' > /www/ag-test-list.txt &&
	 ubus call supacudy adguard_list_add '{\"url\":\"$LIST\",\"name\":\"Local test\"}' | grep -q applied &&
	 $GET | jsonfilter -e '@.filters[@.url=\"$LIST\"].rules' | grep -qx 1"
eventually "names on the list are blocked" "$(lookup listed.test) | grep -q 0.0.0.0"
check "the list is turned off" \
	"ubus call supacudy adguard_list_set '{\"url\":\"$LIST\",\"name\":\"Local test\",\"enabled\":false}' | grep -q applied &&
	 $GET | jsonfilter -e '@.filters[@.url=\"$LIST\"].enabled' | grep -q false"
check "the list is removed" \
	"ubus call supacudy adguard_list_remove '{\"url\":\"$LIST\"}' | grep -q applied &&
	 ! $GET | grep -q ag-test-list && rm /www/ag-test-list.txt"

check "AdGuard Home got the factory login root on first boot" \
	"[ -s /etc/supacudy/default-password ] && grep -q '^  - name: root' /etc/adguardhome.yaml && [ -s /etc/supacudy/adguard.bcrypt ]"
check "the emulator's own password is not reported as the factory one" \
	"ubus call supacudy setup_status | jsonfilter -e @.default_password | grep -q false"
check "AdGuard Home is out of step with the admin password changed by passwd" \
	"$GET | jsonfilter -e @.web.synced | grep -q false"
check "opening the page without the password is refused while out of step" \
	"ubus call supacudy adguard_web_set '{\"enabled\":true,\"password\":\"\",\"hash\":\"\"}' | grep -q password_needed"
check "a malformed hash is rejected" \
	"! ubus call supacudy adguard_web_set '{\"enabled\":true,\"password\":\"$ADMIN\",\"hash\":\"plain\"}'"
check "the AdGuard Home page is turned on with the admin password" \
	"ubus call supacudy adguard_web_set '{\"enabled\":true,\"password\":\"$ADMIN\",\"hash\":\"$ADMIN_HASH\"}' | grep -q applied"
eventually "LAN devices reach the page as root with the admin password, and need it" \
	"$LAPTOP $NATIVE/status | grep -q '\"running\":true' &&
	 [ \"\$($LAPTOP curl -s -o /dev/null -w '%{http_code}' -m 5 http://192.168.200.1:3000/control/status)\" -ge 401 ]"
check "the login is kept for root only and the password is not in the YAML" \
	"ls -l /etc/supacudy/adguard.curl | grep -q '^-rw-------' && ! grep -q '$ADMIN' /etc/adguardhome.yaml &&
	 $GET | jsonfilter -e @.web.synced | grep -q true && $GET | jsonfilter -e @.running | grep -q true"
check "a change made on AdGuard Home's page shows up here" \
	"$LAPTOP $NATIVE/filtering/set_rules -H 'Content-Type: application/json' -d '{\"rules\":[\"||native.test^\"]}' &&
	 $GET | jsonfilter -e '@.rules[0]' | grep -qx '||native.test^'"
check "a change made here still works with the login" "ubus call supacudy adguard_rules_set '{\"rules\":[]}' | grep -q applied"
check "changing the admin password without a hash is rejected" \
	"! ubus call supacudy password_set '{\"password\":\"emu-new-pass\"}'"
check "changing the admin password changes AdGuard Home's too" \
	"ubus call supacudy password_set '{\"password\":\"emu-new-pass\",\"hash\":\"$NEW_HASH\"}' | grep -q changed"
eventually "AdGuard Home takes the new password and refuses the old one" \
	"$LAPTOP curl -s -f -m 5 -u root:emu-new-pass http://192.168.200.1:3000/control/status | grep -q running &&
	 ! $LAPTOP $NATIVE/status && $GET | jsonfilter -e @.web.synced | grep -q true"
check "the admin password is changed back" \
	"ubus call supacudy password_set '{\"password\":\"$ADMIN\",\"hash\":\"$ADMIN_HASH\"}' | grep -q changed"
check "the AdGuard Home page is turned off" \
	"ubus call supacudy adguard_web_set '{\"enabled\":false,\"password\":\"\",\"hash\":\"\"}' | grep -q applied"
eventually "the page is no longer reachable from the LAN and settings still read" \
	"! $LAPTOP curl -s -m 3 http://192.168.200.1:3000/ && $GET | jsonfilter -e @.web.enabled | grep -q false &&
	 $GET | jsonfilter -e @.running | grep -q true"
check "it opens again without asking for the password" \
	"ubus call supacudy adguard_web_set '{\"enabled\":true,\"password\":\"\",\"hash\":\"\"}' | grep -q applied &&
	 ubus call supacudy adguard_web_set '{\"enabled\":false,\"password\":\"\",\"hash\":\"\"}' | grep -q applied"

# Removing the procd service drops its "restart when an interface comes
# up" trigger too, so it stays down like a crashed daemon.
check "AdGuard Home stops working" \
	"/etc/init.d/supacudy-rescue stop && ubus call service delete '{\"name\":\"adguardhome\"}' && sleep 6 &&
	 ! pgrep -f '[A]dGuardHome -c'"
check "nothing is guessed while it is down" \
	"$GET | grep -q '\"protection\": null' && $GET | grep -q '\"filters\": null'"
check "a change is refused while it is down" \
	"ubus call supacudy adguard_protection '{\"enabled\":true}' | grep -q adguard_not_running"
check "two checks later the fallback answers DNS" \
	"$TICK && $TICK && $GET | jsonfilter -e @.fallback | grep -q true && $(lookup ads.test) | grep -q 192.168.200.77"
check "the fallback brings AdGuard Home back after a while" \
	"for i in 1 2 3 4 5 6 7 8 9 10; do $TICK; done; sleep 6; $TICK; $TICK; $TICK;
	 netstat -lnup | grep -q ':53 .*AdGuardHome' && $GET | jsonfilter -e @.fallback | grep -q false &&
	 /etc/init.d/supacudy-rescue start"

check "AdGuard Home is turned off" "ubus call supacudy adguard_set '{\"enabled\":false}' | grep -q applied"
eventually "dnsmasq answers on port 53 again" \
	"! pgrep -f '[A]dGuardHome -c' && ! uci -q get dhcp.@dnsmasq[0].port && ! uci -q get dhcp.lan.dhcp_option &&
	 netstat -lnup | grep -q ':53 .*dnsmasq' && $(lookup ads.test) | grep -q 192.168.200.77"
check "AdGuard Home is turned back on" "ubus call supacudy adguard_set '{\"enabled\":true}' | grep -q applied"
eventually "it answers again" "netstat -lnup | grep -q ':53 .*AdGuardHome'"
check "the test host name is removed" \
	"ubus call supacudy host_delete \"{\\\"id\\\":\\\"\$(cat /tmp/ag-host)\\\"}\" | grep -q deleted"
