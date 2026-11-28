#!/usr/bin/env python3
"""Self-check for TrollLyricsDesk 2.0.2/build 32（药丸长按拖动＋固定位置＋
关于页删日志行＋歌词颜色取色器＋透明度／字号修）。

Base = 2.0.1/build 31 HEAD cf78428 (branch v2.0.2) + 本次六项改动。
Run from the repo root:  python3 check_2.0.0.py
Exit 0 = all PASS. FAILED: none is the goal; OPEN items are recorded,
not failures (things that need macOS compile or Lee's device test).

Covers: versions / bundle id / MinOS; HUD port completeness and the two
key details (helper-path rule §3, always-rewrite plist §4); FrontBoard
trigger removal; LC hard gate (isLiveContainer untouched); retention
list (§11 of the design doc); pbxproj integrity (incl. the new daemon
target); build.yml daemon signing; TrollSpeed attribution; XExternalHUD
zero-copy; no old widget token.
"""
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = "cf78428"
fails = []
opens = []


def check(name, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {detail}")
    if not ok:
        fails.append(name)


def open_item(name, detail=""):
    print(f"OPEN  {name}  {detail}")
    opens.append(name)


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def read_bytes(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return f.read()


def git_out(args):
    return subprocess.check_output(["git"] + args, cwd=ROOT, text=True)


def pbx_sources_files(pbx_text, phase_id):
    m = re.search(re.escape(phase_id)
                  + r" /\* PBXSourcesBuildPhase \*/ = \{(.*?)\n\t\t\};",
                  pbx_text, re.S)
    if not m:
        return []
    out = []
    for bf in re.findall(r"([0-9A-F]{24})", m.group(1)):
        fm = re.search(re.escape(bf)
                       + r" /\* [^*]*\*/ = \{\s*isa = PBXBuildFile;"
                       + r"\s*fileRef = ([0-9A-F]{24})",
                       pbx_text)
        if not fm:
            continue
        fr = fm.group(1)
        rm = re.search(re.escape(fr)
                       + r" /\* [^*]*\*/ = \{\s*isa = PBXFileReference;"
                       + r"\s*lastKnownFileType = [^;]+;"
                       + r"\s*name = \"?([^\n\";]+)\"?;",
                       pbx_text)
        out.append(rm.group(1).strip().strip('"') if rm else fr)
    return out


HUD_FILES = [
    "HUD/TLDHUDHelper.h", "HUD/TLDHUDHelper.mm",
    "HUD/TLDHUDPaths.h", "HUD/TLDHUDPaths.mm",
    "HUD/TLDHUDLog.h", "HUD/TLDHUDLog.mm",
    "HUD/TLDHUDDaemonMain.mm",
    "HUD/TLDHUDMainApplication.h", "HUD/TLDHUDMainApplication.mm",
    "HUD/TLDHUDMainApplicationDelegate.h", "HUD/TLDHUDMainApplicationDelegate.mm",
    "HUD/TLDHUDMainWindow.h", "HUD/TLDHUDMainWindow.mm",
    "HUD/TLDHUDRootViewController.h", "HUD/TLDHUDRootViewController.mm",
    "HUD/TLDHUDLyricsSnapshot.h", "HUD/TLDHUDLyricsSnapshot.mm",
    "HUD/TLDHUDVersion.h",
    "HUD/TLDHUDDaemon.plist", "HUD/TLDHUDDaemon.entitlements",
]
HUD_HEADERS = [
    "HUD/headers/BackboardServices.h", "HUD/headers/IOKit+SPI.h",
    "HUD/headers/LSApplicationProxy.h", "HUD/headers/LSApplicationWorkspace.h",
    "HUD/headers/SBSAccessibilityWindowHostingController.h",
    "HUD/headers/SpringBoardServices.h", "HUD/headers/UIApplication+Private.h",
    "HUD/headers/UIWindow+Private.h",
]
HUD_TBDS = [
    "HUD/Private/BackBoardServices.tbd",
    "HUD/Private/GraphicsServices.tbd",
    "HUD/Private/SpringBoardServices.tbd",
]

print("== 1. 新文件在位 ==")
for rel in HUD_FILES + HUD_HEADERS + HUD_TBDS + [
        "App/HUDLogView.swift", "docs/2.0.0-MERGE-DESIGN.md"]:
    check(f"exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))
for rel in ["HUDTest/MainViewController.mm", "HUDTest/MainApplication.mm"]:
    check(f"not ported (test shell stays out): {rel}",
          not os.path.exists(os.path.join(ROOT, rel)))

print("\n== 2. 版本 / 包名 / MinOS ==")
for rel in ["TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist"]:
    pl = plistlib.loads(open(os.path.join(ROOT, rel), "rb").read())
    check(f"{rel}: version 2.0.2", pl.get("CFBundleShortVersionString") == "2.0.2",
          str(pl.get("CFBundleShortVersionString")))
    check(f"{rel}: build 32", pl.get("CFBundleVersion") == "32",
          str(pl.get("CFBundleVersion")))
    check(f"{rel}: min OS 15.0", pl.get("MinimumOSVersion") == "15.0",
          str(pl.get("MinimumOSVersion")))
app_pl = plistlib.loads(open(
    os.path.join(ROOT, "TrollLyricsDesk/Info.plist"), "rb").read())
check("app Info.plist: bundle id com.ycwl.Lyrics",
      app_pl.get("CFBundleIdentifier") == "com.ycwl.Lyrics")
check("app Info.plist: display name 桌面歌词",
      app_pl.get("CFBundleDisplayName") == "桌面歌词")
ls = read("Lyrics/LyricStore.swift")
check("LyricStore.versionTag = build 32（2.0.2）",
      'static let versionTag = "build 32（2.0.2）"' in ls)
check("LyricStore.testText() 版本 2.0.2",
      "悬浮测试 · 桌面歌词 2.0.2 ·" in ls)
check("SettingsView 测试文字说明版本 2.0.2",
      "悬浮测试 · 桌面歌词 2.0.2" in read("App/SettingsView.swift"))
check("PiPLyricsRenderer 测试文字版本 2.0.2",
      "悬浮测试 · 桌面歌词 2.0.2" in read("Renderer/PiPLyricsRenderer.swift"))
vh = read("HUD/TLDHUDVersion.h")
check("TLDHUDVersion.h: 2.0.2", 'TLDHUD_VERSION_STRING @"2.0.2"' in vh)
check("TLDHUDVersion.h: build 32", 'TLDHUD_BUILD_STRING @"32"' in vh)
check("TLDHUDVersion.h: 无 2.0.1 版本字串（check_2.0.1.py 的引用除外）",
      '@"2.0.1"' not in vh)
check("TLDHUDVersion.h: 无 build 29/30/31",
      '"29"' not in vh and '"30"' not in vh and '"31"' not in vh)
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: MARKETING_VERSION = 2.0.2 ×6（App＋Widget＋daemon 各 2）",
      pbx.count("MARKETING_VERSION = 2.0.2;") == 6,
      str(pbx.count("MARKETING_VERSION = 2.0.2;")))
check("pbxproj: CURRENT_PROJECT_VERSION = 32 ×6",
      pbx.count("CURRENT_PROJECT_VERSION = 32;") == 6,
      str(pbx.count("CURRENT_PROJECT_VERSION = 32;")))
check("pbxproj: 无 2.0.1 / build 29/30/31 版本号",
      "MARKETING_VERSION = 2.0.1" not in pbx
      and "CURRENT_PROJECT_VERSION = 29" not in pbx
      and "CURRENT_PROJECT_VERSION = 30" not in pbx
      and "CURRENT_PROJECT_VERSION = 31" not in pbx)

print("\n== 3. HUD 移植：关键细节 ==")
hp_h = read("HUD/TLDHUDPaths.h")
hp_m = read("HUD/TLDHUDPaths.mm")
hh_m = read("HUD/TLDHUDHelper.mm")
dm_m = read("HUD/TLDHUDDaemonMain.mm")
check("Paths: TLDHUDHelperExecutablePath 声明在位", "TLDHUDHelperExecutablePath" in hp_h)
check("Paths: helper 路径规则＝可执行档目录＋/TLDHUDDaemon",
      'stringByAppendingPathComponent:@"TLDHUDDaemon"' in hp_m)
check("Paths: helper 是自身时返回自身",
      'isEqualToString:@"TLDHUDDaemon"' in hp_m)
check("Paths: 模板路径按可执行档目录找（不用 NSBundle）",
      "TLDHUDDaemonPlistTemplatePath" in hp_m
      and "stringByDeletingLastPathComponent" in hp_m)
check("Paths: .mm 里无 pathForResource: 调用",
      "pathForResource:@" not in hp_m)
check("Helper: spawn 目标 4 处全用 TLDHUDHelperExecutablePath",
      hh_m.count("TLDHUDHelperExecutablePath()") == 4,
      str(hh_m.count("TLDHUDHelperExecutablePath()")))
check("Helper: 主 App 侧不用 _NSGetExecutablePath 的原值写 plist",
      "TLDHUDExecutablePath()" not in hh_m)
check("Helper: 0.2.1 always-rewrite 日志在位",
      "rewriting daemon plist (always on Enable)" in hh_m)
check("Helper: unload-before-load 在位",
      "launchctl unload (best-effort before reload)" in hh_m)
check("Helper: load 后 3 秒复核在位",
      "daemon started after launchctl load (3s check)" in hh_m
      and "daemon did not start after launchctl load (3s check)" in hh_m)
check("DaemonMain: 无 no-arg UIApplicationMain 分支",
      "UIApplicationMain(" not in dm_m)
check("DaemonMain: bare 运行记版本行",
      "no mode given" in dm_m and "TLDHUD_VERSION_STRING" in dm_m)
check("DaemonMain: -hud/-check/-exit/-install-daemon 四模式在位",
      all(s in dm_m for s in ['"-hud"', '"-check"', '"-exit"', '"-install-daemon"']))
check("DaemonMain: InstallDaemonPlist 用自身路径（helper 进程内正确）",
      dm_m.count("TLDHUDExecutablePath()") == 2,
      str(dm_m.count("TLDHUDExecutablePath()")))
check("DaemonMain: SpringBoard 重启后重拉在位",
      "SBSpringBoardDidLaunchNotification" in dm_m)
for s in ["com.ycwl.Lyrics.hud", "com.ycwl.Lyrics.hud.dismissal",
          "com.ycwl.Lyrics.hud.plist", "com.ycwl.Lyrics.hud.log",
          "com.ycwl.Lyrics.hud.pid"]:
    check(f"新 ID 在位：{s}",
          s in hp_m or s in read("HUD/TLDHUDLog.mm") or s in read("HUD/TLDHUDDaemon.plist")
          or s in read("HUD/TLDHUDMainApplication.mm"))
rv = read("HUD/TLDHUDRootViewController.mm")
check("RootVC: 自清检查认主 App bundle id com.ycwl.Lyrics（不是 daemon label）",
      '#define TLDHUD_MAIN_BUNDLE_ID @"com.ycwl.Lyrics"' in rv)
check("RootVC: fallback 文字是桌面歌词 2.0.2",
      "桌面歌詞 2.0.2" in rv or "桌面歌词 2.0.2" in rv)
check("RootVC: 锁屏只藏视图停定时器（无重建）",
      "hud: locked, view hidden" in rv and "hud: unlocked, view shown" in rv)
mw = read("HUD/TLDHUDMainWindow.mm")
check("MainWindow: _ignoresHitTest 改 NO（药丸要接长按，2.0.2）",
      "- (BOOL)_ignoresHitTest { return NO; }" in mw)
check("MainWindow: hitTest 只放行药丸框内触摸，其余 return nil",
      "pillFrameInWindow" in mw and "CGRectContainsPoint(pillFrame, point)" in mw
      and "return nil;" in mw)
snap = read("HUD/TLDHUDLyricsSnapshot.mm")
check("Snapshot: 分隔符表与 LyricStore 一字不差",
      '@" — ", @" – ", @" - ", @" · ", @"—", @"–"' in snap)
check("Snapshot: searchTerms 只拆 \" · \"",
      'rangeOfString:@" · "' in snap)
check("Snapshot: 只读（无 set 快照／无网络）",
      "lyric.snapshot" in snap and "NSURLConnection" not in snap
      and "NSURLSession" not in snap)
check("Snapshot: 测试文字模式读 floatingLyric.testTextEnabled",
      "floatingLyric.testTextEnabled" in snap
      and "懸浮測試 · 桌面歌詞" in snap or "悬浮测试 · 桌面歌词" in snap)
pl = read("HUD/TLDHUDDaemon.plist")
for s in ["com.ycwl.Lyrics.hud", "KeepAlive", "RunAtLoad", "root",
          "ThrottleInterval", "EnablePressuredExit", "RunningBoard",
          "<string>-hud</string>", "TLDHUDDaemon"]:
    check(f"daemon plist 模板含 {s}", s in pl)
check("daemon plist 模板 ProgramArguments[0] 是占位符（安装时重写）",
      "TrollLyricsDesk.app/TLDHUDDaemon" in pl)
ent = read("HUD/TLDHUDDaemon.entitlements")
for k in ["com.apple.security.application-groups",
          "com.apple.private.security.no-sandbox", "platform-application",
          "get-task-allow", "com.apple.private.persona-mgmt",
          "com.apple.backboard.client",
          "com.apple.springboard.accessibility-window-hosting",
          "com.apple.private.kernel.jetsam", "com.apple.private.memorystatus"]:
    check(f"daemon entitlements 含 {k}", k in ent)
check("daemon entitlements: application-identifier = com.ycwl.Lyrics",
      "<string>com.ycwl.Lyrics</string>" in ent)
ent_keys = re.findall(r"<key>([^<]+)</key>", ent)
check("daemon entitlements: 无 MediaRemote",
      not any("mediaremote" in k.lower() for k in ent_keys), str(ent_keys))
check("daemon entitlements: 无 hid.*（不做触摸）",
      not any(k.lower().startswith("hid.") for k in ent_keys))
for tbd, syms in {
        "HUD/Private/BackBoardServices.tbd": ["_BKSDisplayServicesStart"],
        "HUD/Private/GraphicsServices.tbd":
            ["_GSInitialize", "_GSEventInitialize", "_GSEventPushRunLoopMode"],
        "HUD/Private/SpringBoardServices.tbd":
            ["_SBSSpringBoardServerPort", "_SBGetScreenLockStatus"],
}.items():
    tbd_text = read(tbd)
    check(f"{tbd} 是 tapi-tbd-v3", "!tapi-tbd-v3" in tbd_text)
    for s in syms:
        check(f"{tbd} 导出 {s}", s in tbd_text)

print("\n== 4. FrontBoard 触发点停用 ==")
td = read("Overlay/TLDSAppDelegate.m")
check("kill-switch 常量 YES",
      "static const BOOL TLDSFrontBoardOverlayDisabled = YES;" in td)
check("didFinishLaunching：无 [self startFloatingOverlay] 调用",
      "[self startFloatingOverlay]" not in td)
check("didFinishLaunching：无 TLDSInstallNativeWindowFix() 调用",
      "TLDSInstallNativeWindowFix();" not in td)
check("锁屏监听包在 if (!TLDSFrontBoardOverlayDisabled) 里",
      td.count("if (!TLDSFrontBoardOverlayDisabled) {") == 3,
      str(td.count("if (!TLDSFrontBoardOverlayDisabled) {")))
for fn in ["startFloatingOverlay", "reactivateFloatingOverlayWithTrigger",
           "unlockRestoreFloatingOverlay", "foregroundVerifyFloatingWindow",
           "verifyFloatingVisibility"]:
    check(f"入口 early-return 在位：{fn}",
          "诊断2.0.0 FrontBoard 已停用" in td)
check("LC 分支直接定 compat／inApp，不试建场景",
      "LiveContainer 宿主：HUD 守护进程不可用，只走应用内歌词" in td)
check("trollstore／unknown 分支 reason 寫 daemon 路徑",
      "FrontBoard 场景已停用，悬浮歌词改由 HUD 守护进程" in td)
check("旧恢复方法本体保留（未删除）",
      "rebuildFloatingOverlay" in td and "createFloatingSceneWithIdentifier" in td)
sd = read("Overlay/TLDSSceneDelegate.m")
check("SceneDelegate：悬浮会话守卫在位",
      "FrontBoard 已停用：忽略悬浮场景会话" in sd)
check("SceneDelegate：主界面分支不动",
      "主界面场景已连接" in sd)

print("\n== 5. LC 硬性要求（isLiveContainer 不退化） ==")
for s in ['"LC_HOME_PATH"', '"/documents/applications/"', '"livecontainer"',
          '"/lcapps/"', 'NSClassFromString("LCAppDelegate")',
          '"TLDSLiveContainer"']:
    check(f"LyricStore.isLiveContainer 信号在位：{s}", s in ls)
sv = read("App/SettingsView.swift")
check("Settings：LC 下只显示禁用说明",
      "LiveContainer 模式下不可用" in sv)
check("Settings：HUD 区段在位",
      "悬浮歌词（HUD 守护进程）" in sv)
check("Settings：Enable／Disable 走后台队列",
      "TLDHUDSetEnabled(true)" in sv and "TLDHUDSetEnabled(false)" in sv)
check("Settings：状态读 TLDHUDIsEnabled＋PID",
      "TLDHUDIsEnabled()" in sv and "TLDHUDPIDPath()" in sv)
check("Settings：日志入口在位", "HUDLogView()" in sv)
check("Swift 调日志走非变参 wrapper（run 46053945402 教训）",
      "TLDHUDLogMessage" in read("HUD/TLDHUDLog.h")
      and "TLDHUDLogMessage" in read("HUD/TLDHUDLog.mm")
      and sv.count("TLDHUDLogMessage(") == 4)
swift_variadic = []
for dirpath, _, files in os.walk(os.path.join(ROOT, "App")):
    for fn in files:
        if fn.endswith(".swift"):
            c = open(os.path.join(dirpath, fn), encoding="utf-8").read()
            if re.search(r"TLDHUDLog\(", c):
                swift_variadic.append(fn)
check("Swift 里无变参 TLDHUDLog( 调用（Swift 调不了 C 变参）",
      not swift_variadic, str(swift_variadic))
hv = read("App/HUDLogView.swift")
check("HUDLogView：读 TLDHUDLogFilePath，末 120 行",
      "TLDHUDLogFilePath()" in hv and "120" in hv)
bh = read("Overlay/TrollLyricsDesk-Bridging-Header.h")
for h in ["TLDHUDHelper.h", "TLDHUDLog.h", "TLDHUDPaths.h"]:
    check(f"桥接头 import {h}", f'#import "{h}"' in bh)
check("App target HEADER_SEARCH_PATHS 含 $(SRCROOT)/HUD ×2",
      pbx.count('"$(SRCROOT)/HUD",') == 2,
      str(pbx.count('"$(SRCROOT)/HUD",')))

print("\n== 6. 保留项 ==")
check("激活：/api/verify 在位", "https://guhailong-repo.pages.dev/api/verify" in ls)
check("激活：TLD 码标记键在位", "tld.activated" in ls)
check("MediaRemote 跟随在位",
      "MediaRemoteAdapter" in read("App/TrollLyricsDeskApp.swift"))
check("LRCLIB 在位", "LRCLibClient" in read("Lyrics/LRCLibClient.swift"))
check("逐歌偏移在位", "timeOffset" in ls and "offsetKeyPrefix" in ls)
check("「·」修复：searchTerms 只拆 \" · \"",
      ls.count('range(of: " · ")') >= 1 and "searchTerms" in ls)
check("应用内歌词在位", "InAppLyricsRenderer" in read("Renderer/InAppLyricsRenderer.swift"))
check("小组件在位", os.path.exists(os.path.join(ROOT, "TrollLyricsWidget/TrollLyricsWidget.swift")))
about = read("App/AboutView.swift")
for s in ["China fly", "166623677", "@Guhailon"]:
    check(f"About 页保留：{s}", s in about)
check("锁屏歌词不恢复：无 LiveActivity 文件",
      not os.path.exists(os.path.join(ROOT, "LiveActivity/LyricsLiveActivity.swift"))
      and "NSSupportsLiveActivities" not in app_pl)
mr = read("Core/MediaRemoteBridge.swift") + read("MusicProviders/MediaRemoteAdapter.swift")
check("@escaping 回调修法不动（build 23）",
      "@escaping" in read("MusicProviders/MediaRemoteAdapter.swift"))
check("显示名：HUD 守护进程悬浮歌词（两边一致）",
      ls.count("HUD 守护进程悬浮歌词") == 1
      and read("Compatibility/RuntimeEnvironment.swift").count("HUD 守护进程悬浮歌词") == 2)
stale_test = []
for d in ["HUD", "App", "Overlay", "Lyrics", "Core", "Renderer",
          "Compatibility", "Diagnostics", "PlaybackEngine", "MusicProviders",
          "TrollLyricsWidget", "TrollLyricsDesk"]:
    for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
        for fn in files:
            if fn.endswith((".swift", ".m", ".mm", ".h")):
                p = os.path.join(dirpath, fn)
                c = open(p, encoding="utf-8", errors="replace").read()
                if "桌面歌词 1.0.6" in c or "桌面歌詞 1.0.6" in c:
                    stale_test.append(os.path.relpath(p, ROOT))
check("无残留 1.0.6 测试文字（SettingsView／PiPLyricsRenderer 曾漏改）",
      not stale_test, str(stale_test))

print("\n== 7. pbxproj：daemon target ==")
check("pbxproj 大括号平衡", pbx.count("{") == pbx.count("}"))
defined = set(re.findall(r"^\t\t([0-9A-F]{24}) /\*", pbx, re.M))
referenced = set(re.findall(r"\b([0-9A-F]{24})\b", pbx))
# 已知 HEAD 就有的 dangling 引用（Widget phase 里的旧文件），不是本次引入
known_dangling = {"2AC9C558E40544F86D76B6FD"}
check("pbxproj 引用皆有定义（除已知旧 dangling）",
      not (referenced - defined - known_dangling),
      str(sorted(referenced - defined - known_dangling)[:5]))
check("daemon target product-type tool",
      'productType = "com.apple.product-type.tool";' in pbx)
check("daemon target 名 TLDHUDDaemon", 'name = "TLDHUDDaemon";' in pbx)
check("daemon entitlements 指到 HUD/TLDHUDDaemon.entitlements",
      'CODE_SIGN_ENTITLEMENTS = "HUD/TLDHUDDaemon.entitlements";' in pbx)
check("daemon OTHER_LDFLAGS 链 3 个 .tbd",
      all(s in pbx for s in [
          '"$(SRCROOT)/HUD/Private/BackBoardServices.tbd"',
          '"$(SRCROOT)/HUD/Private/GraphicsServices.tbd"',
          '"$(SRCROOT)/HUD/Private/SpringBoardServices.tbd"']))
check("daemon OTHER_LDFLAGS 链 Foundation＋UIKit（run 46037981048 教训："
      "tool target 不自动链 UIKit，缺了链接报 undefined symbols）",
      pbx.count('"-framework",\n\t\t\t\t\tFoundation,') == 2
      and pbx.count('"-framework",\n\t\t\t\t\tUIKit,') == 2)
check("daemon HEADER_SEARCH_PATHS 含 HUD/headers",
      '"$(SRCROOT)/HUD/headers"' in pbx)
check("daemon PRODUCT_BUNDLE_IDENTIFIER = com.ycwl.Lyrics.hud",
      "PRODUCT_BUNDLE_IDENTIFIER = com.ycwl.Lyrics.hud;" in pbx)
check("daemon SKIP_INSTALL = YES", "SKIP_INSTALL = YES;" in pbx)
app_sources = pbx_sources_files(pbx, "4821909E9BF9E73E471FEA84")
for f in ["TLDHUDHelper.mm", "TLDHUDPaths.mm", "TLDHUDLog.mm", "HUDLogView.swift"]:
    check(f"App Sources 含 {f}", f in app_sources, str(app_sources))
check("App Resources 含 TLDHUDDaemon.plist",
      "TLDHUDDaemon.plist in Resources" in pbx)
check("Embed HUD Daemon phase 在位（含 cp＋test -f）",
      "Embed HUD Daemon" in pbx
      and "TLDHUDDaemon" in pbx
      and 'test -f' in pbx)
check("App target 依赖 daemon target",
      "PBXTargetDependency" in pbx and "TLDHUDDaemon" in pbx)
print("\n== 7b. pbxproj：phase 文件集与 HEAD 对照（run 46052617013 教训："
      "手术曾吃掉 DiagnosticsView.swift 一行，导致 Swift 编译失败） ==")
try:
    head_pbx = git_out(["show", BASE + ":TrollLyricsDesk.xcodeproj/project.pbxproj"])

    def phase_ids(text, pid, kind):
        m = re.search(re.escape(pid) + r" /\* " + kind + r" \*/ = \{(.*?)\n\t\t\};",
                      text, re.S)
        return set(re.findall(r"\b([0-9A-F]{24})\b", m.group(1))) if m else set()

    app_src_now = phase_ids(pbx, "4821909E9BF9E73E471FEA84", "PBXSourcesBuildPhase")
    app_src_head = phase_ids(head_pbx, "4821909E9BF9E73E471FEA84", "PBXSourcesBuildPhase")
    check("App Sources：HEAD 的全在（一个不能少）",
          not (app_src_head - app_src_now),
          str(sorted(app_src_head - app_src_now)))
    check("App Sources：相对 build 30 无新增（build 31 未加新文件）",
          app_src_now == app_src_head,
          str(sorted(app_src_now - app_src_head)))
    res_now = phase_ids(pbx, "F667297ED3AB90EAC07798D4", "PBXResourcesBuildPhase")
    res_head = phase_ids(head_pbx, "F667297ED3AB90EAC07798D4", "PBXResourcesBuildPhase")
    check("App Resources：HEAD 的 Assets.xcassets 全在",
          not (res_head - res_now), str(sorted(res_head - res_now)))
    check("App Resources：与 HEAD 一致（无新增）",
          res_now == res_head, str(sorted(res_now - res_head)))
    # 其他 phase（Widget／daemon 除外）一个文件都不能少
    other_lost = []
    for kind in ["PBXSourcesBuildPhase", "PBXResourcesBuildPhase",
                 "PBXFrameworksBuildPhase", "PBXCopyFilesBuildPhase"]:
        for m in re.finditer(r"\t\t([0-9A-F]{24}) /\* " + kind + r" \*/ = \{",
                             head_pbx):
            pid = m.group(1)
            lost = phase_ids(head_pbx, pid, kind) - phase_ids(pbx, pid, kind)
            if lost:
                other_lost.append((kind, pid, sorted(lost)))
    check("其余 phase：无文件丢失", not other_lost, str(other_lost))
except subprocess.CalledProcessError as e:
    open_item("git show HEAD pbxproj 读不到，phase 对照跳过", str(e))
sch = read("TrollLyricsDesk.xcodeproj/xcshareddata/xcschemes/TrollLyricsDesk.xcscheme")
check("scheme 含 daemon BuildActionEntry",
      "TLDHUDDaemon" in sch and sch.count("<BuildActionEntry") == 3,
      str(sch.count("<BuildActionEntry")))
check("scheme 仍含 App＋Widget",
      "TrollLyricsDesk.app" in sch and "TrollLyricsWidget.appex" in sch)

print("\n== 8. build.yml：daemon 签名 ==")
by = read(".github/workflows/build.yml")
check("build.yml 签 daemon（自有 entitlements）",
      'zsign -a -f -e HUD/TLDHUDDaemon.entitlements "$APP/TLDHUDDaemon"' in by)
check("build.yml 印 daemon entitlements",
      'codesign -d --entitlements - "$APP/TLDHUDDaemon"' in by)
check("build.yml 验 helper 在位（test -f）",
      'test -f "$APP/TLDHUDDaemon"' in by)
check("build.yml 验 3 个 dSYM",
      "EXPECTED 3 dSYMs" in by)
for s in ["桌面歌词-2.0.2.ipa", "桌面歌词-2.0.2-dSYM.zip",
          "name: 桌面歌词-2.0.2"]:
    check(f"build.yml 用 2.0.2 檔名：{s}", s in by)
check("build.yml 无 2.0.1 檔名", "桌面歌词-2.0.1" not in by)

print("\n== 9. 署名／禁区 ==")
lic = read("LICENSE")
check("LICENSE 有 Lessica 署名行", "Copyright (c) 2023 Lessica" in lic)
check("LICENSE 仍是 MIT（顾海龙集团）",
      "Copyright (c) 2026 顾海龙集团" in lic and "MIT License" in lic)
code_dirs = ["HUD", "App", "Overlay", "Lyrics", "Core", "Renderer",
             "Compatibility", "Diagnostics", "PlaybackEngine", "MusicProviders",
             "TrollLyricsWidget", "TrollLyricsDesk"]
bad_x = []
for d in code_dirs:
    for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
        for fn in files:
            p = os.path.join(dirpath, fn)
            c = open(p, encoding="utf-8", errors="replace").read()
            if re.search(r"xexternalhud|XEHUD", c, re.I):
                bad_x.append(os.path.relpath(p, ROOT))
check("XExternalHUD 零复制（代码区）", not bad_x, str(bad_x))
bad_j = []
for d in code_dirs:
    for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
        for fn in files:
            if fn.endswith((".mm", ".h", ".swift")):
                p = os.path.join(dirpath, fn)
                c = open(p, encoding="utf-8", errors="replace").read()
                if "JetsamHelper" in c or "BypassJetsamByProcess" in c:
                    bad_j.append(os.path.relpath(p, ROOT))
check("JetsamHelper 死代码不抄（代码区）", not bad_j, str(bad_j))
bad_tok = []
for d in ["HUD", "App"]:
    for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
        for fn in files:
            p = os.path.join(dirpath, fn)
            if "38473" in open(p, encoding="utf-8", errors="replace").read():
                bad_tok.append(os.path.relpath(p, ROOT))
check("无旧 widget token（38473）", not bad_tok, str(bad_tok))
design = read("docs/2.0.0-MERGE-DESIGN.md")
for s in ["TLDHUDHelperExecutablePath", "一律重寫", "LiveContainer",
          "不再留開關", "zsign", "2.0.0"]:
    check(f"设计文档提及：{s}", s in design)


print("\n== 11. Keychain 激活持久化（2.0.1 主任务） ==")
kc = read("App/ActivationKeychain.swift")
check("Keychain 文件在位", os.path.exists(os.path.join(ROOT, "App/ActivationKeychain.swift")))
check("Keychain: import Security", "import Security" in kc)
check("Keychain: generic password", "kSecClassGenericPassword" in kc)
check("Keychain: service = App 自身标识 com.ycwl.Lyrics",
      '"com.ycwl.Lyrics"' in kc)
check("Keychain: account 固定为激活标记键 tld.activated",
      '"tld.activated"' in kc)
for fn in ["static func read()", "static func write(_ type: String)",
           "static func syncWithDefaults()"]:
    check(f"Keychain 接口在位：{fn}", fn in kc)
check("Keychain: 读失败返回 nil（无 throw）", "throw" not in kc)
check("Keychain: 无 try 表达式（全静默）",
      re.search(r"\btry\s+[A-Za-z_]", kc) is None
      and "try?" not in kc and "try!" not in kc)
check("Keychain: Add 已存在则 Update",
      "SecItemAdd" in kc and "errSecDuplicateItem" in kc and "SecItemUpdate" in kc)
check("Keychain: 不同步 iCloud（无 synchronizable）",
      "kSecAttrSynchronizable" not in kc)
check("Keychain: 无自定义 access group（不新增 entitlements）",
      "kSecAttrAccessGroup" not in kc)
check("Keychain: 注释写明删 App 后保留的依据",
      "删除 App 后仍保留" in kc)
check("Keychain: 注释写明签名身份变了的局限",
      "签名身份变了" in kc)
for ent_rel in ["TrollLyricsDesk/TrollLyricsDesk.entitlements",
                "TrollLyricsWidget/TrollLyricsWidget.entitlements"]:
    check(f"Keychain: {ent_rel} 无 keychain 字串（entitlements 未动）",
          "keychain" not in read(ent_rel).lower())
av = read("App/ActivationView.swift")
check("激活成功后同步写 Keychain（markActivated 下一行）",
      "ActivationStore.markActivated(type: type)\n" in av
      and "ActivationKeychain.write(type)" in av)
check("激活页：写 Keychain 在 markActivated 之后",
      av.index("ActivationStore.markActivated(type: type)")
      < av.index("ActivationKeychain.write(type)"))
rt = read("App/TrollLyricsDeskApp.swift")
check("启动恢复：makeRootViewController 调 syncWithDefaults()",
      "ActivationKeychain.syncWithDefaults()" in rt)
check("启动恢复：sync 在 ActivationGateView 构造之前",
      rt.index("ActivationKeychain.syncWithDefaults()")
      < rt.index("let root = ActivationGateView"))
check("Widget 安全：LyricStore.swift 不引用 ActivationKeychain"
      "（Widget target 也编它，引用会断 Widget 编译）",
      "ActivationKeychain" not in ls)
check("Keychain 文件只进 App target（不在 Widget Sources 里）",
      "ActivationKeychain.swift in Sources" in pbx
      and pbx.count("ActivationKeychain.swift in Sources") == 1)

print("\n== 12. 主页面死开关整组藏掉（2.0.1 追加） ==")
pd = read("App/PlaybackDashboardView.swift")
check("主页面：无「显示悬浮歌词窗」Toggle",
      '"显示悬浮歌词窗"' not in pd)
check("主页面：无「固定悬浮窗位置」Toggle",
      '"固定悬浮窗位置"' not in pd)
check("主页面：无旧「悬浮窗歌词颜色」标签（2.0.2 真取色器叫「悬浮歌词颜色」，见 §14）",
      '"悬浮窗歌词颜色"' not in pd)
check("主页面：无「长按拖动／双击隐藏」旧提示字串",
      "悬浮窗口 · 已固定 · 双击隐藏" not in pd
      and "悬浮窗口 · 长按拖动 · 双击隐藏" not in pd)
check("主页面：旧说明已撤下（换成真正能用的 HUD 区段，见 §13）",
      "悬浮歌词药丸只从设置页「悬浮歌词（HUD 守护进程）」里启用打开" not in pd)
for k in ["floatingLyric.enabled", "floatingLyric.positionLocked",
          "floatingLyric.textColorHex"]:
    check(f"主页面：存储键未动：{k}", f'"{k}"' in pd)
check("主页面：@AppStorage 声明仍在（只改 UI 呈现）",
      "@AppStorage(\"floatingLyric.enabled\"" in pd
      and "@AppStorage(\"floatingLyric.positionLocked\"" in pd)
check("死开关的唯一消费方仍是已死的 FloatingLyricViewController",
      "floatingLyric.enabled" in read("Overlay/FloatingLyricViewController.swift")
      and "floatingLyric.positionLocked" in read("Overlay/FloatingLyricViewController.swift"))

print("\n== 10. diff 范围（相对 c6340d0） ==")
try:
    diff_names = git_out(["diff", "--name-only", BASE]).split()
    check("diff 文件数合理（底子 3 文件＋六项改动＋版本）", 0 < len(diff_names) <= 22, str(len(diff_names)))
    print("changed files:", len(diff_names))
    for n in diff_names:
        print("  ", n)
except subprocess.CalledProcessError as e:
    open_item("git diff 读不到（未提交时正常）", str(e))


print("\n== 13. HUD Enable 在主页面（build 31，Lee 定放主页面） ==")
pd = read("App/PlaybackDashboardView.swift")
cv = read("App/ContentView.swift")
sv = read("App/SettingsView.swift")
for needle in ["悬浮歌词（HUD 守护进程）", "守护进程状态", "启用 HUD 守护进程",
               "停用 HUD 守护进程", "查看守护进程日志", "固定位置", "悬浮歌词颜色",
               "LiveContainer 模式下不可用——宿主跑不了 root 守护进程",
               "启用后歌词药丸显示在桌面与其它 App 之上",
               "每次启用都会重写 daemon 配置"]:
    check(f"主页面：有 HUD 文案：{needle}", needle in pd)
for needle in ["TLDHUDSetEnabled(true)", "TLDHUDSetEnabled(false)",
               "TLDHUDIsEnabled()", "TLDHUDPIDPath()", "TLDHUDLogMessage(",
               "HUDLogView()", "refreshHUDStatus()",
               "运行中（pid"]:
    check(f"主页面：有 HUD 调用：{needle}", needle in pd)
check("主页面：HUD 区段在非 LC 分支（else）内",
      "} else {" in pd and "悬浮歌词（HUD 守护进程）" in pd)
check("主页面：LC 分支仍是应用内歌词（未动）",
      "LiveContainer · 应用内歌词模式" in pd)
check("主页面：HUD 状态 @State 三件在位",
      '@State private var hudStatusText' in pd
      and '@State private var hudRunning' in pd
      and '@State private var hudBusy' in pd)
check("主页面：死开关三键 @AppStorage 声明仍在（只改 UI 呈现）",
      '@AppStorage("floatingLyric.enabled"' in pd
      and '@AppStorage("floatingLyric.positionLocked"' in pd
      and '@AppStorage("floatingLyric.textColorHex"' in pd)
check("ContentView 未动（HUD 没放设置页，Lee 改放主页面）",
      "悬浮歌词（HUD 守护进程）" not in cv
      and "启用 HUD 守护进程" not in cv)
check("SettingsView 死页面未动（HUD 区段仍在原处，未删）",
      "悬浮歌词（HUD 守护进程）" in sv)
check("SettingsView 仍无实例化（导航事实未变，死页面就是死页面）",
      sv.count("SettingsView(") == 0
      and pd.count("SettingsView(") == 0
      and cv.count("SettingsView(") == 0)
check("HUD 调用只调现成 helper（无新 daemon 逻辑）",
      "TLDHUDSetEnabled" in pd and "launchctl" not in pd)

print("\n== 14. 2.0.2：药丸拖动／固定／颜色／透明度／字号／关于页 ==")
rv = read("HUD/TLDHUDRootViewController.mm")
snap_h = read("HUD/TLDHUDLyricsSnapshot.h")
snap_m = read("HUD/TLDHUDLyricsSnapshot.mm")
pd = read("App/PlaybackDashboardView.swift")
about = read("App/AboutView.swift")

print("-- 14a 长按拖动 --")
check("拖动：UILongPressGestureRecognizer 在 pill 上",
      "UILongPressGestureRecognizer" in rv and "handlePillLongPress:" in rv)
check("拖动：minimumPressDuration 0.5",
      "minimumPressDuration = 0.5" in rv)
check("拖动：allowableMovement 放大（按住后手指已动也不判失败）",
      "allowableMovement = 10000" in rv)
check("拖动：pill 是 ivar（不再是 viewDidLoad 局部变量）",
      "UIView *_pill;" in rv)
check("拖动：两根可调约束存成 ivar（top＋centerX）",
      "_pillTopConstraint" in rv and "_pillCenterXConstraint" in rv)
check("拖动：Began 给半透明反馈（alpha 0.6），Ended 恢复 1.0",
      "_pill.alpha = 0.6" in rv and "_pill.alpha = 1.0" in rv)
check("拖动：Changed 跟手移动（movePillToCenter＋layoutIfNeeded）",
      "movePillToCenter:" in rv and "[self.view layoutIfNeeded]" in rv)
check("拖动：Ended/Cancelled 松手保存位置",
      "savePillPosition" in rv)
check("拖动：位置夹在屏幕内（UIScreen bounds 夹）",
      "clampedPillCenterForCenter:" in rv
      and "[[UIScreen mainScreen] bounds]" in rv)
check("拖动：位置写 App Group 新键 hudPill.positionX/Y",
      '"hudPill.positionX"' in rv and '"hudPill.positionY"' in rv)
check("拖动：位置读写走 suite（NSUserDefaults initWithSuiteName）",
      'initWithSuiteName:TLDHUD_PILL_GROUP_ID' in rv
      and 'TLDHUD_PILL_GROUP_ID @"group.com.hailong.TrollLyricsDesk"' in rv)
check("拖动：启动后首次布局读回恢复（viewDidLayoutSubviews）",
      "viewDidLayoutSubviews" in rv and "applySavedPillPositionIfNeeded" in rv)
check("拖动：只加长按，无点按／双击手势",
      "UITapGestureRecognizer" not in rv)
check("拖动：pillFrameInWindow 供窗口 hitTest 用",
      "pillFrameInWindow" in rv and "pillFrameInWindow" in read("HUD/TLDHUDRootViewController.h"))

print("-- 14b 固定位置开关 --")
check("固定：主页面有新键 hudPill.positionLocked 的 @AppStorage（默认关）",
      '@AppStorage("hudPill.positionLocked", store: LyricStore.defaults)' in pd
      and "private var hudPillPositionLocked = false" in pd)
check("固定：主页面有「固定位置」Toggle",
      'Toggle("固定位置", isOn: $hudPillPositionLocked)' in pd)
check("固定：Toggle 在 HUD 区段内（LC 说明之后、日志入口之前）",
      pd.index("LiveContainer 模式下不可用——宿主跑不了 root 守护进程")
      < pd.index('Toggle("固定位置"')
      < pd.index("查看守护进程日志"))
check("固定：旧死键 floatingLyric.positionLocked 声明一字未动",
      '@AppStorage("floatingLyric.positionLocked", store: LyricStore.defaults)' in pd
      and "private var positionLocked = false" in pd)
check("固定：手势处理里锁住直接 return（无拖动反馈）",
      "if (_positionLocked) return;" in rv)
check("固定：每秒 tick 重读标志（onTimerTick）",
      "_positionLocked = [self readPositionLocked];" in rv)
check("固定：解锁时也重读标志（hudDidUnlock；三处重读：viewDidLoad＋tick＋unlock）",
      rv.count("_positionLocked = [self readPositionLocked];") == 3,
      str(rv.count("_positionLocked = [self readPositionLocked];")))

print("-- 14c 歌词颜色取色器 --")
check("颜色：主页面有「悬浮歌词颜色」ColorPicker（复用 lyricTextColor）",
      'ColorPicker("悬浮歌词颜色", selection: lyricTextColor)' in pd)
check("颜色：复用旧键 floatingLyric.textColorHex，未另起新键",
      '"floatingLyric.textColorHex"' in pd
      and "hudPill.textColor" not in pd)
check("颜色：取色器在 HUD 区段内（LC 说明之后、日志入口之前）",
      pd.index("LiveContainer 模式下不可用——宿主跑不了 root 守护进程")
      < pd.index('ColorPicker("悬浮歌词颜色"')
      < pd.index("查看守护进程日志"))
check("颜色：daemon 每 tick 读色（pillLyricColor 读 floatingLyric.textColorHex）",
      "pillLyricColor" in rv and '"floatingLyric.textColorHex"' in rv)
check("颜色：缺省（键不存在）保持白色",
      "objectForKey:TLDHUD_PILL_TEXT_COLOR_KEY" in rv
      and "return [UIColor whiteColor];" in rv)
check("颜色：三档 alpha 照旧（0.65／0.45／1.0），只换白底为读到的颜色",
      "[baseColor colorWithAlphaComponent:0.65]" in rv
      and "[baseColor colorWithAlphaComponent:0.45]" in rv
      and "NSForegroundColorAttributeName : baseColor," in rv)
check("颜色：fallback 测试字也跟色（仍 15pt 不动）",
      "[self pillLyricColor]" in rv
      and "monospacedDigitSystemFontOfSize:15" in rv)

print("-- 14d 透明度（药丸背景＋歌词字） --")
check("透明度：daemon 每 tick 读 floatingLyric.cardOpacity 应用到药丸背景",
      "pillCardAlpha" in rv and '"floatingLyric.cardOpacity"' in rv
      and "_pill.backgroundColor" in rv)
check("透明度：药丸背景缺省 0.75（不是滑块初值 0.23）",
      "TLDHUD_PILL_DEFAULT_CARD_ALPHA 0.75" in rv
      and "return TLDHUD_PILL_DEFAULT_CARD_ALPHA;" in rv)
check("透明度：药丸背景 alpha 夹 0–1",
      "if (alpha < 0) alpha = 0;" in rv and "if (alpha > 1) alpha = 1;" in rv)
check("透明度：快照 opacity 字段进 TLDHUDLyricsDisplay",
      "double opacity;" in snap_h)
check("透明度：快照解析读 json[opacity]，缺省 1.0，夹 0–1",
      'json[@"opacity"]' in snap_m and "double opacity = 1.0;" in snap_m
      and "if (opacity < 0) opacity = 0;" in snap_m
      and "if (opacity > 1) opacity = 1;" in snap_m)
check("透明度：歌词 label alpha = 快照 opacity（与颜色三档乘算）",
      "_testLabel.alpha = lyrics.opacity;" in rv)
check("透明度：fallback 无快照时 label alpha 回 1.0",
      "_testLabel.alpha = 1.0;" in rv)
check("透明度：主 App 快照确实带 opacity（LyricStore／poll 写入）",
      "var opacity: Double" in read("Lyrics/LyricStore.swift")
      and "opacity: opacity," in read("PlaybackEngine/PlaybackCoordinator.swift"))

print("-- 14e 歌词字体大小 --")
check("字号：快照 fontSize 字段进 TLDHUDLyricsDisplay",
      "double fontSize;" in snap_h)
check("字号：快照解析读 json[fontSize]，缺省 23.0，夹 14–36",
      'json[@"fontSize"]' in snap_m and "double fontSize = 23.0;" in snap_m
      and "if (fontSize < 14) fontSize = 14;" in snap_m
      and "if (fontSize > 36) fontSize = 36;" in snap_m)
check("字号：当前行就用 fontSize（boldSystemFontOfSize:baseSize）",
      "CGFloat baseSize = lyrics.fontSize;" in rv
      and "[UIFont boldSystemFontOfSize:baseSize]" in rv)
check("字号：歌名／上下行按 11/17 同比例缩放",
      "CGFloat smallSize = baseSize * 11.0 / 17.0;" in rv
      and "[UIFont systemFontOfSize:smallSize" in rv)
check("字号：fallback 测试字保持 15pt 不动",
      "monospacedDigitSystemFontOfSize:15" in rv)
check("字号：主 App 快照确实带 fontSize（LyricStore／poll 写入）",
      "var fontSize: Double" in read("Lyrics/LyricStore.swift")
      and "fontSize: fontSize" in read("PlaybackEngine/PlaybackCoordinator.swift"))

print("-- 14f 关于页删日志行 --")
check("关于页：无「日志」入口字串（入口行已删；注释里的「日志」二字不算）",
      '"日志"' not in about and 'Label("日志"' not in about)
check("关于页：无 LogView() 调用",
      "LogView()" not in about)
check("关于页：其余四行都在（作者／当前版本／加入官方群组／Telegram 频道）",
      all(s in about for s in ["作者", "当前版本", "加入官方群组", "Telegram 频道"]))
check("关于页：LyricLogger 写日志逻辑未停（Documents/TrollLyricsDesk.log）",
      "TrollLyricsDesk.log" in read("TrollLyricsDesk/LyricLogger.swift"))
check("关于页：主页面「查看守护进程日志」保留不动",
      "查看守护进程日志" in pd and "HUDLogView()" in pd)


print("\n== 15. 2.0.2：歌词简繁切换 ==")
ls = read("Lyrics/LyricStore.swift")
cv = read("App/ContentView.swift")
snap_m = read("HUD/TLDHUDLyricsSnapshot.mm")
check("简繁：新键 lyric.displayScript（未复用别的键）",
      'static let displayScriptKey = "lyric.displayScript"' in ls)
check("简繁：默认简体（键不存在时 displayScriptIsTraditional 为 false）",
      'defaults?.string(forKey: displayScriptKey) == "Hant"' in ls)
check("简繁：转换走 CFStringTransform，繁→简 Hant-Hans／简→繁 Hans-Hant",
      'CFStringTransform(mutable, nil, transform, false)' in ls
      and '"Hant-Hans"' in ls and '"Hans-Hant"' in ls)
check("简繁：转换只返回副本，不改原文（NSMutableString 拷贝）",
      "NSMutableString(string: text)" in ls)
check("简繁：设置页歌词区段有「歌词简繁」分段选择器（简体／繁体）",
      'Picker("歌词简繁", selection: $displayScript)' in cv
      and 'Text("简体").tag("Hans")' in cv
      and 'Text("繁体").tag("Hant")' in cv
      and ".pickerStyle(.segmented)" in cv)
check("简繁：设置页开关写 App Group 新键，默认 Hans",
      '@AppStorage("lyric.displayScript", store: LyricStore.defaults)' in cv
      and 'private var displayScript = "Hans"' in cv)
check("简繁：设置页开关与三滑块同区段（歌词透明度／字体大小／悬浮窗透明度）",
      cv.index('Picker("歌词简繁"') > cv.index('"歌词透明度"')
      and cv.index('Picker("歌词简繁"') > cv.index('"悬浮窗透明度"'))
check("简繁：主页面歌名／歌手显示时转换（原文不动）",
      "Text(LyricStore.convertForDisplay(topText))" in pd
      and "Text(LyricStore.convertForDisplay(bottomText))" in pd)
check("简繁：应用内歌词行显示时转换",
      "LyricStore.convertForDisplay(" in read("Renderer/InAppLyricsRenderer.swift"))
check("简繁：daemon 读同一把键并用 CFStringTransform 转显示字串",
      '"lyric.displayScript"' in snap_m
      and 'CFSTR("Hans-Hant")' in snap_m and 'CFSTR("Hant-Hans")' in snap_m)
check("简繁：daemon 只转四行显示字串（songLine／current／previous／next）",
      "TLDHUDApplyScriptToDisplay" in snap_m
      and snap_m.count("TLDHUDApplyScriptToDisplay(display);") == 2
      and snap_m.count("TLDHUDApplyScriptToDisplay(testDisplay);") == 1)
check("简繁：daemon 身份键仍从原文派生（未转 title／artist）",
      "TLDHUDStableSongIdentity(title, artist)" in snap_m
      and "display.songIdentity = identity;" in snap_m)
check("简繁：搜索／缓存／换歌判定／偏移键不受影响（poll 与搜索页不调转换）",
      "convertForDisplay" not in read("PlaybackEngine/PlaybackCoordinator.swift")
      and "convertForDisplay" not in read("App/LyricsSearchView.swift"))
check("简繁：快照 struct 未加字段（title／artist／lyrics[] 仍存原文）",
      "var displayScript " not in ls and "var displayScript\n" not in ls
      and "var opacity: Double" in ls and "var fontSize: Double" in ls)
check("简繁：LyricStore.searchTerms／stableSongIdentity 内无转换调用",
      "convertForDisplay" not in ls.split("static func searchTerms")[1].split("static func")[0]
      if "static func searchTerms" in ls else False)


print("\n== 16. 2.0.2 底子：ChatGPT 建议（PID 校验＋Enable 健壮性） ==")
dm = read("HUD/TLDHUDDaemonMain.mm")
hh = read("HUD/TLDHUDHelper.mm")
vh = read("HUD/TLDHUDVersion.h")
check("底子：TLDHUDOwnPID 用 proc_pidpath＋realpath 核对可执行路径",
      "TLDHUDOwnPID" in dm and "proc_pidpath" in dm and "realpath" in dm
      and "strcmp(expected, resolved) == 0" in dm)
check("底子：TLDHUDOwnPID 头文件齐全（libproc／limits／stdlib，无需补 import）",
      "#import <libproc.h>" in dm and "#import <limits.h>" in dm
      and "#import <stdlib.h>" in dm)
check("底子：-exit 先验 PID，不是本进程就拒绝并记日志",
      "hud: refusing stale or unverified PID" in dm)
check("底子：-check 先验 PID，未通过直接回 EXIT_SUCCESS（不再谎报活着）",
      "if (!TLDHUDOwnPID(pid)) return EXIT_SUCCESS;" in dm)
check("底子：waitpid 后只在 WIFEXITED 时读退出码",
      "if (w != -1 && WIFEXITED(status))" in hh)
check("底子：TLDHUDIsEnabled 由 status != 0 改 status == 1",
      "return status == 1;" in hh and "return status != 0;" not in hh)
check("底子：Enable 只有 plist 装成功才走 launchctl unload/load",
      "BOOL installed = TLDHUDInstallDaemonPlist();" in hh
      and "if (installed && " in hh)
check("底子：launchctl load 失败直接返回（走直启 -hud 兜底）",
      "if (loadRc != 0) return;" in hh)
check("底子：TLDHUDVersion.h 注释指向 check_2.0.2.py",
      "check_2.0.2.py" in vh)
try:
    msgs = git_out(["log", "--format=%s", BASE + "..HEAD"]).splitlines()
    check("底子：分支顺序正确（底子提交第一，功能提交第二）",
          len(msgs) == 2 and msgs[1].startswith("ChatGPT 建议")
          and msgs[0].startswith("2.0.2/build 32"), str(msgs))
except subprocess.CalledProcessError as e:
    open_item("git log 读不到，分支顺序断言跳过", str(e))


print("\n== OPEN（需 macOS／真机） ==")
open_item("macOS 编译（xcodebuild archive）：Linux 无 Xcode", "CI 见分晓")
open_item("daemon dSYM 是否进 archive（3 个）", "build.yml 已断言，CI 日志为准")
open_item("真机：重装后免激活（全新安装激活一次 → 删 App → 重装 → 不弹激活页）",
          "见 RUN_2.0.2.md 清单，等 Lee")
open_item("真机：药丸长按拖动／固定／颜色／透明度／字号（2.0.2 六项）",
          "见 RUN_2.0.2.md 清单，等 Lee")
open_item("真机：关于页无日志行，主页面查看守护进程日志能点开",
          "见 RUN_2.0.2.md 清单，等 Lee")
open_item("真机：Enable／stale-plist 回归／五项歌词／10 次锁解／30 分钟后台",
          "见 RUN_2.0.0.md 清单，等 Lee")
open_item("真机：LC 模式下 daemon 不出现", "见 RUN_2.0.0.md 清单，等 Lee")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens))
sys.exit(1 if fails else 0)
