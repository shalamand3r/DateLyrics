TARGET := iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = Music SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DateLyrics
DateLyrics_FILES = DateLyrics.xm
DateLyrics_CFLAGS = -fobjc-arc

SUBPROJECTS = DateLyricsPrefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
