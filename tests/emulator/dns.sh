#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for DNS modes. They check what dnsmasq and https-dns-proxy
# are told to do, not real lookups, so they work without internet access.
# Sourced by run.sh.

AUTO='{"mode":"auto","servers":[],"provider":"","url":""}'
DNSMASQ_CONF="/var/etc/dnsmasq.conf.*"

check "encrypted DNS is installed but off after first boot" \
	"[ -x /etc/init.d/https-dns-proxy ] && ! ls /etc/rc.d | grep -q https-dns-proxy && ! pgrep https-dns-proxy"
check "a server set outside the UI is kept" \
	"uci add_list dhcp.@dnsmasq[0].server=/corp.example/10.0.0.53 && uci commit dhcp"
check "manual DNS servers are accepted" \
	"ubus call supacudy dns_set '{\"mode\":\"manual\",\"servers\":[\"9.9.9.9\",\"1.1.1.1\"],\"provider\":\"\",\"url\":\"\"}' | grep -q applied"
eventually "dnsmasq only asks the manual servers" \
	"grep -q '^server=9.9.9.9$' $DNSMASQ_CONF && grep -q '^server=1.1.1.1$' $DNSMASQ_CONF &&
	 grep -q '^no-resolv$' $DNSMASQ_CONF && grep -q 'server=/corp.example/10.0.0.53' $DNSMASQ_CONF"
check "a malformed server is rejected as invalid" \
	"! ubus call supacudy dns_set '{\"mode\":\"manual\",\"servers\":[\"dns.example\"],\"provider\":\"\",\"url\":\"\"}'"
check "manual mode without servers is rejected as invalid" \
	"! ubus call supacudy dns_set '{\"mode\":\"manual\",\"servers\":[],\"provider\":\"\",\"url\":\"\"}'"
check "a plain-HTTP DoH address is refused" \
	"ubus call supacudy dns_set '{\"mode\":\"encrypted\",\"servers\":[],\"provider\":\"custom\",\"url\":\"http://dns.example/q\"}' | grep -q doh_url_invalid"

check "AliDNS by address is the default encrypted DNS provider" \
	"ubus call supacudy dns_get | jsonfilter -e @.provider | grep -qx alidns && ubus call supacudy dns_get | jsonfilter -e '@.providers[0]' | grep -qx alidns"
check "encrypted DNS with the default provider is accepted" \
	"ubus call supacudy dns_set '{\"mode\":\"encrypted\",\"servers\":[],\"provider\":\"alidns\",\"url\":\"\"}' | grep -q applied"
eventually "the proxy asks 223.5.5.5 over HTTPS" "uci show https-dns-proxy | grep -q \"resolver_url='https://223.5.5.5/dns-query'\""
check "encrypted DNS is accepted" \
	"ubus call supacudy dns_set '{\"mode\":\"encrypted\",\"servers\":[],\"provider\":\"quad9\",\"url\":\"\"}' | grep -q applied"
eventually "the proxy runs the chosen provider and dnsmasq forwards to it" \
	"pgrep -f '[h]ttps-dns-proxy.*dns.quad9.net' && grep -q '^server=127.0.0.1#5053$' $DNSMASQ_CONF &&
	 ! grep -q '^server=9.9.9.9$' $DNSMASQ_CONF && [ \"\$(uci show https-dns-proxy | grep -c resolver_url)\" = 1 ]"
check "the proxy starts again after a reboot" "ls /etc/rc.d | grep -q https-dns-proxy"

check "automatic DNS is restored" "ubus call supacudy dns_set '$AUTO' | grep -q applied"
eventually "the proxy stops and dnsmasq uses the network's servers again" \
	"! pgrep https-dns-proxy && ! ls /etc/rc.d | grep -q https-dns-proxy &&
	 ! grep -q '^no-resolv$' $DNSMASQ_CONF && ! grep -q '127.0.0.1#5053' $DNSMASQ_CONF &&
	 grep -q 'server=/corp.example/10.0.0.53' $DNSMASQ_CONF"
check "the outside server is cleaned up" \
	"uci del_list dhcp.@dnsmasq[0].server=/corp.example/10.0.0.53 && uci commit dhcp && /etc/init.d/dnsmasq restart"

check "a local host name is added" \
	"ubus call supacudy host_set '{\"id\":\"\",\"name\":\"nas.home\",\"ip\":\"192.168.200.50\"}' | jsonfilter -e @.id > /tmp/host-id"
eventually "LAN devices resolve it through the router" \
	"ip netns exec laptop nslookup nas.home 192.168.200.1 | grep -q 'Address: 192.168.200.50'"
check "a duplicate name is refused" \
	"ubus call supacudy host_set '{\"id\":\"\",\"name\":\"NAS.home\",\"ip\":\"192.168.200.51\"}' | grep -q host_exists"
check "a malformed name is rejected as invalid" \
	"! ubus call supacudy host_set '{\"id\":\"\",\"name\":\"bad name\",\"ip\":\"192.168.200.51\"}'"
check "the host name is deleted" \
	"ubus call supacudy host_delete \"{\\\"id\\\":\\\"\$(cat /tmp/host-id)\\\"}\" | grep -q deleted && ! uci show dhcp | grep -q nas.home"
check "rebind protection can be turned off and on" "
	ubus call supacudy dns_rebind_set '{\"enabled\":false}' | grep -q applied && [ \"\$(uci get dhcp.@dnsmasq[0].rebind_protection)\" = 0 ] &&
	ubus call supacudy dns_rebind_set '{\"enabled\":true}' | grep -q applied && [ \"\$(uci get dhcp.@dnsmasq[0].rebind_protection)\" = 1 ]"
eventually "dnsmasq stops rebind protection only while it is off" "grep -q '^stop-dns-rebind$' /var/etc/dnsmasq.conf.*"
