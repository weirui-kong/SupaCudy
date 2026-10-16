#
# Copyright 2026 SupaCudy contributors
# SPDX-License-Identifier: Apache-2.0
#

include $(TOPDIR)/rules.mk

PKG_NAME:=supacudy-rpcd
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SupaCudy contributors

include $(INCLUDE_DIR)/package.mk

define Package/supacudy-rpcd
  SECTION:=supacudy
  CATEGORY:=SupaCudy
  TITLE:=SupaCudy rpcd API plugin
  PKGARCH:=all
  DEPENDS:=+supacudy-base +rpcd +rpcd-mod-ucode
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
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/supacudy.json $(1)/usr/share/rpcd/acl.d/
endef

define Package/supacudy-rpcd/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/rpcd restart
exit 0
endef

$(eval $(call BuildPackage,supacudy-rpcd))
