#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for dynamic DNS. Only the configuration is checked: updating
# a provider needs the internet. Sourced by run.sh.

check "dynamic DNS needs a known provider and a real domain" "
	ubus call supacudy ddns_set '{\"enabled\":true,\"service\":\"nope.example\",\"domain\":\"a.duckdns.org\",\"username\":\"\",\"password\":\"t\"}' | grep -q ddns_service_unknown &&
	ubus call supacudy ddns_set '{\"enabled\":true,\"service\":\"duckdns.org\",\"domain\":\"nodot\",\"username\":\"\",\"password\":\"t\"}' | grep -q ddns_domain_invalid"
check "dynamic DNS is set up without handing its token back" "
	ubus call supacudy ddns_set '{\"enabled\":true,\"service\":\"duckdns.org\",\"domain\":\"myhome.duckdns.org\",\"username\":\"myhome\",\"password\":\"tok-123\"}' | grep -q applied &&
	[ \"\$(uci get ddns.supacudy.service_name)\" = duckdns.org ] && [ \"\$(uci get ddns.supacudy.ip_source)\" = web ] &&
	! ubus call supacudy ddns_get | grep -q tok-123 && ubus call supacudy ddns_get | grep -q '\"has_password\": true'"
check "dynamic DNS is turned off" \
	"ubus call supacudy ddns_set '{\"enabled\":false,\"service\":\"\",\"domain\":\"\",\"username\":\"\",\"password\":\"\"}' | grep -q applied && [ \"\$(uci get ddns.supacudy.enabled)\" = 0 ]"
