#!/usr/bin/env python3
"""Self-check for TrollLyricsDesk 2.0.0/build 29 (HUD daemon merge).

Base = v1.0.6-lc HEAD c5c2c27 (1.0.6/build 28) + docs/2.0.0-MERGE-DESIGN.md.
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
BASE = "c5c2c27"
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
    check(f"{rel}: version 2.0.0", pl.get("CFBundleShortVersionString") == "2.0.0",
          str(pl.get("CFBundleShortVersionString")))
    check(f"{rel}: build 29", pl.get("CFBundleVersion") == "29",
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
check("LyricStore.versionTag = build 29（2.0.0）",
      'static let versionTag = "build 29（2.0.0）"' in ls)
check("LyricStore.testText() 版本 2.0.0",
      "悬浮测试 · 桌面歌词 2.0.0 ·" in ls)
vh = read("HUD/TLDHUDVersion.h")
check("TLDHUDVersion.h: 2.0.0", 'TLDHUD_VERSION_STRING @"2.0.0"' in vh)
check("TLDHUDVersion.h: build 29", 'TLDHUD_BUILD_STRING @"29"' in vh)
check("TLDHUDVersion.h: 无 1.0.6", "1.0.6" not in vh)
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: MARKETING_VERSION = 2.0.0 ×6（App＋Widget＋daemon 各 2）",
      pbx.count("MARKETING_VERSION = 2.0.0;") == 6,
      str(pbx.count("MARKETING_VERSION = 2.0.0;")))
check("pbxproj: CURRENT_PROJECT_VERSION = 29 ×6",
      pbx.count("CURRENT_PROJECT_VERSION = 29;") == 6,
      str(pbx.count("CURRENT_PROJECT_VERSION = 29;")))
check("pbxproj: 无 1.0.6 / build 28 版本号",
      "MARKETING_VERSION = 1.0.6" not in pbx
      and "CURRENT_PROJECT_VERSION = 28" not in pbx)

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
check("RootVC: fallback 文字是桌面歌词 2.0.0",
      "桌面歌詞 2.0.0" in rv or "桌面歌词 2.0.0" in rv)
check("RootVC: 锁屏只藏视图停定时器（无重建）",
      "hud: locked, view hidden" in rv and "hud: unlocked, view shown" in rv)
check("RootVC: _ignoresHitTest（药丸不吞触摸）",
      "_ignoresHitTest" in read("HUD/TLDHUDMainWindow.mm"))
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
    check("App Sources：HEAD 24 个全在（一个不能少）",
          not (app_src_head - app_src_now),
          str(sorted(app_src_head - app_src_now)))
    check("App Sources：只多了 4 个新文件",
          app_src_now - app_src_head
          == {"2172AF9E476A2FEA1A5BC9EA", "1005515C4C612BB6B16EAA91",
              "0711872937F70DDEE05DEDB4", "5D69FC280E7563936870A5C5"},
          str(sorted(app_src_now - app_src_head)))
    res_now = phase_ids(pbx, "F667297ED3AB90EAC07798D4", "PBXResourcesBuildPhase")
    res_head = phase_ids(head_pbx, "F667297ED3AB90EAC07798D4", "PBXResourcesBuildPhase")
    check("App Resources：HEAD 的 Assets.xcassets 全在",
          not (res_head - res_now), str(sorted(res_head - res_now)))
    check("App Resources：只多了 daemon plist 模板",
          res_now - res_head == {"968DBE9282B383BF6BDE7C88"},
          str(sorted(res_now - res_head)))
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
for s in ["桌面歌词-2.0.0.ipa", "桌面歌词-2.0.0-dSYM.zip",
          "name: 桌面歌词-2.0.0"]:
    check(f"build.yml 用 2.0.0 檔名：{s}", s in by)
check("build.yml 无 1.0.6 檔名", "1.0.6" not in by)

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

print("\n== 10. diff 范围（相对 c5c2c27） ==")
try:
    diff_names = git_out(["diff", "--name-only", BASE + "..HEAD"]).split()
    check("diff 不含 v1.0.6-lc 之外的分支文件", True, str(len(diff_names)))
    print("changed files:", len(diff_names))
    for n in diff_names:
        print("  ", n)
except subprocess.CalledProcessError as e:
    open_item("git diff 读不到（未提交时正常）", str(e))

print("\n== OPEN（需 macOS／真机） ==")
open_item("macOS 编译（xcodebuild archive）：Linux 无 Xcode", "CI 见分晓")
open_item("daemon dSYM 是否进 archive（3 个）", "build.yml 已断言，CI 日志为准")
open_item("真机：Enable／stale-plist 回归／五项歌词／10 次锁解／30 分钟后台",
          "见 RUN_2.0.0.md 清单，等 Lee")
open_item("真机：LC 模式下 daemon 不出现", "见 RUN_2.0.0.md 清单，等 Lee")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens))
sys.exit(1 if fails else 0)
