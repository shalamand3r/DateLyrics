TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TOOL_NAME = DateLyricsResetDiagnostics
DateLyricsResetDiagnostics_FILES = main.m
DateLyricsResetDiagnostics_CFLAGS = -fobjc-arc
DateLyricsResetDiagnostics_FRAMEWORKS = Foundation
DateLyricsResetDiagnostics_INSTALL_PATH = /usr/libexec/DateLyrics
include $(THEOS_MAKE_PATH)/tool.mk
