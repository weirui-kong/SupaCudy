#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for system settings and maintenance: time zone, admin
# password, firmware uploads through cgi-io with its ACL, and a real reboot.
# Sourced by run.sh; the reboot runs last because it resets the VM.

BASE="http://127.0.0.1:$EMU_HTTP_PORT"
PASSWORD=supacudy-test
UPLOAD="$(mktemp)"
trap 'rm -f "$UPLOAD"' RETURN
head -c 200000 /dev/urandom > "$UPLOAD"
# The UI sends AdGuard Home a bcrypt hash of every new admin password.
hash_of() { (cd "$ROOT/web" && node -e 'import("bcryptjs").then((b) => console.log(b.default.hashSync(process.argv[1], 10)))' "$1"); }
TEMP_HASH="$(hash_of temporary-pass)"
ADMIN_HASH="$(hash_of "$PASSWORD")"

rpc() {
	local args="${4:-}"
	curl -s --max-time 20 "$BASE/ubus" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"$1\",\"$2\",\"$3\",${args:-"{}"}]}"
}
session() {
	rpc 00000000000000000000000000000000 session login "{\"username\":\"root\",\"password\":\"$1\"}" |
		python3 -I -c 'import json, sys; print(json.load(sys.stdin)["result"][1]["ubus_rpc_session"])' 2>/dev/null
}
upload() {
	curl -s --max-time 30 -F "sessionid=$1" -F "filename=$2" -F filemode=0600 -F "filedata=@$UPLOAD" "$BASE/cgi-bin/cgi-upload"
}

check "the time zone is applied to the system" \
	"ubus call supacudy time_set '{\"zonename\":\"Asia/Shanghai\",\"ntp\":true,\"time\":0}' | grep -q applied &&
	 [ \"\$(uci get system.@system[0].timezone)\" = CST-8 ] &&
	 for i in \$(seq 10); do date | grep -q CST && exit 0; sleep 1; done; exit 1"
check "time_get lists the zones and the chosen one" \
	"ubus call supacudy time_get | grep -q '\"zonename\": \"Asia/Shanghai\"' && ubus call supacudy time_get | grep -q 'Europe/Berlin'"
check "the clock can be set from the browser" \
	"ubus call supacudy time_set '{\"zonename\":\"UTC\",\"ntp\":false,\"time\":1893456000}' | grep -q applied &&
	 [ \"\$(date +%Y)\" = 2030 ] && [ \"\$(uci get system.ntp.enabled)\" = 0 ]"
check "an unknown time zone is rejected as invalid" \
	"! ubus call supacudy time_set '{\"zonename\":\"Mars/Base\",\"ntp\":true,\"time\":0}'"
check "an implausible clock is rejected as invalid" \
	"! ubus call supacudy time_set '{\"zonename\":\"UTC\",\"ntp\":true,\"time\":12345}'"
check "NTP and the zone are restored" \
	"ubus call supacudy time_set '{\"zonename\":\"UTC\",\"ntp\":true,\"time\":$(date +%s)}' | grep -q applied"

check "a short admin password is refused" \
	"ubus call supacudy password_set '{\"password\":\"short\",\"hash\":\"$TEMP_HASH\"}' | grep -q password_invalid"
check "the admin password is changed" \
	"ubus call supacudy password_set '{\"password\":\"temporary-pass\",\"hash\":\"$TEMP_HASH\"}' | grep -q changed"
if [ -n "$(session temporary-pass)" ] && [ -z "$(session "$PASSWORD")" ]; then ok "the new password logs in and the old one no longer does"; else not_ok "the new password logs in and the old one no longer does"; fi
check "the admin password is restored" \
	"ubus call supacudy password_set '{\"password\":\"$PASSWORD\",\"hash\":\"$ADMIN_HASH\"}' | grep -q changed"

SID="$(session "$PASSWORD")"
if upload "$SID" /tmp/firmware.bin | grep -q '"size": 200000'; then ok "the UI session can upload the firmware file"; else not_ok "the UI session can upload the firmware file"; fi
if upload "$SID" /etc/shadow | grep -q "denied by ACL"; then ok "uploads to any other path are refused by the ACL"; else not_ok "uploads to any other path are refused by the ACL"; fi
if upload 00000000000000000000000000000000 /tmp/firmware.bin | grep -q "permission denied"; then ok "anonymous uploads are refused"; else not_ok "anonymous uploads are refused"; fi
check "random data is not accepted as firmware" \
	"ubus call supacudy firmware_check | grep -q '\"valid\": false' &&
	 ubus call supacudy firmware_upgrade '{\"keep_settings\":true}' | grep -q firmware_invalid"
check "discarding removes the upload" \
	"ubus call supacudy firmware_discard | grep -q true && [ ! -e /tmp/firmware.bin ] && ! ubus call supacudy firmware_check"
if rpc 00000000000000000000000000000000 supacudy reboot | grep -q '"code":-32002'; then ok "anonymous callers cannot reboot"; else not_ok "anonymous callers cannot reboot"; fi
if curl -s --max-time 10 "$BASE/cgi-bin/supacudy-whoami" | grep -q '"ip":"10.250.3.2"'; then
	ok "the UI can learn its own address"
else
	not_ok "the UI can learn its own address"
fi
rpc "$SID" session destroy >/dev/null

if rpc 00000000000000000000000000000000 supacudy setup_status | grep -q '"password_set":true,"default_password":false'; then
	ok "the first-run status is readable before login"
else
	not_ok "the first-run status is readable before login"
fi
if rpc 00000000000000000000000000000000 supacudy status | grep -q '"code":-32002'; then
	ok "nothing else is readable before login"
else
	not_ok "nothing else is readable before login"
fi
CPU_MAX=/sys/fs/cgroup/services/cpu.max
cpu_max_for() { echo "[ \"\$(cat $CPU_MAX)\" = \"\$(($1 * \$(grep -c '^processor' /proc/cpuinfo) * 1000)) 100000\" ]"; }
cpu_limit() { echo "ubus call supacudy cpu_limit_set '{\"limit\":$1}' | grep -q applied"; }
# CPU time all programs used during 4 s with two busy loops, in percent of one core.
BUSY_USAGE="u() { sed -n 's/^usage_usec //p' /sys/fs/cgroup/services/cpu.stat; };
	(while :; do :; done) & a=\$!; (while :; do :; done) & b=\$!; sleep 1; s=\$(u); sleep 4; e=\$(u); kill \$a \$b;
	echo \$(( (e - s) / 40000 ))"
check "the status reports each temperature sensor, as null since the VM has none" \
	"ubus call supacudy status | tr -d '\n\t ' | grep -q '\"temperature\":{\"cpu\":null,\"wifi\":null}'"
check "programs may use 80% of the CPU out of the box" \
	"ubus call supacudy cpu_limit_get | jsonfilter -e @.limit | grep -qx 80 && $(cpu_max_for 80) &&
	 grep -qw cpu /sys/fs/cgroup/cgroup.subtree_control"
eventually "a program started outside the services is moved under the limit" \
	"sh -c 'echo \$\$ > /sys/fs/cgroup/cgroup.procs; exec sleep 30' & pid=\$!; sleep 7;
	 grep -qx \$pid /sys/fs/cgroup/services/supacudy-other/cgroup.procs; found=\$?; kill \$pid; [ \$found = 0 ]"
check "a limit that is not offered is rejected as invalid" "! ubus call supacudy cpu_limit_set '{\"limit\":42}'"
check "the limit is set to 30%" "$(cpu_limit 30)"
eventually "the cap follows" "$(cpu_max_for 30)"
check "two busy programs get 30% of the CPU together" "[ \$($BUSY_USAGE) -le 65 ]"
check "without a limit they get both cores" "$(cpu_limit 100) && sleep 2 && grep -qx 'max 100000' $CPU_MAX && [ \$($BUSY_USAGE) -ge 150 ]"
check "the limit is back at 80%" "$(cpu_limit 80)"
eventually "the cap follows again" "$(cpu_max_for 80)"
if rpc 00000000000000000000000000000000 supacudy cpu_limit_set '{"limit":100}' | grep -q '"code":-32002'; then
	ok "anonymous callers cannot change the CPU limit"
else
	not_ok "anonymous callers cannot change the CPU limit"
fi

check "finishing setup is stored" \
	"ubus call supacudy setup_complete | grep -q true && [ \"\$(uci get supacudy.main.setup_done)\" = 1 ] &&
	 ubus call supacudy setup_status | grep -q '\"setup_done\": true'"

check "a reboot is accepted" "ubus call supacudy reboot | grep -q rebooting"
sleep 15
eventually "the router comes back after the reboot" "[ \"\$(cut -d. -f1 /proc/uptime)\" -lt 300 ]"
eventually "the CPU limit is applied again after the reboot" "$(cpu_max_for 80)"
