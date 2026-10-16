#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Install the built packages into an official OpenWrt rootfs container
# (same OpenWrt version, native architecture of this machine) and check that
# the web UI can log in and call the SupaCudy API. No router needed. The
# packages are architecture independent, so a generic rootfs is enough.
#
#   scripts/smoke-test.sh            run the checks, then remove the container
#   scripts/smoke-test.sh --keep     leave it running at http://localhost:8080/supacudy/

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/config/openwrt.env"

case "$(uname -m)" in
	arm64|aarch64) IMAGE="openwrt/rootfs:armsr-armv8-${OPENWRT_VERSION}" ;;
	x86_64|amd64)  IMAGE="openwrt/rootfs:x86-64-${OPENWRT_VERSION}" ;;
	*) echo "Unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
esac
NAME="${SMOKE_NAME:-supacudy-smoke}"
PORT="${PORT:-8080}"
PASSWORD="supacudy-test"
KEEP="${1:-}"

if ! ls "$ROOT"/out/packages/*.ipk >/dev/null 2>&1; then
	echo "No packages in out/packages/. Run scripts/build-packages.sh first." >&2
	exit 1
fi

# The official arm64 rootfs images label their platform with the OpenWrt
# package architecture ("aarch64_generic") instead of "arm64", so a plain pull
# finds no match. Pull that entry by digest and tag it locally instead.
if [[ "$IMAGE" == *armsr-armv8* ]] && ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
	DIGEST="$(docker manifest inspect "$IMAGE" | python3 -I -c '
import json, sys
for m in json.load(sys.stdin)["manifests"]:
    if m["platform"]["architecture"] == "aarch64_generic":
        print(m["digest"])
')"
	[ -n "$DIGEST" ] || { echo "No aarch64 entry in $IMAGE" >&2; exit 1; }
	docker pull -q "${IMAGE%%:*}@$DIGEST" >/dev/null
	docker tag "${IMAGE%%:*}@$DIGEST" "$IMAGE"
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true
[ "$KEEP" = --keep ] || trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

echo "==> starting $IMAGE"
docker run -d --name "$NAME" -p "127.0.0.1:$PORT:80" \
	-v "$ROOT/out/packages:/supacudy:ro" \
	"$IMAGE" sleep infinity >/dev/null

docker exec -e PASSWORD="$PASSWORD" -e MIRROR="$OPENWRT_MIRROR" "$NAME" sh -euc '
	mkdir -p /var/lock /var/run /tmp/sysinfo
	echo "supacudy,smoke-test" > /tmp/sysinfo/board_name
	echo "SupaCudy smoke test" > /tmp/sysinfo/model

	sed -i "s#https://downloads.openwrt.org#${MIRROR%/}#" /etc/opkg/distfeeds.conf
	opkg update >/dev/null
	opkg install /supacudy/*.ipk >/dev/null
	# A syntax error would otherwise only show up as "Object not found".
	ucode -c -o /dev/null /usr/share/rpcd/ucode/supacudy.uc
	printf "%s\n%s\n" "$PASSWORD" "$PASSWORD" | passwd root >/dev/null

	# No procd in the container: start the daemons by hand.
	# Redirect output so docker exec does not wait on their stdout.
	/sbin/ubusd >/dev/null 2>&1 &
	sleep 1
	/sbin/rpcd >/dev/null 2>&1 &
	sleep 1
	/usr/sbin/uhttpd -p 0.0.0.0:80 -h /www -u /ubus >/dev/null 2>&1
'

URL="http://localhost:$PORT"
ANON=00000000000000000000000000000000

rpc() {
	local args="${4:-}"
	[ -n "$args" ] || args='{}'
	curl -fsS "$URL/ubus" -H 'Content-Type: application/json' \
		-d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"$1\",\"$2\",\"$3\",$args]}"
}

# rpcd answers "permission denied" either as ubus status 6 or as a JSON-RPC
# "Access denied" error, depending on where the check fails.
denied() { grep -qE '"result":\[6\]|"code":-32002'; }

fail() { echo "FAIL: $*" >&2; exit 1; }

for _ in $(seq 20); do
	curl -fsS -o /dev/null "$URL/supacudy/" 2>/dev/null && break
	sleep 0.5
done

echo "==> GET /supacudy/"
curl -fsS "$URL/supacudy/" | grep -q '<title>SupaCudy</title>' || fail "UI page not served"

echo "==> session.login with a wrong password is rejected"
rpc "$ANON" session login '{"username":"root","password":"wrong"}' | denied ||
	fail "wrong password was not rejected"

echo "==> session.login"
SESSION="$(rpc "$ANON" session login "{\"username\":\"root\",\"password\":\"$PASSWORD\"}" |
	sed -n 's/.*"ubus_rpc_session":"\([0-9a-f]*\)".*/\1/p')"
[ -n "$SESSION" ] || fail "login failed"

echo "==> supacudy.info"
INFO="$(rpc "$SESSION" supacudy info)"
echo "    $INFO"
echo "$INFO" | grep -q "\"openwrt\":\"$OPENWRT_VERSION\"" || fail "unexpected supacudy.info result"
echo "$INFO" | grep -q '"version":"0\.' || fail "SupaCudy version missing"

echo "==> supacudy.status"
STATUS="$(rpc "$SESSION" supacudy status)"
echo "    $STATUS"
echo "$STATUS" | grep -qE '"uptime":[0-9]+' || fail "status has no uptime"
echo "$STATUS" | grep -qE '"load":\[[0-9.]+,[0-9.]+,[0-9.]+\]' || fail "status has no load averages"
echo "$STATUS" | grep -qE '"cpus":[1-9]' || fail "status has no CPU count"
echo "$STATUS" | grep -qE '"total":[1-9][0-9]+' || fail "status has no memory total"
echo "$STATUS" | grep -qE '"available":[0-9]+' || fail "status has no available memory"

echo "==> supacudy.status rejects undeclared arguments as invalid"
rpc "$SESSION" supacudy status '{"bogus":1}' | grep -q '"result":\[2\]' || fail "status accepted undeclared arguments"

echo "==> supacudy.status without a session is denied"
rpc "$ANON" supacudy status | denied || fail "anonymous status call was allowed"

echo "==> supacudy.info without a session is denied"
rpc "$ANON" supacudy info | denied || fail "anonymous call was allowed"

echo "PASS"
[ "$KEEP" = --keep ] && echo "Container left running: $URL/supacudy/ (root / $PASSWORD)"
exit 0
