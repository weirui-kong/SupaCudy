#
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#

include $(TOPDIR)/rules.mk

PKG_NAME:=supacudy-rpcd
PKG_VERSION:=0.4.0
PKG_RELEASE:=5

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SupaCudy contributors

include $(INCLUDE_DIR)/package.mk

define Package/supacudy-rpcd
  SECTION:=supacudy
  CATEGORY:=SupaCudy
  TITLE:=SupaCudy rpcd API plugin
  PKGARCH:=all
  # luci-base: time zone table (luci.zoneinfo) and cgi-io for firmware uploads.
  # https-dns-proxy: encrypted DNS (about 400 KB with libcurl); off by default.
  # wireguard-tools: VPN client and server (about 200 KB, pulls in kmod-wireguard).
  # openvpn-mbedtls: OpenVPN client (about 650 KB, pulls in kmod-tun).
  # ddns-scripts*: dynamic DNS with common providers (about 250 KB).
  # adguardhome: the default DNS with ad blocking (about 10 MB).
  DEPENDS:=+supacudy-base +rpcd +rpcd-mod-ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus +ucode-mod-rtnl +ucode-mod-nl80211 +nftables +luci-base +https-dns-proxy +wireguard-tools +openvpn-mbedtls +ddns-scripts +ddns-scripts-services +ddns-scripts-cloudflare +ddns-scripts-dnspod-v3 +adguardhome +curl +tailscale
endef

define Package/supacudy-rpcd/description
  ucode plugin for rpcd exposing the "supacudy" ubus object, plus the
  ACL that lets the web UI call it.
endef

define Build/Compile
endef

define Package/supacudy-rpcd/install
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) ./files/usr/share/rpcd/ucode/supacudy.uc $(1)/usr/share/rpcd/ucode/
	$(INSTALL_DIR) $(1)/usr/share/ucode/supacudy
	$(INSTALL_DATA) ./files/usr/share/ucode/supacudy/*.uc $(1)/usr/share/ucode/supacudy/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/92-supacudy-adguard $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/supacudy.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/usr/libexec/supacudy $(1)/etc/hotplug.d/openvpn $(1)/etc/hotplug.d/iface
	$(INSTALL_DATA) ./files/usr/libexec/supacudy/vpn-dns.uc $(1)/usr/libexec/supacudy/
	$(INSTALL_BIN) ./files/etc/hotplug.d/openvpn/30-supacudy-dns $(1)/etc/hotplug.d/openvpn/
	$(INSTALL_BIN) ./files/etc/hotplug.d/iface/30-supacudy-vpn-dns $(1)/etc/hotplug.d/iface/
endef

define Package/supacudy-rpcd/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/rpcd restart
exit 0
endef

$(eval $(call BuildPackage,supacudy-rpcd))
