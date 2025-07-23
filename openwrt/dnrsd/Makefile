include $(TOPDIR)/rules.mk

PKG_NAME:=dnrsd
PKG_VERSION:=$(shell git show -s --format=%cd --date=format:%Y%m%d)
PKG_RELEASE:=1

PKG_FILE_DEPENDS:=$(CURDIR)/../..

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	ln -s $(CURDIR)/../../.git $(PKG_BUILD_DIR)/.git
	cd $(PKG_BUILD_DIR) && git checkout .
endef

define Build/Compile
endef

define Package/dnrsd
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=+ucode +ucode-mod-fs +ucode-mod-ubus +ucode-mod-uloop
  TITLE:=Distributed Neighbor Report Synchronization Daemon
endef

define Package/dnrsd/conffiles
/etc/config/dnrsd
endef

define Package/dnrsd/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/share/ucode/dnrsd $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/openwrt/dnrsd/files/dnrsd.init $(1)/etc/init.d/dnrsd
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/dnrsd.uc $(1)/usr/bin/dnrsd
	$(CP) $(PKG_BUILD_DIR)/openwrt/dnrsd/files/dnrsd.config $(1)/etc/config/dnrsd
	$(CP) $(PKG_BUILD_DIR)/src/wlan.uc $(1)/usr/share/ucode/dnrsd/wlan.uc
endef

$(eval $(call BuildPackage,dnrsd))
