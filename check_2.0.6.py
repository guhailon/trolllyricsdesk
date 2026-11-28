#!/usr/bin/env python3
"""Self-check for TrollLyricsDesk 2.0.6/build 36（卡拉OK修复：LRCLIB lyricsfile 逐字＋缓存键 v2＋诊断日志＋歌卡归一化复用）。

Base = 643037a (2.0.5/build 35) + 四项修复＋升版 35→36 / 2.0.5→2.0.6。
Run from the repo root:  python3 check_2.0.6.py
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
BASE = "643037a"
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
    check(f"{rel}: version 2.0.6", pl.get("CFBundleShortVersionString") == "2.0.6",
          str(pl.get("CFBundleShortVersionString")))
    check(f"{rel}: build 36", pl.get("CFBundleVersion") == "36",
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
check("LyricStore.versionTag = build 36（2.0.6）",
      'static let versionTag = "build 36（2.0.6）"' in ls)
check("LyricStore.testText() 版本 2.0.6",
      "悬浮测试 · 桌面歌词 2.0.6 ·" in ls)
check("SettingsView 测试文字说明版本 2.0.6",
      "悬浮测试 · 桌面歌词 2.0.6" in read("App/SettingsView.swift"))
check("PiPLyricsRenderer 测试文字版本 2.0.6",
      "悬浮测试 · 桌面歌词 2.0.6" in read("Renderer/PiPLyricsRenderer.swift"))
vh = read("HUD/TLDHUDVersion.h")
check("TLDHUDVersion.h: 2.0.6", 'TLDHUD_VERSION_STRING @"2.0.6"' in vh)
check("TLDHUDVersion.h: build 36", 'TLDHUD_BUILD_STRING @"36"' in vh)
check("TLDHUDVersion.h: 无 2.0.0", "2.0.0" not in vh)
check("TLDHUDVersion.h: 无 2.0.3 版本字串", '@"2.0.3"' not in vh)
check("TLDHUDVersion.h: 无 build 29/30/31/32/33/34/91",
      '"29"' not in vh and '"30"' not in vh and '"31"' not in vh
      and '"32"' not in vh and '"33"' not in vh and '"34"' not in vh
      and '"91"' not in vh)
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: MARKETING_VERSION = 2.0.6 ×6（App＋Widget＋daemon 各 2）",
      pbx.count("MARKETING_VERSION = 2.0.6;") == 6,
      str(pbx.count("MARKETING_VERSION = 2.0.6;")))
check("pbxproj: CURRENT_PROJECT_VERSION = 36 ×6",
      pbx.count("CURRENT_PROJECT_VERSION = 36;") == 6,
      str(pbx.count("CURRENT_PROJECT_VERSION = 36;")))
check("pbxproj: 无 2.0.3 / build 30/31/32/33/34 版本号",
      "MARKETING_VERSION = 2.0.3" not in pbx
      and "CURRENT_PROJECT_VERSION = 30" not in pbx
      and "CURRENT_PROJECT_VERSION = 31" not in pbx
      and "CURRENT_PROJECT_VERSION = 32" not in pbx
      and "CURRENT_PROJECT_VERSION = 33" not in pbx
      and "CURRENT_PROJECT_VERSION = 34" not in pbx
      and "CURRENT_PROJECT_VERSION = 91" not in pbx)

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
check("RootVC: fallback 文字是桌面歌詞 2.0.6",
      "桌面歌詞 2.0.6" in rv)
check("RootVC: fallback 文字无旧版 2.0.3",
      "桌面歌詞 2.0.3" not in rv)
check("RootVC: 锁屏只藏视图停定时器（无重建）",
      "hud: locked, view hidden" in rv and "hud: unlocked, view shown" in rv)
mw = read("HUD/TLDHUDMainWindow.mm")
check("MainWindow: _ignoresHitTest 改 NO（药丸要接拖动，2.0.3）",
      "- (BOOL)_ignoresHitTest { return NO; }" in mw)
check("MainWindow: hitTest 只放行药丸框内触摸，其余 return nil",
      "pillFrameInWindow" in mw and "insidePill" in mw
      and "return nil;" in mw)
check("MainWindow/RootVC: 不用 CoreGraphics 外部符号（daemon 不链它，run 46109741847）",
      "CGRectContainsPoint(" not in mw and "CGRectIsEmpty(" not in mw
      and "CGRectZero(" not in read("HUD/TLDHUDRootViewController.mm"))
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
check("daemon entitlements: 有 5 个 hid.*（2.0.5 全量触摸，见 §18）",
      {"com.apple.private.hid.client.event-dispatch",
       "com.apple.private.hid.client.event-filter",
       "com.apple.private.hid.client.event-monitor",
       "com.apple.private.hid.client.service-protected",
       "com.apple.private.hid.manager.client"} <= set(ent_keys))
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
check("unknown 分支 fail-closed：记 compat／inApp，不再记原生候选",
      'setRunMode:@"compat"' in td
      and "安装来源未知，禁止原生 HUD" in td)
check("unknown 分支：启动路径不再写 native-candidate（只剩已停用的复核死代码里一处）",
      td.count('setRunMode:@"native-candidate"') == 1,
      str(td.count('setRunMode:@"native-candidate"')))
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
check("Settings：未知环境只显示禁用说明（补丁正面证据门控）",
      "当前环境未确认具备原生 HUD 权限" in sv
      and "RuntimeEnvironment.canUseNativeHUD" in sv)
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
    check("App Sources：相对 cf78428 无新增（补丁未加新源文件）",
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
for s in ["桌面歌词-2.0.6.ipa", "桌面歌词-2.0.6-dSYM.zip",
          "name: 桌面歌词-2.0.6"]:
    check(f"build.yml 用 2.0.6 檔名：{s}", s in by)
check("build.yml 无 2.0.1 檔名", "桌面歌词-2.0.1" not in by)
check("build.yml 无 2.0.3 檔名", "桌面歌词-2.0.3" not in by)
check("build.yml 无 2.0.4 檔名", "桌面歌词-2.0.4" not in by)

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
check("主页面：无旧「悬浮窗歌词颜色」标签（2.0.2 真取色器叫「悬浮歌词颜色」，见 §15）",
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

print("\n== 10. diff 范围（相对 643037a） ==")
try:
    diff_names = git_out(["diff", "--name-only", BASE]).split()
    diff_names += git_out(["ls-files", "--others", "--exclude-standard"]).split()
    expected = {".github/workflows/build.yml",
        "App/PlaybackDashboardView.swift", "App/SettingsView.swift",
        "Diagnostics/DiagnosticsView.swift",
        "HUD/TLDHUDRootViewController.mm", "HUD/TLDHUDVersion.h",
        "EngineTests/main.swift",
        "Lyrics/LRCLibClient.swift", "Lyrics/LyricParser.swift",
        "Lyrics/LyricStore.swift",
        "PlaybackEngine/LyricMatcher.swift",
        "PlaybackEngine/PlaybackCoordinator.swift",
        "Renderer/PiPLyricsRenderer.swift",
        "TrollLyricsDesk.xcodeproj/project.pbxproj",
        "TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist",
        "check_2.0.6.py", "RUN_2.0.6.md"}
    check("diff 集合 == 预期（卡拉OK四项修复＋升版＋自检＋RUN 文档）",
          set(diff_names) == expected,
          "多：" + str(sorted(set(diff_names) - expected))
          + " 少：" + str(sorted(expected - set(diff_names))))
    print("changed files:", len(diff_names))
    for n in diff_names:
        print("  ", n)
except subprocess.CalledProcessError as e:
    open_item("git diff 读不到（未提交时正常）", str(e))


print("\n== 13. HUD Enable 在主页面（build 31，Lee 定放主页面；2.0.3 改单开关） ==")
pd = read("App/PlaybackDashboardView.swift")
cv = read("App/ContentView.swift")
sv = read("App/SettingsView.swift")
for needle in ["启用悬浮歌词",
               "查看守护进程日志", "固定位置", "悬浮歌词颜色",
               "当前环境未确认具备原生 HUD 权限；使用应用内歌词或独立 PiP 测试。"]:
    check(f"主页面：有 HUD 文案：{needle}", needle in pd)
check("主页面：HUD 区段说明文字已藏掉（2.0.3，见 §15j）",
      "锁屏解锁后仍在跟" not in pd
      and "重装后容器路径变了也不怕" not in pd)
check("主页面：HUD 区段标题已藏掉（2.0.3，见 §15h）",
      'Text("悬浮歌词（HUD 守护进程）")' not in pd)
for needle in ["TLDHUDSetEnabled(enabled)",
               "TLDHUDIsEnabled()", "TLDHUDLogMessage(",
               "HUDLogView()", "refreshHUDStatus()"]:
    check(f"主页面：有 HUD 调用：{needle}", needle in pd)
check("主页面：HUD 区段在非 LC 分支（else）内",
      "} else {" in pd and 'Toggle("启用悬浮歌词"' in pd)
check("主页面：LC 分支仍是应用内歌词（2.0.4 文案改兼容环境）",
      "兼容环境 · 应用内歌词模式" in pd
      and "RuntimeEnvironment.canUseNativeHUD" in pd)
check("主页面：HUD 状态 @State 两件在位（hudRunning＋hudBusy；"
      "2.0.3 藏掉状态行后 hudStatusText 已撤）",
      '@State private var hudRunning' in pd
      and '@State private var hudBusy' in pd
      and '@State private var hudStatusText' not in pd)
check("主页面：死开关三键 @AppStorage 声明仍在（只改 UI 呈现）",
      '@AppStorage("floatingLyric.enabled"' in pd
      and '@AppStorage("floatingLyric.positionLocked"' in pd
      and '@AppStorage("floatingLyric.textColorHex"' in pd)
check("ContentView 无 HUD 区段（HUD 在主页面；2.0.4 卡拉OK开关在设置页，见 §16）",
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

print("\n== 14. 兼容补丁标记（ChatGPT first compatibility patch） ==")
dm = read("HUD/TLDHUDDaemonMain.mm")
check("DaemonMain：OwnPID 校验在位", "TLDHUDOwnPID" in dm
      and "refusing stale or unverified PID" in dm)
hl = read("HUD/TLDHUDHelper.mm")
check("Helper：WIFEXITED 才读退出码", "WIFEXITED(status)" in hl)
check("Helper：IsEnabled 只认 status == 1", "return status == 1;" in hl)
re_ = read("Compatibility/RuntimeEnvironment.swift")
check("RuntimeEnvironment：canUseNativeHUD 定义在位",
      "static var canUseNativeHUD: Bool" in re_
      and 'LyricStore.installEnvironment == "trollstore"' in re_)
check("RuntimeEnvironment：native-candidate 不再走 nativeHUD",
      'case "native-candidate":' in re_ and "return .inApp" in re_)
ll = read("Lyrics/LyricLine.swift")
check("LyricLine：词级 LyricWord 模型在位",
      "struct LyricWord" in ll and "activeWord(at" in ll)
lp = read("Lyrics/LyricParser.swift")
check("LyricParser：词级时间戳正则在位", "wordPattern" in lp)
ak = read("App/ActivationKeychain.swift")
check("激活：类型 allowlist 只有 master／code",
      '["master", "code"].contains(type)' in ak)
check("CI：Engine regression tests 步骤在位",
      "Engine regression tests" in by)


print("\n== 15. 2.0.3 回归：药丸直接拖动（pan）／固定／颜色／透明度／字号／关于页／简繁／底子 ==")
rv = read("HUD/TLDHUDRootViewController.mm")
snap_h = read("HUD/TLDHUDLyricsSnapshot.h")
snap_m = read("HUD/TLDHUDLyricsSnapshot.mm")
pd = read("App/PlaybackDashboardView.swift")
about = read("App/AboutView.swift")
ls = read("Lyrics/LyricStore.swift")
cv = read("App/ContentView.swift")

print("-- 15a 直接拖动（pan，2.0.3 替代 2.0.2 长按） --")
check("拖动：UILongPressGestureRecognizer 已拆掉（源码无此类名）",
      "UILongPressGestureRecognizer" not in rv)
check("拖动：UIPanGestureRecognizer 在 pill 上（handlePillPan:）",
      "UIPanGestureRecognizer" in rv and "handlePillPan:" in rv)
check("拖动：pan 不设 minimumPressDuration（默认一碰就触发）",
      "minimumPressDuration" not in rv)
check("拖动：pan 不设 allowableMovement（长按才有的参数）",
      "allowableMovement" not in rv)
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
check("拖动：只加 pan，无点按／双击／长按手势",
      "UITapGestureRecognizer" not in rv
      and "UILongPressGestureRecognizer" not in rv)
check("拖动：Began 锁住记 blocked 行并 return（hud: pill drag blocked (locked)）",
      "hud: pill drag blocked (locked)" in rv
      and "if (_positionLocked) {" in rv)
check("拖动：Began 记 began 行（含 locked=NO）",
      "hud: pill drag began (locked=NO)" in rv)
check("拖动：Changed 只记首行（_dragLogged 标志，Began 时清零）",
      "_dragLogged = NO;" in rv and "hud: pill drag changed to" in rv
      and "if (!_dragLogged) {" in rv)
check("拖动：Ended/Cancelled 记行（含保存的中心点 saved centre）",
      "hud: pill drag" in rv and "saved centre" in rv)
check("拖动：pillFrameInWindow 供窗口 hitTest 用",
      "pillFrameInWindow" in rv and "pillFrameInWindow" in read("HUD/TLDHUDRootViewController.h"))

print("-- 15b 固定位置开关 --")
check("固定：主页面有新键 hudPill.positionLocked 的 @AppStorage（默认关）",
      '@AppStorage("hudPill.positionLocked", store: LyricStore.defaults)' in pd
      and "private var hudPillPositionLocked = false" in pd)
check("固定：主页面有「固定位置」Toggle",
      'Toggle("固定位置", isOn: $hudPillPositionLocked)' in pd)
check("固定：Toggle 在 HUD 区段内（兼容门控说明之后、日志入口之前）",
      pd.index("当前环境未确认具备原生 HUD 权限；使用应用内歌词或独立 PiP 测试。")
      < pd.index('Toggle("固定位置"')
      < pd.index("查看守护进程日志"))
check("固定：旧死键 floatingLyric.positionLocked 声明一字未动",
      '@AppStorage("floatingLyric.positionLocked", store: LyricStore.defaults)' in pd
      and "private var positionLocked = false" in pd)
check("固定：每秒 tick 重读标志（onTimerTick）",
      "_positionLocked = [self readPositionLocked];" in rv)
check("固定：解锁时也重读标志（hudDidUnlock；三处重读：viewDidLoad＋tick＋unlock）",
      rv.count("_positionLocked = [self readPositionLocked];") == 3,
      str(rv.count("_positionLocked = [self readPositionLocked];")))

print("-- 15c 歌词颜色取色器 --")
check("颜色：主页面有「悬浮歌词颜色」ColorPicker（复用 lyricTextColor）",
      'ColorPicker("悬浮歌词颜色", selection: lyricTextColor)' in pd)
check("颜色：复用旧键 floatingLyric.textColorHex，未另起新键",
      '"floatingLyric.textColorHex"' in pd
      and "hudPill.textColor" not in pd)
check("颜色：取色器在 HUD 区段内（兼容门控说明之后、日志入口之前）",
      pd.index("当前环境未确认具备原生 HUD 权限；使用应用内歌词或独立 PiP 测试。")
      < pd.index('ColorPicker("悬浮歌词颜色"')
      < pd.index("查看守护进程日志"))
check("颜色：daemon 每 tick 读色（pillLyricColor 读 floatingLyric.textColorHex）",
      "pillLyricColor" in rv and '"floatingLyric.textColorHex"' in rv)
check("颜色：缺省（键不存在）保持白色",
      "objectForKey:TLDHUD_PILL_TEXT_COLOR_KEY" in rv
      and "return [UIColor whiteColor];" in rv)
check("颜色：两档 alpha 照旧（0.45／1.0），只换白底为读到的颜色"
      "（2.0.3 藏掉 songLine 后 0.65 那档随 songAttrs 一起撤掉）",
      "[baseColor colorWithAlphaComponent:0.45]" in rv
      and "NSForegroundColorAttributeName : baseColor," in rv
      and "[baseColor colorWithAlphaComponent:0.65]" not in rv)
check("颜色：fallback 测试字也跟色（仍 15pt 不动）",
      "[self pillLyricColor]" in rv
      and "monospacedDigitSystemFontOfSize:15" in rv)

print("-- 15d 透明度（药丸背景＋歌词字） --")
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

print("-- 15e 歌词字体大小 --")
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

print("-- 15f 关于页删日志行 --")
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

print("-- 15g 藏掉歌名 · 歌手，只留歌词（2.0.3，Lee 定） --")
check("藏身份行：歌卡无 bottomText 渲染（Text(bottomText) 已删）",
      "convertForDisplay(bottomText)" not in pd
      and "Text(LyricStore.convertForDisplay(bottomText))" not in pd)
check("藏身份行：歌卡上行歌词行还在（topText 大字）",
      "Text(LyricStore.convertForDisplay(topText))" in pd
      and ".font(.title2.bold())" in pd)
check("藏身份行：歌卡 PLAYING 还在（进度行 2.0.3 另藏，见 §15i）",
      "state.status.rawValue.uppercased()" in pd)
check("藏身份行：药丸 updateDisplay 里无 songLine 追加",
      "lyrics.songLine" not in rv and "songAttrs" not in rv)
check("藏身份行：药丸只留 previous／current／next 三行",
      "lyrics.previousLine" in rv and "lyrics.currentLine" in rv
      and "lyrics.nextLine" in rv)
check("藏身份行：药丸无歌 fallback 测试字保留（showFallbackText）",
      "showFallbackText" in rv and "桌面歌詞 2.0.6" in rv)
check("藏身份行：快照 songLine 构造仍在（识别／逐歌偏移继续用原文）",
      'display.songLine = [NSString stringWithFormat:@"%@ · %@",' in snap_m
      and "display.songLine = display.track;" in snap_m)
check("藏身份行：快照仍对 songLine 做简繁显示转换（接线不动）",
      "display.songLine = TLDHUDConvertForDisplay(display.songLine);" in snap_m)

print("-- 15h HUD 一个开关＋藏状态行＋藏区段标题（2.0.3，Lee 定） --")
check("开关：两个大按键文案已撤（主页面源码级；SettingsView 死页面"
      "里还有，二进制不断言——它照常编进包）",
      '"启用 HUD 守护进程"' not in pd and '"停用 HUD 守护进程"' not in pd)
check("开关：一个 Toggle「启用悬浮歌词」，绑定 hudEnabledToggle",
      'Toggle("启用悬浮歌词", isOn: hudEnabledToggle)' in pd)
check("开关：绑定 get 读 hudRunning（-check 实时结果，不是偏好值）",
      "get: { hudRunning }" in pd)
check("开关：绑定 set 调 setHUDEnabled（走后台队列＋hudBusy 防连点）",
      "set: { newValue in setHUDEnabled(newValue) }" in pd
      and "guard !hudBusy else { return }" in pd
      and "TLDHUDSetEnabled(enabled)" in pd)
check("开关：set 后 refreshHUDStatus() 回写真实状态",
      "refreshHUDStatus()" in pd
      and pd.index("TLDHUDSetEnabled(enabled)")
      < pd.index("refreshHUDStatus()", pd.index("TLDHUDSetEnabled(enabled)")))
check("开关：Toggle 出现时 onAppear 刷新一次真实状态",
      ".onAppear" in pd[pd.index('Toggle("启用悬浮歌词"'):
                        pd.index('Toggle("启用悬浮歌词"') + 500]
      and "refreshHUDStatus()" in pd[pd.index('Toggle("启用悬浮歌词"'):
                                     pd.index('Toggle("启用悬浮歌词"') + 500])
check("开关：状态不用 @AppStorage 存（只有原来四把键，无新增 HUD 开关键）",
      set(re.findall(r'@AppStorage\("([^"]+)"', pd))
      == {"floatingLyric.enabled", "floatingLyric.positionLocked",
          "hudPill.positionLocked", "floatingLyric.textColorHex"},
      str(set(re.findall(r'@AppStorage\("([^"]+)"', pd))))
check("开关：没复用 floatingLyric.enabled 死键当绑定",
      'isOn: $floatingEnabled' not in pd)
check("开关：兼容门控分支仍只显示禁用说明，绝不调 SetHUDEnabled",
      "当前环境未确认具备原生 HUD 权限；使用应用内歌词或独立 PiP 测试。" in pd
      and "TLDHUDSetEnabled" not in pd.split(
          "当前环境未确认具备原生 HUD 权限；使用应用内歌词或独立 PiP 测试。")[1].split(
          "} else {")[0])
check("状态行：可见行已藏掉（Text(\"守护进程状态\") 不在主页面）",
      'Text("守护进程状态")' not in pd)
check("状态行：refreshHUDStatus 仍更新 hudRunning",
      "hudRunning = TLDHUDIsEnabled()" in pd)
check("状态行：不再读 PID 文件（显示没了，pid 只在日志里）",
      "TLDHUDPIDPath()" not in pd)
check("状态行：hudStatusText @State 已清理",
      "@State private var hudStatusText" not in pd
      and "Text(hudStatusText)" not in pd)
check("标题：区段标题可见行已藏掉（Text(\"悬浮歌词（HUD 守护进程）\") 不在主页面）",
      'Text("悬浮歌词（HUD 守护进程）")' not in pd)
check("标题：其余控件都在（开关＋固定位置＋颜色＋日志入口；说明文字"
      " 2.0.3 另藏，见 §15j）",
      'Toggle("启用悬浮歌词"' in pd
      and 'Toggle("固定位置"' in pd
      and 'ColorPicker("悬浮歌词颜色"' in pd
      and "查看守护进程日志" in pd)

print("-- 15j HUD 区段说明文字藏掉（2.0.3，Lee 定） --")
check("说明文字：HUD 区段里无那段说明文字（源码级；二进制不断言）",
      "锁屏解锁后仍在跟" not in pd
      and "重装后容器路径变了也不怕" not in pd
      and "每次启用都会重写 daemon 配置" not in pd)
check("说明文字：区段只剩开关／固定位置／颜色／滑块／查看守护进程日志",
      'Toggle("启用悬浮歌词"' in pd
      and 'Toggle("固定位置"' in pd
      and 'ColorPicker("悬浮歌词颜色"' in pd
      and "查看守护进程日志" in pd)
check("说明文字：「查看守护进程日志」链接保留不动（Lee 定过要留着）",
      "查看守护进程日志" in pd and "HUDLogView()" in pd)

print("-- 15i 歌卡进度行藏掉（2.0.3，Lee 定） --")
check("进度行：歌卡内无进度显示行（源码级；二进制不断言——别处"
      "可能还有「进度」字串）",
      '"进度：\\(Int(state.position)) 秒"' not in pd)
check("进度行：歌词行与 PLAYING 不动",
      "Text(LyricStore.convertForDisplay(topText))" in pd
      and "state.status.rawValue.uppercased()" in pd)
check("进度行：只藏显示，状态来源不动（歌卡仍 key 在 coordinator.state 上）",
      "if let state = coordinator.state" in pd)

print("-- 15k 歌词简繁切换（2.0.2） --")
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
check("简繁：主页面歌名／歌手显示时转换（原文不动；2.0.3 藏掉身份行后"
      "只剩上行歌词行转 bottomText 不再渲染）",
      "Text(LyricStore.convertForDisplay(topText))" in pd
      and "convertForDisplay(bottomText)" not in pd)
check("简繁：应用内歌词行显示时转换",
      "LyricStore.convertForDisplay(" in read("Renderer/InAppLyricsRenderer.swift"))
check("简繁：daemon 读同一把键并用 CFStringTransform 转显示字串",
      '"lyric.displayScript"' in snap_m
      and 'CFSTR("Hans-Hant")' in snap_m and 'CFSTR("Hant-Hans")' in snap_m)
check("简繁：daemon 转显示字串（四行＋逐字；ApplyScript 两处 display＋一处 test）",
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

print("-- 15m 2.0.2 底子：ChatGPT 建议（PID 校验＋Enable 健壮性） --")
dm = read("HUD/TLDHUDDaemonMain.mm")
hh = read("HUD/TLDHUDHelper.mm")
vh = read("HUD/TLDHUDVersion.h")
check("底子：TLDHUDOwnPID 用 proc_pidpath＋realpath 核对可执行路径",
      "TLDHUDOwnPID" in dm and "proc_pidpath" in dm and "realpath" in dm
      and "strcmp(expected, resolved) == 0" in dm)
check("底子：libproc.h 不在 iOS SDK 里，改前置声明（run 46109489987 教训）",
      "#import <libproc.h>" not in dm
      and 'extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);' in dm
      and "#define PROC_PIDPATHINFO_MAXSIZE 1024" in dm
      and "#import <limits.h>" in dm and "#import <stdlib.h>" in dm)
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
check("底子：TLDHUDVersion.h 注释指向 check_2.0.6.py",
      "check_2.0.6.py" in vh)
try:
    msgs = git_out(["log", "--format=%s", BASE + "..HEAD"]).splitlines()
    if not msgs:
        open_item("未提交：提交顺序断言等提交后再跑", "HEAD == BASE，尚无新提交")
    else:
        check("提交顺序：v2.0.6 五笔（2.0.6 产品＋引擎测试修＋Widget 编译修＋RUN 文档＋补自检数）",
              len(msgs) == 5 and msgs[4].startswith("2.0.6/build 36：卡拉OK修复")
              and msgs[3].startswith("2.0.6/build 36：修 run 46134758976")
              and msgs[2].startswith("2.0.6/build 36：修 run 46135798827")
              and msgs[1].startswith("RUN_2.0.6：run 46136838949")
              and msgs[0].startswith("RUN_2.0.6：补提交后自检数"), str(msgs))
except subprocess.CalledProcessError as e:
    open_item("git log 读不到，分支顺序断言跳过", str(e))

print("\n== 16. 2.0.4 新功能：横竖滑块定位＋卡拉OK模式＋药丸版本号 ==")
rv = read("HUD/TLDHUDRootViewController.mm")
snap_h = read("HUD/TLDHUDLyricsSnapshot.h")
snap_m = read("HUD/TLDHUDLyricsSnapshot.mm")
pd = read("App/PlaybackDashboardView.swift")
ls = read("Lyrics/LyricStore.swift")
cv = read("App/ContentView.swift")

print("-- 16a 横竖滑块定位 --")
check("滑块：主页面有「横向」「纵向」两条滑块（药丸位置）",
      'Text("横向")' in pd and 'Slider(value: $pillSliderX' in pd
      and 'Text("纵向")' in pd and 'Slider(value: $pillSliderY' in pd)
check("滑块：写同一对 hudPill 位置键，不另发明键",
      '"hudPill.positionX"' in pd and '"hudPill.positionY"' in pd
      and "hudPill.position" in pd
      and pd.count("hudPill.position") == pd.count("hudPill.positionX") + pd.count("hudPill.positionY") + pd.count("hudPill.positionLocked"))
check("滑块：固定位置开时置灰（.disabled 绑 hudPillPositionLocked）",
      ".disabled(hudPillPositionLocked)" in pd)
check("滑块：进页面时 onAppear 读回当前药丸位置（syncPillSliders）",
      "syncPillSliders()" in pd
      and 'store?.object(forKey: "hudPill.positionX")' in pd
      and 'store?.object(forKey: "hudPill.positionY")' in pd)
check("滑块：拖滑块写键（onChange → writePillSliderPosition）",
      "writePillSliderPosition()" in pd
      and "onChange(of: pillSliderX)" in pd
      and "onChange(of: pillSliderY)" in pd)
check("滑块：滑块在 HUD 区段内（固定位置之后、颜色之前）",
      pd.index('Toggle("固定位置"') < pd.index('Text("横向")')
      < pd.index('ColorPicker("悬浮歌词颜色"'))
check("滑块：daemon 每秒 tick 重读位置键（applySavedPillPositionIfChanged）",
      "applySavedPillPositionIfChanged" in rv
      and "applySavedPillPositionIfChanged];" in rv)
check("滑块：tick 与解锁时都重读位置（onTimerTick＋hudDidUnlock）",
      rv.count("applySavedPillPositionIfChanged];") >= 2,
      str(rv.count("applySavedPillPositionIfChanged];")))
check("滑块：拖动中不抢（_dragging 时直接 return）",
      "if (_dragging || !_pill) return;" in rv)
check("滑块：变化小于 0.5pt 不动（死区，不刷屏）",
      "saved.x - current.x > 0.5" in rv and "saved.y - current.y > 0.5" in rv)
check("滑块：移药丸走 movePillToCenter（复用夹取，不出屏）",
      "movePillToCenter:saved" in rv
      and "hud: pill position applied from slider" in rv)
check("滑块：无键时不动（没拖过保持默认居中偏上）",
      "never positioned: keep the default top-centre spot" in rv)

print("-- 16b 卡拉OK模式 --")
check("卡拉OK：新键 lyric.karaokeEnabled，默认开（键不存在 = 开）",
      'static let karaokeEnabledKey = "lyric.karaokeEnabled"' in ls
      and "static var isKaraokeEnabled: Bool" in ls
      and "guard defaults.object(forKey: karaokeEnabledKey) != nil else { return true }" in ls)
check("卡拉OK：设置页（ContentView）歌词区段有「卡拉OK模式」开关，默认开",
      'Toggle("卡拉OK模式", isOn: $karaokeEnabled)' in cv
      and '@AppStorage("lyric.karaokeEnabled", store: LyricStore.defaults)' in cv
      and "private var karaokeEnabled = true" in cv)
check("卡拉OK：LyricStore 有当前行＋已播位置 helper（currentLyricAndElapsed）",
      "static func currentLyricAndElapsed(" in ls
      and "snapshot.lyrics.last(where: { $0.time <= elapsed })" in ls)
check("卡拉OK：主页面有 KaraokeLyricText（已唱金色、未唱灰色）",
      "struct KaraokeLyricText: View" in pd
      and "Color(red: 1.0, green: 0.8, blue: 0.1)" in pd
      and "baseColor.opacity(0.45)" in pd)
check("卡拉OK：歌卡大字是当前歌词行时逐字亮（TimelineView 0.25s＋原文比对）",
      "KaraokeLyricText(line: pair.line, elapsed: pair.elapsed" in pd
      and "normalize(pair.line.text) == normalize(topText)" in pd)
check("卡拉OK：应用内歌词区逐字亮（测试文字开时不逐字）",
      "!LyricStore.isTestTextEnabled" in pd
      and "KaraokeLyricText(line: pair.line, elapsed: pair.elapsed, font: .title2" in pd)
check("卡拉OK：无逐字时间戳退回整行（words 为空走 else 分支）",
      "let words = pair.line.words, !words.isEmpty" in pd
      and "words.reduce(Text(\"\"))" in pd)
check("卡拉OK：逐词按简繁开关转换（convertForDisplay 逐词）",
      "LyricStore.convertForDisplay(word.text)" in pd)
check("卡拉OK：快照只存原文（title／artist／lyrics[] 无转换调用）",
      "convertForDisplay" not in ls.split("static func save(")[1].split("static func load()")[0]
      if "static func save(" in ls else False)
check("卡拉OK：daemon 快照带当前行逐字＋已播位置（currentWords／elapsed）",
      "NSArray<NSDictionary *> *currentWords;" in snap_h
      and "NSTimeInterval elapsed;" in snap_h
      and 'display.currentWords = lines[currentIndex][@"words"];' in snap_m
      and "display.elapsed = elapsed;" in snap_m)
check("卡拉OK：daemon 解析快照时保留每行 words（只留 time／text 合法项）",
      'id wordsRaw = entry[@"words"];' in snap_m
      and 'lineDict[@"words"] = [words copy];' in snap_m)
check("卡拉OK：daemon 逐词按简繁开关转换（ApplyScript 里转 words）",
      "display.currentWords = [convertedWords copy];" in snap_m
      and "TLDHUDConvertForDisplay(wordText)" in snap_m)
check("卡拉OK：daemon 读同一把开关，键不存在 = 开（readKaraokeEnabled）",
      "readKaraokeEnabled" in rv
      and '#define TLDHUD_PILL_KARAOKE_KEY @"lyric.karaokeEnabled"' in rv
      and "objectForKey:TLDHUD_PILL_KARAOKE_KEY" in rv)
check("卡拉OK：药丸当前行逐字上色（已唱金色、未唱灰色；无逐字退回整行）",
      "lyrics.currentWords.count > 0" in rv
      and "[UIColor colorWithRed:1.0 green:0.8 blue:0.1 alpha:1.0]" in rv
      and "[baseColor colorWithAlphaComponent:0.45]" in rv
      and "[wordTime doubleValue] <= lyrics.elapsed" in rv)
check("卡拉OK：药丸上一句／下一句照常（暗行，不受逐字影响）",
      "lyrics.previousLine" in rv and "lyrics.nextLine" in rv
      and "dimAttrs" in rv)

print("-- 16c 药丸版本号修掉写死的 2.0.1 --")
check("药丸版本：fallback 文字是桌面歌詞 2.0.6（与 versionTag 一致）",
      "桌面歌詞 2.0.6" in rv)
check("药丸版本：无旧版 2.0.3 fallback 文字",
      "桌面歌詞 2.0.3" not in rv)

print("-- 16d 兼容补丁其余项（§14 之外） --")
dv = read("Diagnostics/DiagnosticsView.swift")
check("兼容：诊断页有 Apple Music 备选授权按钮（requestMusicPermission）",
      "musicPermission" in dv and "requestMusicPermission" in dv
      and "MPMediaLibrary.authorizationStatus()" in dv)
ma = read("MusicProviders/MediaRemoteAdapter.swift")
check("兼容：MediaRemote 仅在非原生 HUD 环境＋已授权时走 Apple Music 兜底",
      "authorizedFallback()" in ma
      and "!RuntimeEnvironment.canUseNativeHUD" in ma
      and "state.status == .playing" in ma)
check("兼容：MediaRemote 按 bundle-ID 分类平台（fromBundleIdentifier）",
      "MusicPlatform.fromBundleIdentifier" in ma
      and "kMRMediaRemoteNowPlayingInfoApplicationBundleIdentifier" in ma)
pc = read("PlaybackEngine/PlaybackCoordinator.swift")
check("兼容：轮询代次守卫（pollingGeneration）＋空闲降频（nextPollUptime）",
      "pollingGeneration" in pc and "nextPollUptime" in pc
      and "estimatedPosition()" in pc)
check("兼容：单调播放外推在 PlaybackState（estimatedPosition，暂停冻结／截断到 duration）",
      "func estimatedPosition(" in read("PlaybackEngine/PlaybackState.swift")
      and "observedUptime" in read("PlaybackEngine/PlaybackState.swift"))
td = read("Overlay/TLDSAppDelegate.m")
check("兼容：AppDelegate 未知环境记 compat（不再 native-candidate）",
      'setRunMode:@"compat" reason:@"安装来源未知，禁止原生 HUD"' in td)
rt = read("App/TrollLyricsDeskApp.swift")
check("兼容：保活只在 canUseNativeHUD 时启动",
      "if RuntimeEnvironment.canUseNativeHUD { BackgroundKeepAlive.shared.start() }" in rt)
sv = read("App/SettingsView.swift")
check("兼容：SettingsView 读状态先过 canUseNativeHUD 门控",
      "guard RuntimeEnvironment.canUseNativeHUD else" in sv
      and 'hudStatusText = "当前环境不支持原生 HUD"' in sv)
check("兼容：导航标题诊断（2.0.6）",
      'navigationTitle("诊断（2.0.6）")' in dv)


print("\n== 17. hid-probe 底子保留（日志＋hitTest 节流） ==")
import plistlib as _pl
ent = _pl.loads(open(os.path.join(ROOT, "HUD/TLDHUDDaemon.entitlements"), "rb").read())
for k in ["com.apple.private.hid.client.event-dispatch",
          "com.apple.private.hid.client.event-filter",
          "com.apple.private.hid.client.event-monitor",
          "com.apple.private.hid.client.service-protected",
          "com.apple.private.hid.manager.client"]:
    check(f"entitlements: 有 {k}", ent.get(k) is True)
check("entitlements: 注释说明 2.0.5 全量触摸（Lee 2026-11-28 已批准）",
      "2.0.5" in read("HUD/TLDHUDDaemon.entitlements")
      and "full HID touch port" in read("HUD/TLDHUDDaemon.entitlements")
      and "Do NOT carry" not in read("HUD/TLDHUDDaemon.entitlements"))
dm = read("HUD/TLDHUDDaemonMain.mm")
tbd = read("HUD/Private/BackBoardServices.tbd")
check("链接：BackBoardServices.tbd 导出 _BKSHIDEventRegisterEventCallback（run 46127968236 教训：stub 只导了 _BKSDisplayServicesStart）",
      "_BKSHIDEventRegisterEventCallback" in tbd
      and "_BKSDisplayServicesStart" in tbd)
check("daemon: 注册 BKSHIDEventRegisterEventCallback(TLDHIDEventCallback)",
      "BKSHIDEventRegisterEventCallback(TLDHIDEventCallback);" in dm)
check("daemon: 探针回调已撤（TLDHIDProbeCallback 不再存在）",
      "TLDHIDProbeCallback" not in dm)
# 注册点在 -hud 分支 [NSRunLoop currentRunLoop]; 之后（TrollSpeed HUDApp.mm 同款位置）
check("daemon: 注册点在 [NSRunLoop currentRunLoop]; 之后",
      dm.index("BKSHIDEventRegisterEventCallback(TLDHIDEventCallback);")
      > dm.index("[NSRunLoop currentRunLoop];"))
check("daemon: 回调 TLDHIDEventCallback 存在",
      "static void TLDHIDEventCallback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event)" in dm)
check("daemon: 回调前 10 个事件全记（CFCopyDescription＋CFRelease，探针日志保留）",
      "CFCopyDescription((CFTypeRef)event)" in dm and "CFRelease(desc)" in dm
      and "probeCount <= 10" in dm)
check("daemon: 10 个之后每秒最多一个计数行",
      '"hid: probe count %lu"' in dm and "now - lastCountLog >= 1.0" in dm)
check("daemon: 日志前缀统一 hid: probe",
      dm.count('"hid: probe') >= 3)
check("daemon: 回调有自己的锁（可能不在主线程）",
      "probeLock" in dm and "@synchronized (probeLock)" in dm)
check("daemon: 无新增 CoreGraphics 调用（注释里提名字不算，只禁调用点）",
      "CGRectContainsPoint(" not in dm and "CGRectIsEmpty(" not in dm
      and "CGRectZero" not in dm)
mw = read("HUD/TLDHUDMainWindow.mm")
check("hitTest: import TLDHUDLog.h",
      '#import "TLDHUDLog.h"' in mw)
check("hitTest: 只记第一次调用（static BOOL 跳过）",
      "static BOOL hitTestLogged = NO;" in mw and "if (!hitTestLogged)" in mw)
check("hitTest: 日志行 hid: probe hitTest first call point (%d,%d)",
      '"hid: probe hitTest first call point (%d,%d)"' in mw)
_ht = mw.split("- (UIView *)hitTest")[1].split("UIView *hit = [super hitTest")[0]
check("hitTest: 无新增 CoreGraphics 调用（只记两个 int）",
      "CGRect" not in _ht and "CGPointMake" not in _ht)
check("hitTest: 仍走原有手算几何（pillFrame 手算未动）",
      "pillFrame.size.width > 0" in mw)

print("\n== 18. HID 全量移植（TrollSpeed 触摸管线，药丸内才注入） ==")
check("daemon: 回调署名 TrollSpeed（MIT © 2023 Lessica）",
      "TrollSpeed" in dm and "MIT" in dm and "Lessica" in dm)
check("daemon: AX 解码（representationWithHIDEvent + hidStreamIdentifier）",
      'representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"' in dm)
check("daemon: 加载 AccessibilityUtilities（AX 类来源）",
      'bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"' in dm)
check("daemon: 相位映射（TouchDown/Move/Cancel/Lift/InRange）",
      "[rep isTouchDown]" in dm and "[rep isMove]" in dm
      and "[rep isCancel]" in dm and "[rep isLift]" in dm)
check("daemon: pointerId 取 pathIdentity 并夹到 1..98",
      "pathIdentity" in dm and "MIN(MAX(pointerId, 1), 98)" in dm)
check("daemon: 注入经 TSEventFetcher.receiveAXEventID（不在回调里直接 sendEvent）",
      "[TSEventFetcher receiveAXEventID:" in dm
      and "sendEvent:" not in dm)
_cb = dm.split("static void TLDHIDEventCallback")[1].split("int main")[0]
check("安全门 1：hitTest 验窗（keyView 为空直接 return）",
      "[keyWindow hitTest:location withEvent:nil]" in _cb
      and "if (!keyView) return;" in _cb)
check("安全门 2：pillFrameInWindow 手算比对（药丸外直接 return）",
      "pillFrameInWindow" in _cb and "insidePill" in _cb
      and "if (!pillNotEmpty || !insidePill) return;" in _cb)
check("安全门 3：注入只发给药丸窗口自己的 view（inWindow:keyWindow onView:keyView）",
      "inWindow:keyWindow onView:keyView" in _cb)
check("安全门 4：药丸外不记注入日志（只记第一次药丸内注入）",
      '"hid: touch in pill, injecting (phase %ld)"' in _cb)
check("安全门 5：iOS 15.1 以下才 _enqueueHIDEvent（TrollSpeed 原样，不双发）",
      "[app _enqueueHIDEvent:event]" in _cb)
check("daemon: 导入 TSEventFetcher.h＋AXEventRepresentation.h",
      '#import "TSEventFetcher.h"' in dm
      and '#import "AXEventRepresentation.h"' in dm)
for h in ["AXEventRepresentation.h", "AXEventHandInfoRepresentation.h",
          "AXEventPathInfoRepresentation.h", "UIEvent+Private.h",
          "UITouch+Private.h", "UITouch-KIFAdditions.h", "IOHIDEvent+KIF.h",
          "UIEventFetcher.h", "UIEventDispatcher.h", "pac_helper.h"]:
    hp = os.path.join(ROOT, "HUD/headers", h)
    check(f"头文件在位：HUD/headers/{h}", os.path.exists(hp))
    check(f"头文件有 Lessica 署名：{h}",
          "Lessica" in open(hp).read())
check("头文件：AXEventRepresentation.h 仍声明 representationWithHIDEvent",
      "representationWithHIDEvent" in read("HUD/headers/AXEventRepresentation.h"))
check("头文件：pac_helper.h 仍有 make_sym_callable／make_sym_readable",
      "make_sym_callable" in read("HUD/headers/pac_helper.h")
      and "make_sym_readable" in read("HUD/headers/pac_helper.h"))
for f in ["HUD/TSEventFetcher.h", "HUD/TSEventFetcher.mm",
          "HUD/UITouch-KIFAdditions.m", "HUD/IOHIDEvent+KIF.m"]:
    check(f"源文件在位：{f}", os.path.exists(os.path.join(ROOT, f)))
    check(f"源文件有 Lessica 署名：{f}", "Lessica" in read(f))
te = read("HUD/TSEventFetcher.mm")
check("TSEventFetcher: +load 池子 100 个触摸（TrollSpeed 原样）",
      "for (NSInteger i = 0; i < 100; i++)" in te)
check("TSEventFetcher: +load initTouch 包 @try/@catch（daemon 无 scenes，TLD 唯一改动）",
      "@try" in te and "initTouch" in te and "@catch" in te)
check("TSEventFetcher: receiveAXEventID 存在（KIF 合成 UITouch）",
      "+ (NSInteger)receiveAXEventID:" in te)
check("TSEventFetcher: 新触摸用 initAtPoint 造，旧触摸 setLocationInWindow 跟",
      "initAtPoint:coordinate inWindow:window onView:view" in te
      and "[touch setLocationInWindow:coordinate]" in te)
check("TSEventFetcher: 经 [app _touchesEvent]＋sendEvent 发出",
      "[app _touchesEvent]" in te and "[app sendEvent:event]" in te)
check("TSEventFetcher: setPhaseAndUpdateTimestamp 更新相位",
      "[touch setPhaseAndUpdateTimestamp:phase]" in te)
ma = read("HUD/TLDHUDMainApplication.mm")
check("MainApplication: 装 UIEventDispatcher run loop sources",
      "_installEventRunLoopSources:" in ma)
check("MainApplication: 建 UIEventFetcher 并接成 sink",
      '[[objc_getClass("UIEventFetcher") alloc] init]' in ma
      and "setEventFetcherSink:" in ma)
check("MainApplication: pac_helper 兜底扫描 _run（BL＋CBZ）",
      "make_sym_readable" in ma and "make_sym_callable" in ma
      and "0xaa0003e2" in ma and "0xb4000000" in ma)
check("MainApplication: fail-closed @try/@catch（装不上 daemon 照活，只无触摸）",
      "@try" in ma and "@catch" in ma
      and '"hud: touch pipeline install failed' in ma)
check("MainApplication: 撤场 handler 还在（fade out＋terminateWithSuccess）",
      "NOTIFY_DISMISSAL_HUD" in ma and "terminateWithSuccess" in ma)
check("pbxproj: daemon Sources 含 TSEventFetcher.mm＋两个 KIF .m（每件 2 处：BuildFile 定义＋Sources 列表）",
      pbx.count("TSEventFetcher.mm in Sources") == 2
      and pbx.count("UITouch-KIFAdditions.m in Sources") == 2
      and pbx.count("IOHIDEvent+KIF.m in Sources") == 2)
check("pbxproj: daemon 链 IOKit（KIF 造 digitizer 事件用）",
      pbx.count("IOKit,") == 2)
rv = read("HUD/TLDHUDRootViewController.mm")
check("拖动保护：tick／解锁重算位置时 _dragging 直接 return（不抢手指）",
      "if (_dragging || !_pill) return;" in rv)
check("拖动逻辑未动：handlePillPan 仍在（Began/Changed/Ended）",
      "handlePillPan" in rv and "UIGestureRecognizerStateBegan" in rv
      and "UIGestureRecognizerStateEnded" in rv)

print("\n== 19. 2.0.6 卡拉OK修复：lyricsfile 逐字＋缓存 v2＋诊断日志＋歌卡归一化 ==")
lc = read("Lyrics/LRCLibClient.swift")
lp = read("Lyrics/LyricParser.swift")
lm = read("PlaybackEngine/LyricMatcher.swift")
pc = read("PlaybackEngine/PlaybackCoordinator.swift")
pd = read("App/PlaybackDashboardView.swift")
check("P0：LRCLyricsRecord 有 lyricsfile 字段（optional，旧记录缺失不崩）",
      "let lyricsfile: String?" in lc)
check("P0：LRCLyricsRecord 有 hasWordSync 字段（optional，仅打分参考）",
      "let hasWordSync: Bool?" in lc)
check("P0：LyricsFileParser 在位（parse／mergingWordSync／linesFromLyricsFile）",
      "enum LyricsFileParser" in lp
      and "static func parse(_ yaml: String)" in lp
      and "static func mergingWordSync" in lp
      and "static func linesFromLyricsFile" in lp)
check("P0：YAML 解析只取 text／start_ms／words（end_ms／metadata 忽略）",
      '"text"' in lp and '"start_ms"' in lp and '"words"' in lp)
check("P0：plain: | 字面块有防护（块内行不被当成行／词项）",
      "inPlainBlock" in lp and "plainIndent" in lp)
check("P0：无新依赖（不引 YAML 库）",
      "Yams" not in lp and "import Yams" not in lp)
check("P0：lyricsfile 不喂 LyricParser.parse（YAML 不是 LRC 文本）",
      "LyricParser.parse(lyricsFile" not in pc
      and "LyricParser.parse(result.lyricsfile" not in pc
      and "LyricParser.parse(lrc)" in pc)
check("P0：词时间 = start_ms / 1000（行时间仍用 syncedLyrics 行级戳）",
      "Double($0.startMs) / 1000.0" in lp)
check("P0：loadLyrics 用 lyricsfile 补逐字（行数一致下标映射，不一致文本对齐）",
      "LyricsFileParser.mergingWordSync" in pc
      and "LyricsFileParser.linesFromLyricsFile" in pc)
check("P0：只有 lyricsfile、没有 syncedLyrics 也能建行",
      "if lines.isEmpty {" in pc
      and "lines = LyricsFileParser.linesFromLyricsFile(lyricsFile)" in pc)
check("P0：Matcher 候选放宽——有 lyricsfile 即候选（以前只认 syncedLyrics）",
      "let hasFile = !($0.lyricsfile?.isEmpty ?? true)" in lm
      and "(hasSynced || hasFile)" in lm)
check("P0：Matcher 打分优先选有 lyricsfile 的候选（+50，防无逐字版本赢）",
      'if !(record.lyricsfile?.isEmpty ?? true) {' in lm
      and "value += 50" in lm)
check("P1：loadLyrics 解析后记诊断行（行数／逐字行数／总词数）",
      '"歌词匹配成功：\\(searchTrack.title)"' in pc
      and "逐字 \\(wordLineCount) 行" in pc
      and "共 \\(wordTotal) 词" in pc)
check("P1：本地缓存命中也记逐字计数（重播走缓存不联网，这是唯一自证）",
      '"本地歌词命中：\\(title)"' in pc
      and "逐字 \\(cachedWordLines) 行" in pc)
check("P1：守护进程换歌行追加当前行词数（karaoke N words）",
      'hud: lyrics now %@ — %@ (%lu lines, karaoke %lu words)' in rv
      and "lyrics.currentWords.count" in rv)
check("P1：缓存键版本化 v2（旧缓存一次性失效重取）",
      '"lyric.cache|v2|\\(title.lowercased())|\\(artist.lowercased())"' in ls)
check("P1：旧缓存键不在位（无 v2 的键已撤）",
      '"lyric.cache|\\(title.lowercased())|\\(artist.lowercased())"' not in ls)
check("P2：歌卡逐字门复用 LyricMatcher.normalize（字母数字归一化）",
      "let normalize: (String) -> String = LyricMatcher.normalize" in pd)
check("P2：歌卡旧窄 normalize 闭包已撤（只去空格）",
      '.replacingOccurrences(of: " ", with: "")' not in pd)
check("P2：LyricMatcher.normalize 已去 private（供歌卡复用）",
      "static func normalize(" in lm
      and "private static func normalize(" not in lm)
check("P0 回归门：LyricParser.swift 不引 LyricMatcher（Widget target 只编前者，run 46135798827 教训）",
      re.search(r"LyricMatcher\.(?!swift\b)", lp) is None)
check("P0 回归门：LyricsFileParser 自带同规则归一化（小写＋只留字母数字）",
      "private static func normalize(_ value: String) -> String" in lp
      and "$0.isLetter || $0.isNumber" in lp)
check("P2：药丸与 LC 应用内区没有逐字门——不动（RootVC／应用内渲染无 normalize 门）",
      "LyricMatcher.normalize" not in rv)
by = read(".github/workflows/build.yml")
check("P0 回归门：CI 引擎测试 swiftc 列表含 LyricMatcher＋LRCLibClient（run 46134758976 教训：LyricParser 引 LyricMatcher，列表缺了就编不过）",
      "PlaybackEngine/LyricMatcher.swift" in by
      and "Lyrics/LRCLibClient.swift" in by
      and "EngineTests/main.swift" in by)
check("P0 回归门：EngineTests 覆盖 lyricsfile 解析＋合并（CI 里跑）",
      "LyricsFileParser.parse(yaml)" in read("EngineTests/main.swift")
      and "mergingWordSync(into: rows, lyricsFile: yaml)" in read("EngineTests/main.swift"))

print("\n== OPEN（需 macOS／真机） ==")
open_item("真机：卡拉OK（2.0.6 新）——有逐字词的歌药丸逐字亮、歌卡逐字亮；日志里找「歌词匹配成功：…（N 行，逐字 M 行，共 W 词）」与守护进程「hud: lyrics now … karaoke N words」",
          "见 RUN_2.0.6.md 清单，等 Lee")
open_item("macOS 编译（xcodebuild archive）：Linux 无 Xcode", "CI 见分晓")
open_item("daemon dSYM 是否进 archive（3 个）", "build.yml 已断言，CI 日志为准")
open_item("真机：重装后免激活（全新安装激活一次 → 删 App → 重装 → 不弹激活页）",
          "见 RUN_2.0.1.md 清单，等 Lee")
open_item("真机：主页面无假开关，药丸只从设置页 HUD 区段启用",
          "见 RUN_2.0.1.md 清单，等 Lee")
open_item("真机：Enable／stale-plist 回归／五项歌词／10 次锁解／30 分钟后台",
          "见 RUN_2.0.0.md 清单，等 Lee")
open_item("真机：LC 模式下 daemon 不出现", "见 RUN_2.0.0.md 清单，等 Lee")
open_item("真机：药丸触摸（2.0.5 新）——点药丸拖动跟手、点药丸外 App 正常接事件",
          "见 RUN_2.0.6.md 清单，等 Lee")
open_item("真机：守护进程日志里 hid: probe event／hid: touch in pill, injecting",
          "见 RUN_2.0.6.md 清单，等 Lee")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens))
sys.exit(1 if fails else 0)
