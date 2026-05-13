export PACKAGE_VERSION := 1.0

THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = Music SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME += DateLyrics

DateLyrics_FILES += DateLyrics.xm
DateLyrics_CFLAGS += -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
