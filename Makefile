# TrollLyricsDesk — Theos 构建入口（v0.5 悬浮歌词 HUD）。
#
# 第二条构建路线，尚未接 CI、尚未验证；当前 CI 走 Xcode（.github/workflows/build.yml）。
# 以皇上发的 Makefile 为底，FILES 的 glob 按本仓库实际布局改了；
# 签名 entitlements 路径也按本仓库改了（皇上原版的 supports/entitlements.plist
# 在这个仓库里不存在，实际文件是 TrollLyricsDesk/TrollLyricsDesk.entitlements）。
# Widget Extension 只走 Xcode，不进这份 Makefile。
#
# 用法（Linux 烟囱编法，和分屏/抖音一样）：
#   export THEOS=/home/hatch/theos
#   make clean
#   make package
ARCHS := arm64
TARGET := iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := TrollLyricsDesk

TrollLyricsDesk_FILES += $(wildcard sources/*.mm)
TrollLyricsDesk_FILES += $(wildcard sources/*.m)
TrollLyricsDesk_FILES += $(wildcard HUD/*.swift)
TrollLyricsDesk_FILES += $(wildcard App/*.swift)
TrollLyricsDesk_FILES += $(wildcard Lyrics/*.swift)
TrollLyricsDesk_FILES += $(wildcard Core/*.swift)
TrollLyricsDesk_FILES += $(wildcard PlaybackEngine/*.swift)
TrollLyricsDesk_FILES += $(wildcard MusicProviders/*.swift)
TrollLyricsDesk_FILES += $(wildcard TrollLyricsDesk/*.swift)

TrollLyricsDesk_FRAMEWORKS += \
    UIKit Foundation QuartzCore CoreGraphics AVFoundation

TrollLyricsDesk_PRIVATE_FRAMEWORKS += \
    BackBoardServices GraphicsServices SpringBoardServices

TrollLyricsDesk_CFLAGS += -fobjc-arc
TrollLyricsDesk_CCFLAGS += -std=c++17

TrollLyricsDesk_CODESIGN_FLAGS += \
    -STrollLyricsDesk/TrollLyricsDesk.entitlements

include $(THEOS_MAKE_PATH)/application.mk
