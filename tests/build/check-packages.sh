#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build tests: inspect the .ipk files in out/packages/ without installing them.
#
#   tests/build/check-packages.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_DIR="$ROOT/out/packages"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
ok()     { echo "ok - $*"; }
not_ok() { echo "not ok - $*"; FAILED=1; }
check()  { local desc="$1"; shift; if "$@"; then ok "$desc"; else not_ok "$desc"; fi; }

unpack() {
	local name="$1" dir
	local matches=("$PKG_DIR/${name}"_*_all.ipk)
	local ipk="${matches[0]}"
	[ -f "$ipk" ] || return 1
	dir="$WORK/$name"
	mkdir -p "$dir/control" "$dir/data"
	tar -xzOf "$ipk" ./control.tar.gz | tar -xzf - -C "$dir/control"
	tar -xzOf "$ipk" ./data.tar.gz | tar -xzf - -C "$dir/data"
}

field()    { sed -n "s/^$2: //p" "$WORK/$1/control/control"; }
has_file() { [ -f "$WORK/$1/data/$2" ]; }
is_exec()  { [ -x "$WORK/$1/data/$2" ]; }
depends_on() {
	field "$1" Depends | tr ',' '\n' | sed 's/^ *//; s/ .*//' | grep -qx "$2"
}

for dir in "$ROOT"/packages/*/; do
	name="$(basename "$dir")"
	check "$name: .ipk was built" unpack "$name"
done

[ "$FAILED" = 0 ] || { echo "Missing packages; run scripts/build-packages.sh first." >&2; exit 1; }

for dir in "$ROOT"/packages/*/; do
	name="$(basename "$dir")"
	version="$(sed -n 's/^PKG_VERSION:=//p' "$dir/Makefile")"
	check "$name: architecture is 'all'" test "$(field "$name" Architecture)" = all
	check "$name: version matches Makefile ($version)" \
		bash -c "[[ '$(field "$name" Version)' == '$version'-r* ]]"
	check "$name: license is Apache-2.0" test "$(field "$name" License)" = Apache-2.0
done

check "base: depends on uhttpd"          depends_on supacudy-base uhttpd
check "base: depends on uhttpd-mod-ubus" depends_on supacudy-base uhttpd-mod-ubus
check "base: depends on rpcd"            depends_on supacudy-base rpcd
check "base: ships /etc/supacudy_version" has_file supacudy-base etc/supacudy_version
check "base: version file matches package version" \
	test "$(cat "$WORK/supacudy-base/data/etc/supacudy_version")" = "$(field supacudy-base Version)"
check "base: uci-defaults script is executable" is_exec supacudy-base etc/uci-defaults/90-supacudy

check "rpcd: depends on supacudy-base"   depends_on supacudy-rpcd supacudy-base
check "rpcd: depends on rpcd-mod-ucode"  depends_on supacudy-rpcd rpcd-mod-ucode
check "rpcd: ships the ucode plugin"     has_file supacudy-rpcd usr/share/rpcd/ucode/supacudy.uc
check "rpcd: ships the ACL"              has_file supacudy-rpcd usr/share/rpcd/acl.d/supacudy.json
check "rpcd: has a postinst that restarts rpcd" \
	grep -q 'rpcd restart' "$WORK/supacudy-rpcd/control/postinst-pkg"

acl_check="$(python3 -I - "$WORK/supacudy-rpcd/data/usr/share/rpcd/ucode/supacudy.uc" \
	"$WORK/supacudy-rpcd/data/usr/share/rpcd/acl.d/supacudy.json" <<'EOF'
import json, re, sys
plugin = open(sys.argv[1]).read()
try:
    acl = json.load(open(sys.argv[2]))
except ValueError as e:
    print("invalid JSON: %s" % e); sys.exit(0)
methods = set(re.findall(r'(\w+):\s*\{\s*(?:args:\s*\{[^}]*\}\s*,\s*)?call:', plugin))
granted = set()
for group in acl.values():
    for kind in ("read", "write"):
        granted |= set(group.get(kind, {}).get("ubus", {}).get("supacudy", []))
missing = sorted(methods - granted)
extra = sorted(granted - methods)
if not methods:
    print("no methods found in plugin")
elif missing or extra:
    print("missing from ACL: %s; in ACL but not defined: %s" % (missing, extra))
EOF
)"
check "rpcd: ACL is valid and matches plugin methods${acl_check:+ ($acl_check)}" test -z "$acl_check"

check "ui: depends on supacudy-rpcd"   depends_on supacudy-ui supacudy-rpcd
check "ui: depends on uhttpd-mod-ubus" depends_on supacudy-ui uhttpd-mod-ubus
check "ui: ships /www/supacudy/index.html" has_file supacudy-ui www/supacudy/index.html

for dir in "$ROOT"/packages/*/; do
	name="$(basename "$dir")"
	matches=("$PKG_DIR/${name}"_*_all.ipk)
	ipk="${matches[0]}"
	# tar -tv output differs between GNU tar and bsdtar, so read it in Python.
	owners="$(tar -xzOf "$ipk" ./data.tar.gz | python3 -I -c '
import sys, tarfile
with tarfile.open(fileobj=sys.stdin.buffer, mode="r|gz") as t:
    print(" ".join(sorted({"%d:%d" % (m.uid, m.gid) for m in t})))')"
	check "$name: all files owned by root (got: $owners)" test "$owners" = "0:0"
done

if [ "$FAILED" = 0 ]; then
	echo "build tests: PASS"
else
	echo "build tests: FAIL" >&2
	exit 1
fi
