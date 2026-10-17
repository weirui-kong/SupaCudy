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
check "base: first-boot defaults script is executable" is_exec supacudy-base etc/uci-defaults/91-supacudy-defaults
for f in etc/init.d/supacudy-rescue usr/libexec/supacudy/rescue-watch usr/libexec/supacudy/dhcp-probe; do
	check "base: $f is executable" is_exec supacudy-base "$f"
done
check "base: whoami CGI is executable" is_exec supacudy-base www/cgi-bin/supacudy-whoami
check "base: ships the tethering hotplug script" has_file supacudy-base etc/hotplug.d/net/30-supacudy-tethering
for dep in kmod-usb-net-rndis kmod-usb-net-cdc-ether kmod-usb-net-cdc-ncm kmod-usb-net-ipheth usbmuxd; do
	check "base: depends on $dep" depends_on supacudy-base "$dep"
done

check "rpcd: depends on supacudy-base"   depends_on supacudy-rpcd supacudy-base
check "rpcd: depends on rpcd-mod-ucode"  depends_on supacudy-rpcd rpcd-mod-ucode
check "rpcd: ships the ucode plugin"     has_file supacudy-rpcd usr/share/rpcd/ucode/supacudy.uc
for module in "$ROOT"/packages/supacudy-rpcd/files/usr/share/ucode/supacudy/*.uc; do
	check "rpcd: ships the $(basename "$module" .uc) module" \
		has_file supacudy-rpcd "usr/share/ucode/supacudy/$(basename "$module")"
done
check "rpcd: ships the ACL"              has_file supacudy-rpcd usr/share/rpcd/acl.d/supacudy.json
check "rpcd: has a postinst that restarts rpcd" \
	grep -q 'rpcd restart' "$WORK/supacudy-rpcd/control/postinst-pkg"

acl_check="$(python3 -I - "$WORK/supacudy-rpcd/data/usr/share/rpcd/acl.d/supacudy.json" \
	"$WORK/supacudy-rpcd/data/usr/share/rpcd/ucode/supacudy.uc" \
	"$WORK"/supacudy-rpcd/data/usr/share/ucode/supacudy/*.uc <<'EOF'
import json, re, sys
plugin = "".join(open(p).read() for p in sys.argv[2:])
try:
    acl = json.load(open(sys.argv[1]))
except ValueError as e:
    print("invalid JSON: %s" % e); sys.exit(0)
methods = set(re.findall(r'(\w+):\s*\{\s*(?:args:\s*(?:\{[^}]*\}|\w+)\s*,\s*)?call:', plugin))
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
check "rpcd: depends on luci-base (zoneinfo, cgi-io)" depends_on supacudy-rpcd luci-base
check "rpcd: depends on https-dns-proxy" depends_on supacudy-rpcd https-dns-proxy
check "rpcd: depends on wireguard-tools" depends_on supacudy-rpcd wireguard-tools
check "rpcd: depends on openvpn-mbedtls" depends_on supacudy-rpcd openvpn-mbedtls
check "rpcd: depends on ddns-scripts" depends_on supacudy-rpcd ddns-scripts
check "rpcd: depends on adguardhome" depends_on supacudy-rpcd adguardhome
check "rpcd: depends on curl for the AdGuard Home API" depends_on supacudy-rpcd curl
check "rpcd: depends on tailscale" depends_on supacudy-rpcd tailscale
check "rpcd: AdGuard Home first-boot script is executable" is_exec supacudy-rpcd etc/uci-defaults/92-supacudy-adguard
check "rpcd: before login only setup_status is readable" \
	python3 -I -c 'import json, sys
anon = json.load(open(sys.argv[1])).get("unauthenticated", {})
sys.exit(anon.get("read") != {"ubus": {"supacudy": ["setup_status"]}} or "write" in anon)' \
	"$WORK/supacudy-rpcd/data/usr/share/rpcd/acl.d/supacudy.json"
check "rpcd: file ACL only allows writing the firmware upload" \
	python3 -I -c 'import json, sys
acl = json.load(open(sys.argv[1]))["supacudy"]
files = {p: m for kind in ("read", "write") for p, m in acl.get(kind, {}).get("file", {}).items()}
sys.exit(files != {"/tmp/firmware.bin": ["write"]} or "file" in acl.get("read", {}))' \
	"$WORK/supacudy-rpcd/data/usr/share/rpcd/acl.d/supacudy.json"

check "ui: depends on supacudy-rpcd"   depends_on supacudy-ui supacudy-rpcd
check "ui: depends on uhttpd-mod-ubus" depends_on supacudy-ui uhttpd-mod-ubus
check "ui: ships /www/supacudy/index.html" has_file supacudy-ui www/supacudy/index.html
check "ui: ships the start page that opens SupaCudy" \
	bash -c "grep -q 'URL=supacudy/' '$WORK/supacudy-ui/data/www/supacudy-start.html'"
check "ui: start page script is executable" is_exec supacudy-ui etc/uci-defaults/93-supacudy-ui
check "ui: does not replace LuCI's /www/index.html" bash -c "[ ! -e '$WORK/supacudy-ui/data/www/index.html' ]"
ui_root="$WORK/supacudy-ui/data/www/supacudy"
check "ui: ships a JavaScript bundle" bash -c "ls '$ui_root'/assets/*.js >/dev/null 2>&1"
check "ui: ships a stylesheet" bash -c "ls '$ui_root'/assets/*.css >/dev/null 2>&1"
check "ui: index.html references assets relatively (served under /supacudy/)" \
	bash -c "grep -q 'src=\"./assets/' '$ui_root/index.html' && ! grep -q 'src=\"/assets/' '$ui_root/index.html'"
check "ui: no source maps or stray files" \
	bash -c "[ -z \"\$(find '$ui_root' -name '*.map' -o -name '.DS_Store' -o -name '._*')\" ]"
ui_gzip_bytes="$(find "$ui_root" -type f -exec gzip -9c {} \; | wc -c | tr -d ' ')"
check "ui: gzipped size within the 300 KB budget (got $((ui_gzip_bytes / 1024)) KB)" \
	test "$ui_gzip_bytes" -le $((300 * 1024))

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
