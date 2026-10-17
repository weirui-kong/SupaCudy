#!/usr/bin/env bash
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#
# Emulator tests for the internet connection: WAN settings reach netifd, the
# repeater really joins the upstream hotspots (WPA2, open and WPA2-Enterprise),
# reports how a join went, and auto-switch moves to another saved network
# when the current one disappears. Sourced by run.sh.

HOTEL='"ssid":"Hotel-WiFi","bssid":"","encryption":"psk2","band":"2g"'
CAFE='"ssid":"Cafe-Free","bssid":"","encryption":"none","key":"","band":"2g"'
UP="ip netns exec upstream"
WAN_DHCP='{"proto":"dhcp","ipaddr":"","netmask":"","gateway":"","dns":[],"username":"","password":""}'
# The bracket keeps pgrep from matching the shell running this command.
RESPAWN_UPSTREAM="kill \$(pgrep -f '[h]ostapd-upstream.conf')"
status_is() { echo "ubus call supacudy repeater_status | jsonfilter -e @.state -e @.reason | xargs | grep -qx '$1'"; }
# PEAP or TTLS login for the emulator's "Campus-WiFi"; see docs/emulator.md.
campus() {
	echo "ubus call supacudy repeater_connect '{\"ssid\":\"Campus-WiFi\",\"bssid\":\"\",\"encryption\":\"enterprise\",\"key\":\"\",\"band\":\"2g\",\"save\":${5:-true},\"eap\":{\"method\":\"$1\",\"identity\":\"campus-user\",\"anonymous_identity\":\"\",\"password\":\"$2\",\"phase2\":\"$3\",\"validate\":$4,\"domain\":\"emu-server\"}}' | grep -q applied"
}
wwan_up() { echo "ubus call network.interface.wwan status | jsonfilter -e @.up | grep -q true && ubus call network.interface.wwan status | grep -q '\"address\": \"$1'"; }

check "anonymous callers cannot read the internet status" \
	"! ubus -S call session access '{\"ubus_rpc_session\":\"00000000000000000000000000000000\",\"scope\":\"ubus\",\"object\":\"supacudy\",\"function\":\"internet_status\"}' | grep -q true"
check "anonymous callers cannot read how a join went" \
	"! ubus -S call session access '{\"ubus_rpc_session\":\"00000000000000000000000000000000\",\"scope\":\"ubus\",\"object\":\"supacudy\",\"function\":\"repeater_status\"}' | grep -q true"
eventually "the Ethernet WAN is the active connection" \
	"ubus call supacudy internet_status | tr -d '\n\t ' | grep -q '\"active\":\"wan\"' &&
	 ubus call supacudy internet_status | jsonfilter -e @.ethernet.ipaddr | grep -q '^10.250.2.'"
check "the WAN settings are readable" \
	"ubus call supacudy wan_get | jsonfilter -e @.proto | grep -qx dhcp"

check "a gateway outside the subnet is refused" \
	"ubus call supacudy wan_set '{\"proto\":\"static\",\"ipaddr\":\"10.250.2.15\",\"netmask\":\"255.255.255.0\",\"gateway\":\"10.250.3.1\",\"dns\":[],\"username\":\"\",\"password\":\"\"}' | grep -q gateway_outside"
check "a WAN address inside the LAN is refused" \
	"ubus call supacudy wan_set '{\"proto\":\"static\",\"ipaddr\":\"192.168.200.20\",\"netmask\":\"255.255.255.0\",\"gateway\":\"192.168.200.254\",\"dns\":[],\"username\":\"\",\"password\":\"\"}' | grep -q subnet_conflict"
check "PPPoE without a user name is refused" \
	"ubus call supacudy wan_set '{\"proto\":\"pppoe\",\"ipaddr\":\"\",\"netmask\":\"\",\"gateway\":\"\",\"dns\":[],\"username\":\"\",\"password\":\"x\"}' | grep -q pppoe_credentials"
check "a saved PPPoE password is kept but never read back" "
	ubus call supacudy wan_set '{\"proto\":\"pppoe\",\"ipaddr\":\"\",\"netmask\":\"\",\"gateway\":\"\",\"dns\":[],\"username\":\"u@isp\",\"password\":\"isp-secret\"}' | grep -q applied &&
	ubus call supacudy wan_set '{\"proto\":\"pppoe\",\"ipaddr\":\"\",\"netmask\":\"\",\"gateway\":\"\",\"dns\":[],\"username\":\"u@isp\",\"password\":\"\"}' | grep -q applied &&
	[ \"\$(uci get network.wan.password)\" = isp-secret ] && ! ubus call supacudy wan_get | grep -q isp-secret &&
	ubus call supacudy wan_get | grep -q '\"has_password\": true' && ubus call supacudy wan_set '$WAN_DHCP' | grep -q applied"
check "an unknown protocol is rejected as invalid" \
	"! ubus call supacudy wan_set '{\"proto\":\"l2tp\",\"ipaddr\":\"\",\"netmask\":\"\",\"gateway\":\"\",\"dns\":[],\"username\":\"\",\"password\":\"\"}'"
check "a malformed DNS server is rejected as invalid" \
	"! ubus call supacudy wan_set '{\"proto\":\"dhcp\",\"ipaddr\":\"\",\"netmask\":\"\",\"gateway\":\"\",\"dns\":[\"dns.example\"],\"username\":\"\",\"password\":\"\"}'"

check "a static WAN address is applied" \
	"ubus call supacudy wan_set '{\"proto\":\"static\",\"ipaddr\":\"10.250.2.15\",\"netmask\":\"255.255.255.0\",\"gateway\":\"10.250.2.2\",\"dns\":[\"10.250.2.3\"],\"username\":\"\",\"password\":\"\"}' | grep -q applied"
eventually "netifd runs the WAN with the static address and DNS" \
	"ubus call network.interface.wan status | jsonfilter -e @.proto | grep -qx static &&
	 ubus call network.interface.wan status | jsonfilter -e @.up | grep -q true &&
	 [ \"\$(uci get network.wan.peerdns)\" = 0 ] && grep -q 10.250.2.3 /tmp/resolv.conf.d/resolv.conf.auto"
check "the WAN goes back to DHCP" "ubus call supacudy wan_set '$WAN_DHCP' | grep -q applied"
eventually "DHCP on the WAN is up again" \
	"ubus call network.interface.wan status | jsonfilter -e @.proto | grep -qx dhcp &&
	 ubus call network.interface.wan status | jsonfilter -e @.up | grep -q true &&
	 ! uci -q get network.wan.dns"

check "a multicast MAC address is refused" \
	"ubus call supacudy mac_set '{\"target\":\"wan\",\"mode\":\"custom\",\"macaddr\":\"01:00:5e:00:00:01\"}' | grep -q mac_not_unicast"
check "a custom WAN MAC address is accepted" \
	"ubus call supacudy mac_set '{\"target\":\"wan\",\"mode\":\"custom\",\"macaddr\":\"02:AB:CD:00:11:22\"}' | grep -q applied"
eventually "the WAN port uses the custom address and comes back up" \
	"[ \"\$(cat /sys/class/net/eth0/address)\" = 02:ab:cd:00:11:22 ] &&
	 ubus call network.interface.wan status | jsonfilter -e @.up | grep -q true &&
	 ubus call supacudy mac_get | tr -d '\n\t ' | grep -q '\"custom\":\"02:ab:cd:00:11:22\",\"factory\":\"52:54'"
check "the factory WAN address is restored" \
	"ubus call supacudy mac_set '{\"target\":\"wan\",\"mode\":\"default\",\"macaddr\":\"\"}' | grep -q applied"
eventually "the WAN port is back on its factory address" \
	"cat /sys/class/net/eth0/address | grep -q '^52:54' && ! uci -q get network.supacudy_wan_dev &&
	 ubus call network.interface.wan status | jsonfilter -e @.up | grep -q true"

eventually "the scan finds both hotspots with their security" \
	"ubus call supacudy repeater_scan | tr -d '\n\t ' > /tmp/scan.json &&
	 grep -q '\"ssid\":\"Hotel-WiFi\",[^}]*\"encryption\":\"psk2\"' /tmp/scan.json &&
	 grep -q '\"ssid\":\"Cafe-Free\",[^}]*\"encryption\":\"none\"' /tmp/scan.json"
check "the scan leaves out the router's own networks" \
	"! ubus call supacudy repeater_scan | grep -q SupaCudy-Emu"
check "a short upstream password is refused" \
	"ubus call supacudy repeater_connect '{$HOTEL,\"key\":\"short\",\"save\":true}' | grep -q key_invalid"
check "a malformed BSSID is rejected as invalid" \
	"! ubus call supacudy repeater_connect '{\"ssid\":\"Hotel-WiFi\",\"bssid\":\"zz\",\"encryption\":\"psk2\",\"key\":\"hotel-guest\",\"band\":\"2g\",\"save\":false}'"

check "joining the hotel hotspot is accepted" \
	"ubus call supacudy repeater_connect '{$HOTEL,\"key\":\"hotel-guest\",\"save\":true}' | grep -q applied"
check "a fresh join is not mistaken for a lost network" \
	"sleep 3; ubus call supacudy repeater_tick | grep -q waiting && [ \"\$(uci get wireless.wwan.ssid)\" = Hotel-WiFi ]"
eventually "the repeater gets an address from the hotel" "$(wwan_up 10.250.11.)"
check "the join is reported as connected with its address" \
	"$(status_is connected) && ubus call supacudy repeater_status | jsonfilter -e @.ipaddr | grep -q '^10.250.11.'"
check "the repeater reports the link and locks the shared radio" \
	"ubus call supacudy internet_status | tr -d '\n\t ' | grep -q '\"connected\":true' &&
	 ubus call supacudy wifi_get | tr -d '\n\t ' | grep -q '\"name\":\"radio0\",[^}]*\"locked\":\"repeater\"'"
check "the router's own 2.4 GHz network follows the upstream channel" \
	"iw dev phy0-ap0 info | grep -q 'channel 1 ' &&
	 ubus call supacudy wifi_get | tr -d '\n\t ' | grep -q '\"name\":\"radio0\",\"band\":\"2g\",\"enabled\":true,\"channel\":1,'"
check "the hotel is saved with its password" \
	"ubus call supacudy repeater_saved | grep -q Hotel-WiFi && uci show supacudy | grep -q \"key='hotel-guest'\""
check "rejoining a saved network works without the password" \
	"ubus call supacudy repeater_connect '{$HOTEL,\"key\":\"\",\"save\":true}' | grep -q applied && [ \"\$(uci get wireless.wwan.key)\" = hotel-guest ]"
eventually "the repeater is back on the hotel" "$(wwan_up 10.250.11.)"

check "joining the open café is accepted" \
	"ubus call supacudy repeater_connect '{$CAFE,\"save\":true}' | grep -q applied"
eventually "the repeater gets an address from the café" "$(wwan_up 10.250.12.)"
check "the switch grace period is shortened for the test" \
	"uci set supacudy.main.repeater_grace=5 && uci commit supacudy"
check "the café disappears" "$UP ip link set up1 down"
# Ticked here rather than waiting for the watcher's 20 s period.
switched=0
for _ in $(seq 30); do
	if vm "ubus call supacudy repeater_tick >/dev/null; [ \"\$(uci get wireless.wwan.ssid)\" = Hotel-WiFi ] && $(wwan_up 10.250.11.)" >/dev/null 2>&1; then
		switched=1
		break
	fi
	sleep 3
done
if [ "$switched" = 1 ]; then ok "auto-switch moves to the saved hotel"; else not_ok "auto-switch moves to the saved hotel"; fi
eventually "the café comes back" "$RESPAWN_UPSTREAM; sleep 3; $UP iw dev up1 info | grep -q 'ssid Cafe-Free'"
check "the grace period is back to its default" "uci -q delete supacudy.main.repeater_grace; uci commit supacudy"

check "options are stored" \
	"ubus call supacudy repeater_options '{\"auto_switch\":false,\"force_20mhz\":true}' | grep -q true &&
	 [ \"\$(uci get supacudy.main.repeater_auto_switch)\" = 0 ] && [ \"\$(uci get supacudy.main.repeater_20mhz)\" = 1 ]"
check "the tick is idle with auto-switch off" \
	"ubus call supacudy repeater_tick | grep -q idle"
check "options with the wrong type are rejected" \
	"! ubus call supacudy repeater_options '{\"auto_switch\":\"yes\",\"force_20mhz\":false}'"
check "auto-switch is turned back on" \
	"ubus call supacudy repeater_options '{\"auto_switch\":true,\"force_20mhz\":false}' | grep -q true"
check "forgetting a network removes it" \
	"ubus call supacudy repeater_forget '{\"ssid\":\"Cafe-Free\"}' | grep -q true && ! ubus call supacudy repeater_saved | grep -q Cafe-Free"
check "forgetting an unknown network reports not found" \
	"! ubus call supacudy repeater_forget '{\"ssid\":\"Nowhere\"}'"

check "a wrong hotel password is accepted for trying" \
	"ubus call supacudy repeater_connect '{$HOTEL,\"key\":\"not-the-key\",\"save\":false}' | grep -q applied"
eventually "the join is reported as failed because of the password" "$(status_is 'failed wrong_key')"
check "a network that is not there is accepted for trying" \
	"ubus call supacudy repeater_connect '{\"ssid\":\"Nowhere-WiFi\",\"bssid\":\"\",\"encryption\":\"psk2\",\"key\":\"whatever-123\",\"band\":\"2g\",\"save\":false}' | grep -q applied"
eventually "the join is first reported as still connecting, then as not found" \
	"$(status_is connecting) || $(status_is 'failed not_found')"
eventually "the network is reported as not found" "$(status_is 'failed not_found')"

eventually "the scan reports the campus network as enterprise" \
	"ubus call supacudy repeater_scan | tr -d '\n\t ' | grep -q '\"ssid\":\"Campus-WiFi\",[^}]*\"encryption\":\"enterprise\"'"
check "an enterprise join without a login is rejected as invalid" \
	"! ubus call supacudy repeater_connect '{\"ssid\":\"Campus-WiFi\",\"bssid\":\"\",\"encryption\":\"enterprise\",\"key\":\"\",\"band\":\"2g\",\"save\":false}'"
check "PEAP with an inner method only TTLS has is rejected as invalid" "! $(campus peap campus-pass PAP false false)"
check "checking the certificate without a domain is rejected as invalid" \
	"! ubus call supacudy repeater_connect '{\"ssid\":\"Campus-WiFi\",\"bssid\":\"\",\"encryption\":\"enterprise\",\"key\":\"\",\"band\":\"2g\",\"save\":false,\"eap\":{\"method\":\"peap\",\"identity\":\"campus-user\",\"anonymous_identity\":\"\",\"password\":\"x\",\"phase2\":\"MSCHAPV2\",\"validate\":true,\"domain\":\"\"}}'"
check "an enterprise join without a password is refused" \
	"ubus call supacudy repeater_forget '{\"ssid\":\"Campus-WiFi\"}' >/dev/null 2>&1; ubus call supacudy repeater_connect '{\"ssid\":\"Campus-WiFi\",\"bssid\":\"\",\"encryption\":\"enterprise\",\"key\":\"\",\"band\":\"2g\",\"save\":false,\"eap\":{\"method\":\"peap\",\"identity\":\"campus-user\",\"anonymous_identity\":\"\",\"password\":\"\",\"phase2\":\"MSCHAPV2\",\"validate\":false,\"domain\":\"\"}}' | grep -q eap_password_needed"
check "a wrong campus password is accepted for trying" "$(campus peap wrong-pass MSCHAPV2 false false)"
eventually "the join is reported as failed: login not accepted" "$(status_is 'failed auth_failed')"
check "joining the campus network with PEAP is accepted" "$(campus peap campus-pass MSCHAPV2 false)"
eventually "the repeater gets an address from the campus network" "$(wwan_up 10.250.13.) && $(status_is connected)"
check "netifd gets a WPA2-Enterprise station without a certificate check" \
	"[ \"\$(uci get wireless.wwan.encryption)\" = wpa2 ] && [ \"\$(uci get wireless.wwan.eap_type)\" = peap ] &&
	 [ \"\$(uci get wireless.wwan.auth)\" = MSCHAPV2 ] && ! uci -q get wireless.wwan.key && ! uci -q get wireless.wwan.ca_cert_usesystem"
check "the login is saved, and read back without its password" \
	"uci show supacudy | grep -q \"eap_identity='campus-user'\" &&
	 ubus call supacudy repeater_saved | tr -d '\n\t ' | grep -q '\"ssid\":\"Campus-WiFi\",[^]]*\"identity\":\"campus-user\"' &&
	 ! ubus call supacudy repeater_saved | grep -q campus-pass"
check "rejoining it with TTLS and PAP works without retyping the password" "$(campus ttls '' PAP false)"
eventually "the TTLS join connects" "$(wwan_up 10.250.13.) && $(status_is connected) && [ \"\$(uci get wireless.wwan.eap_type)\" = ttls ]"
check "checking the certificate against the system authorities is accepted for trying" "$(campus peap campus-pass MSCHAPV2 true false)"
check "the check uses the system authorities and the server domain" \
	"[ \"\$(uci get wireless.wwan.ca_cert_usesystem)\" = 1 ] && uci get wireless.wwan.domain_suffix_match | grep -qx emu-server"
eventually "the test certificate is not trusted, so the join fails on the certificate" "$(status_is 'failed certificate')"
check "the campus network is forgotten and the hotel rejoined" \
	"ubus call supacudy repeater_forget '{\"ssid\":\"Campus-WiFi\"}' | grep -q true &&
	 ubus call supacudy repeater_connect '{$HOTEL,\"key\":\"\",\"save\":true}' | grep -q applied"
eventually "the repeater is back on the hotel once more" "$(wwan_up 10.250.11.) && $(status_is connected)"

check "the repeater gets a random locally administered MAC address" \
	"ubus call supacudy mac_set '{\"target\":\"repeater\",\"mode\":\"random\",\"macaddr\":\"\"}' | grep -q applied &&
	 uci get wireless.wwan.macaddr | grep -Eq '^[0-9a-f][26ae]:'"
check "the repeater MAC address is reset" \
	"ubus call supacudy mac_set '{\"target\":\"repeater\",\"mode\":\"default\",\"macaddr\":\"\"}' | grep -q applied && ! uci -q get wireless.wwan.macaddr"
check "disconnecting is accepted" "ubus call supacudy repeater_disconnect | grep -q applied"
eventually "the station interface goes away and the radio is unlocked" \
	"! iw dev | grep -q phy0-sta0 &&
	 ! ubus call supacudy wifi_get | grep -q '\"locked\": \"repeater\"' &&
	 ubus call supacudy internet_status | tr -d '\n\t ' | grep -q '\"enabled\":false'"

check "the WAN port becomes a LAN port" "ubus call supacudy wan_port_set '{\"as_lan\":true}' | grep -q applied"
eventually "eth0 joins the LAN bridge and the Ethernet WAN is off" \
	"[ \"\$(basename \"\$(readlink /sys/class/net/eth0/master)\")\" = br-lan ] && [ \"\$(uci get network.wan.disabled)\" = 1 ] &&
	 ubus call supacudy wan_get | grep -q '\"as_lan\": true'"
check "the WAN port is given back" "ubus call supacudy wan_port_set '{\"as_lan\":false}' | grep -q applied"
eventually "eth0 is the Ethernet WAN again" \
	"[ ! -e /sys/class/net/eth0/master ] && ! uci -q get network.wan.disabled &&
	 ubus call network.interface.wan status | jsonfilter -e @.up | grep -q true"
