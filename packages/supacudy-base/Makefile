#
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#

include $(TOPDIR)/rules.mk

PKG_NAME:=supacudy-base
PKG_VERSION:=0.4.0
PKG_RELEASE:=4

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SupaCudy contributors

include $(INCLUDE_DIR)/package.mk

define Package/supacudy-base
  SECTION:=supacudy
  CATEGORY:=SupaCudy
  TITLE:=SupaCudy base system integration
  PKGARCH:=all
  DEPENDS:=+uhttpd +uhttpd-mod-ubus +rpcd +ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus +ucode-mod-nl80211 +nftables +conntrack
  # USB tethering. Kernel modules go in EXTRA_DEPENDS so the SDK records them
  # without rebuilding every kernel package; usbmuxd pairs iPhones.
  EXTRA_DEPENDS:=kmod-usb-net-rndis, kmod-usb-net-cdc-ether, kmod-usb-net-cdc-ncm, kmod-usb-net-ipheth, usbmuxd
endef

define Package/supacudy-base/description
  First-boot defaults, version information and glue scripts shared by
  the SupaCudy web UI and its rpcd plugin.
endef

define Package/supacudy-base/conffiles
/etc/config/supacudy
endef

define Build/Compile
endef

define Package/supacudy-base/install
	$(INSTALL_DIR) $(1)/etc
	echo "$(PKG_VERSION)-r$(PKG_RELEASE)" > $(1)/etc/supacudy_version
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-supacudy $(1)/etc/uci-defaults/
	$(INSTALL_BIN) ./files/etc/uci-defaults/91-supacudy-defaults $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/supacudy $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/supacudy $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/init.d/supacudy-repeater $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/init.d/supacudy-rescue $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/init.d/supacudy-failover $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/init.d/supacudy-cpu-limit $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/usr/libexec/supacudy
	$(INSTALL_DATA) ./files/usr/libexec/supacudy/policy.uc $(1)/usr/libexec/supacudy/
	$(INSTALL_BIN) ./files/usr/libexec/supacudy/repeater-watch $(1)/usr/libexec/supacudy/
	$(INSTALL_DATA) ./files/usr/libexec/supacudy/rescue.uc $(1)/usr/libexec/supacudy/
	$(INSTALL_BIN) ./files/usr/libexec/supacudy/rescue-watch $(1)/usr/libexec/supacudy/
	$(INSTALL_DATA) ./files/usr/libexec/supacudy/failover.uc $(1)/usr/libexec/supacudy/
	$(INSTALL_BIN) ./files/usr/libexec/supacudy/failover-watch $(1)/usr/libexec/supacudy/
	$(INSTALL_BIN) ./files/usr/libexec/supacudy/cpu-limit $(1)/usr/libexec/supacudy/
	$(INSTALL_BIN) ./files/usr/libexec/supacudy/dhcp-probe $(1)/usr/libexec/supacudy/
	$(INSTALL_DIR) $(1)/etc/hotplug.d/net
	$(INSTALL_DATA) ./files/etc/hotplug.d/net/30-supacudy-tethering $(1)/etc/hotplug.d/net/
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) ./files/www/cgi-bin/supacudy-whoami $(1)/www/cgi-bin/
endef

$(eval $(call BuildPackage,supacudy-base))
