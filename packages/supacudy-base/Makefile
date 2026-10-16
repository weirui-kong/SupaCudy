#
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#

include $(TOPDIR)/rules.mk

PKG_NAME:=supacudy-base
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SupaCudy contributors

include $(INCLUDE_DIR)/package.mk

define Package/supacudy-base
  SECTION:=supacudy
  CATEGORY:=SupaCudy
  TITLE:=SupaCudy base system integration
  PKGARCH:=all
  DEPENDS:=+uhttpd +uhttpd-mod-ubus +rpcd
endef

define Package/supacudy-base/description
  First-boot defaults, version information and glue scripts shared by
  the SupaCudy web UI and its rpcd plugin.
endef

define Build/Compile
endef

define Package/supacudy-base/install
	$(INSTALL_DIR) $(1)/etc
	echo "$(PKG_VERSION)-r$(PKG_RELEASE)" > $(1)/etc/supacudy_version
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-supacudy $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,supacudy-base))
