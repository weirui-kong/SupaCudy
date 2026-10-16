#
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#

include $(TOPDIR)/rules.mk

PKG_NAME:=supacudy-ui
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SupaCudy contributors

include $(INCLUDE_DIR)/package.mk

define Package/supacudy-ui
  SECTION:=supacudy
  CATEGORY:=SupaCudy
  TITLE:=SupaCudy web UI
  PKGARCH:=all
  DEPENDS:=+supacudy-rpcd +uhttpd +uhttpd-mod-ubus
endef

define Package/supacudy-ui/description
  Pre-built static files of the SupaCudy web interface, served by uhttpd
  under /supacudy/.
endef

define Build/Compile
endef

# htdocs/ holds the built front-end (web/ compiles into it).
define Package/supacudy-ui/install
	$(INSTALL_DIR) $(1)/www/supacudy
	$(CP) ./htdocs/. $(1)/www/supacudy/
endef

$(eval $(call BuildPackage,supacudy-ui))
