TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Music SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DateLyrics
DateLyrics_FILES = DateLyrics.xm
DateLyrics_LIBRARIES = CoreLyrics
DateLyrics_LDFLAGS = -L$(THEOS_PROJECT_DIR)/LyricBridge/SDK
DateLyrics_CFLAGS = -fobjc-arc

SUBPROJECTS = DateLyricsPrefs tools/install-helper

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

# package readable files and executable binaries regardless of the host umask.
before-package::
	@echo "> Normalising staging permissions"
	@find "$(THEOS_STAGING_DIR)" -type d -exec chmod 755 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -exec chmod 644 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -name '*.dylib' -exec chmod 755 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -path '*/DateLyricsPrefs.bundle/DateLyricsPrefs' -exec chmod 755 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -path '*/usr/libexec/DateLyrics/DateLyricsResetDiagnostics' -exec chmod 755 {} +
	@for script in postinst postrm preinst prerm; do \
		if [ -f "$(THEOS_STAGING_DIR)/DEBIAN/$$script" ]; then \
			chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN/$$script"; \
		fi; \
	done
