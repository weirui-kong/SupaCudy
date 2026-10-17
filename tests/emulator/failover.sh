#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for uplink failover between the Ethernet WAN (with an
# emulated delegated IPv6 prefix) and USB tethering (IPv6 without one).
# The checks run the watcher's ticks themselves instead of waiting for its
# 10 s period. An outage is simulated by dropping the router's own probes on
# eth0, so the link stays up but "the internet" stops answering. The probe
# targets are the uplinks' QEMU gateways. Sourced by run.sh.

TICK="flock /var/run/supacudy-failover.lock ucode /usr/libexec/supacudy/failover.uc"
STATE=/var/run/supacudy/failover.json
LAPTOP="ip netns exec laptop"
TARGETS='"targets4":["10.250.2.2","10.250.42.2"],"targets6":["2001:db8:2::2","2001:db8:42::2"]'
active() { echo "[ \"\$(jsonfilter -i $STATE -e @.active_v4)\" = '$1' ] && [ \"\$(jsonfilter -i $STATE -e @.active_v6)\" = '$2' ]"; }
ticks() { echo "for i in \$(seq $1); do $TICK; done"; }
# Rules for the simulated outage, one device per argument.
block() {
	local cmd="nft delete table inet emu_fault 2>/dev/null; nft add table inet emu_fault &&
		nft add chain inet emu_fault out '{ type filter hook output priority 0; policy accept; }'"
	for dev in "$@"; do
		cmd="$cmd && nft add rule inet emu_fault out oifname $dev icmp type echo-request drop &&
			nft add rule inet emu_fault out oifname $dev icmpv6 type echo-request drop"
	done
	echo "$cmd"
}
block_v6() {
	local cmd="nft delete table inet emu_fault 2>/dev/null; nft add table inet emu_fault &&
		nft add chain inet emu_fault out '{ type filter hook output priority 0; policy accept; }'"
	for dev in "$@"; do
		cmd="$cmd && nft add rule inet emu_fault out oifname $dev icmpv6 type echo-request drop"
	done
	echo "$cmd"
}
UNBLOCK="nft delete table inet emu_fault 2>/dev/null; true"

check "Ethernet gets the base metric that keeps it ahead of the other uplinks" \
	"[ \"\$(uci get network.wan.metric)\" = 10 ] && ip route show default | grep -q 'dev eth0 .*metric 10'"
check "an order that leaves out an uplink is rejected as invalid" \
	"! ubus call supacudy uplinks_set '{\"order\":[\"wired\",\"tethering\"],\"reset_connections\":true,$TARGETS}'"
check "a probe target that is not an address is refused" \
	"ubus call supacudy uplinks_set '{\"order\":[\"wired\",\"repeater\",\"tethering\"],\"reset_connections\":true,\"targets4\":[\"example.com\"],\"targets6\":[\"2001:db8:2::2\"]}' | grep -q target_invalid"
check "the watcher is stopped so the checks drive it" \
	"/etc/init.d/supacudy-failover stop && rm -f $STATE /etc/supacudy/failover-orig.json"
check "probe targets inside the emulator are set" \
	"ubus call supacudy uplinks_set '{\"order\":[\"wired\",\"repeater\",\"tethering\"],\"reset_connections\":true,$TARGETS}' | grep -q applied"
check "tethering is turned on, with IPv6" \
	"ubus call supacudy tethering_set '{\"enabled\":true}' | grep -q applied &&
	 [ \"\$(uci get network.tethering6.proto)\" = dhcpv6 ] && [ \"\$(uci get network.tethering6.device)\" = @tethering ]"
eventually "tethering has IPv4 and IPv6 without a delegated prefix" \
	"ifstatus tethering | jsonfilter -e '@[\"ipv4-address\"][0].address' | grep -q '^10.250.42.' &&
	 ifstatus tethering6 | jsonfilter -e '@[\"ipv6-address\"][0].address' | grep -q '^2001:db8:42:' &&
	 ifstatus tethering6 | jsonfilter -e '@.route[@.mask=0].nexthop' | grep -q ."
eventually "Ethernet has IPv6 and the delegated prefix reaches the laptop" \
	"ifstatus wan6 | jsonfilter -e '@[\"ipv6-prefix\"][0].address' | grep -q '^2001:db8:250::' &&
	 $LAPTOP ip -6 addr show dev eth0 | grep -q 'inet6 2001:db8:250:'"

# Turning tethering on reloads the network; checks run until it settles.
eventually "the first checks use Ethernet for both IPv4 and IPv6" \
	"$TICK && $(active wired wired) && ip -4 route show default proto 99 | grep -q 'dev eth0 .*metric 5' &&
	 ip -6 route show default proto 99 | grep -q 'dev eth0' && ! uci -q get network.lan.ip6class &&
	 ! nft list table ip6 supacudy_nat66"
check "the internet status reports Ethernet from the watcher" \
	"ubus call supacudy internet_status | jsonfilter -e @.active | grep -qx wan &&
	 ubus call supacudy uplinks_get | jsonfilter -e '@.uplinks[0].v6.online' | grep -q true"

eventually "tethering is a working standby for IPv4 and IPv6" \
	"$TICK && [ \"\$(jsonfilter -i $STATE -e @.uplinks.tethering.v4.ok)\" = true ] &&
	 [ \"\$(jsonfilter -i $STATE -e @.uplinks.tethering.v6.ok)\" = true ]"
check "a connection through Ethernet is open" \
	"($LAPTOP ping -c 40 -i 0.5 10.250.2.2 >/dev/null 2>&1 </dev/null &) ; sleep 2;
	 conntrack -L -p icmp --reply-dst 10.250.2.15 2>/dev/null | grep -q 'dst=10.250.2.2'"
check "Ethernet stops reaching the internet" "$(block eth0)"
check "two failed checks are not enough to switch" "$(ticks 2) && $(active wired wired)"
check "the third one switches IPv4 and IPv6 to tethering" \
	"$TICK && $(active tethering tethering) && ip -4 route show default proto 99 | grep -q 'dev usb0 .*metric 5' &&
	 ip -6 route show default proto 99 | grep -q 'dev usb0'"
check "connections through Ethernet were reset" \
	"! conntrack -L -p icmp --reply-dst 10.250.2.15 2>/dev/null | grep -q 'dst=10.250.2.2'"
check "the LAN drops Ethernet's prefix and uses NAT66 on tethering" \
	"[ \"\$(uci get network.lan.ip6class)\" = local ] &&
	 nft list table ip6 supacudy_nat66 | grep -q 'oifname \"usb0\" ip6 saddr fc00::/7 masquerade'"
eventually "the laptop stops using the old prefix" \
	"$LAPTOP ip -6 addr show dev eth0 | grep -A1 'inet6 2001:db8:250:' | grep -q 'preferred_lft 0sec'"
eventually "the laptop reaches the internet through tethering over IPv4 and IPv6" \
	"$LAPTOP ping -c1 -W2 10.250.42.2 && $LAPTOP ping -6 -c1 -W2 2001:db8:42::2"
check "the internet status reports tethering" \
	"ubus call supacudy internet_status | jsonfilter -e @.active | grep -qx tethering"

check "Ethernet works again" "$UNBLOCK"
check "four good checks are not enough to switch back" "$(ticks 4) && $(active tethering tethering)"
check "the fifth one switches back and restores the LAN" \
	"$TICK && $(active wired wired) && ip -4 route show default proto 99 | grep -q 'dev eth0' &&
	 ! uci -q get network.lan.ip6class && ! nft list table ip6 supacudy_nat66 && [ ! -e /etc/supacudy/failover-orig.json ]"
eventually "the laptop uses Ethernet's prefix again" \
	"$LAPTOP ip -6 addr show dev eth0 | grep -A1 'inet6 2001:db8:250:' | grep -qv 'preferred_lft 0sec'"

check "resetting connections is turned off" \
	"ubus call supacudy uplinks_set '{\"order\":[\"wired\",\"repeater\",\"tethering\"],\"reset_connections\":false,$TARGETS}' | grep -q applied"
check "without the reset, connections through Ethernet survive a switch" \
	"($LAPTOP ping -c 40 -i 0.5 10.250.2.2 >/dev/null 2>&1 </dev/null &) ; sleep 2; $(block eth0) && $(ticks 3) && $(active tethering tethering) &&
	 conntrack -L -p icmp --reply-dst 10.250.2.15 2>/dev/null | grep -q 'dst=10.250.2.2'"
check "back to Ethernet" "$UNBLOCK && $(ticks 5) && $(active wired wired)"

check "IPv6 stops working everywhere while IPv4 keeps working" "$(block_v6 eth0 usb0) && $(ticks 3) && $(active wired '')"
check "the router stops offering itself as IPv6 gateway" \
	"[ \"\$(uci get dhcp.lan.ra_lifetime)\" = 0 ] && ! ip -6 route show default proto 99 | grep -q ."
eventually "the laptop drops its IPv6 default route" "! $LAPTOP ip -6 route | grep -q default"
check "IPv6 comes back" "$UNBLOCK && $(ticks 5) && $(active wired wired) && ! uci -q get dhcp.lan.ra_lifetime"
eventually "the laptop gets its IPv6 default route back" "$LAPTOP ip -6 route | grep -q default"

check "tethering is put first" \
	"ubus call supacudy uplinks_set '{\"order\":[\"tethering\",\"wired\",\"repeater\"],\"reset_connections\":true,$TARGETS}' | grep -q applied &&
	 $TICK && $(active tethering tethering)"
check "the original order is restored" \
	"ubus call supacudy uplinks_set '{\"order\":[\"wired\",\"repeater\",\"tethering\"],\"reset_connections\":true,$TARGETS}' | grep -q applied &&
	 $TICK && $(active wired wired)"

check "stopping the watcher undoes its routes" \
	"$TICK && $UNBLOCK && ucode /usr/libexec/supacudy/failover.uc stop && ! ip route show default proto 99 | grep -q . &&
	 ! ip -6 route show default proto 99 | grep -q . && [ ! -e $STATE ]"
check "the emulator's settings and the watcher are back" \
	"ubus call supacudy uplinks_set '{\"order\":[\"wired\",\"repeater\",\"tethering\"],\"reset_connections\":true,$TARGETS}' | grep -q applied &&
	 ubus call supacudy tethering_set '{\"enabled\":false}' | grep -q applied && /etc/init.d/supacudy-failover start"
eventually "the running watcher picks Ethernet" "[ -e $STATE ] && $(active wired wired)"
