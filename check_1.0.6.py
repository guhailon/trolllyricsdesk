#!/usr/bin/env python3
"""Verify TrollLyricsDesk 1.0.6 (single IPA, runtime environment detection):
1.0.6 = 1.0.5 的 TrollStore 版＋LC 版融合成一个版本、一个 IPA。
运行时判断取代编译期分流：LyricStore.isLiveContainer 读
LC_HOME_PATH 环境变量（LiveContainer 宿主起客人前设）或包体路径
（宿主 Documents/Applications/ 或 LiveContainer/Applications/）；
都命不中默认独立版。Overlay 两个 .m 文件的 #ifdef TLDS_LIVE_CONTAINER
守卫改成运行时判断（TLDSEnvironment 桥）。livecontainer.yml 和
scripts/build-livecontainer.sh 已删，只剩 build.yml 一个 workflow，
产物只有一个 桌面歌词-1.0.6.ipa（zsign 签名）。
1.0.6 不修 Telegram 行点了没反应、不修锁屏歌词不见（那两件还在等
皇上回对照测试结果）。

红线锚点是固定基点 c68acc6（1.0.5 融合提交），提交后再重跑才算数。
不要用 `git diff HEAD`（提交后工作区干净，diff 永远是空），
也不要用 HEAD~1（每多一个提交就漂走）。

FAILED: none is the goal. OPEN items are recorded, not failures:
things that cannot be verified on Linux (macOS compile, device) or that
need Lee's device test (DUAL_PROCESS.md 未验证清单＋1.0.3 结转项)。
"""
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = "c68acc6"
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


def tracked_files():
    out = subprocess.check_output(
        ["git", "ls-files"], cwd=ROOT, text=True)
    return [f for f in out.strip().splitlines() if f.strip()]


def diff_names():
    out = subprocess.check_output(
        ["git", "diff", "--name-only", BASE, "HEAD"],
        cwd=ROOT, text=True).strip().splitlines()
    return sorted(f for f in out if f.strip())


def diff_text(rel):
    return subprocess.check_output(
        ["git", "diff", BASE, "HEAD", "--", rel],
        cwd=ROOT, text=True)


def plist(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return plistlib.load(f)


print("== 1. 版本（1.0.6/build 18，两处一致）==")
app_pl = plist("TrollLyricsDesk/Info.plist")
wid_pl = plist("TrollLyricsWidget/Info.plist")
check("App Info.plist: version 1.0.6",
      app_pl.get("CFBundleShortVersionString") == "1.0.6",
      str(app_pl.get("CFBundleShortVersionString")))
check("App Info.plist: build 18",
      app_pl.get("CFBundleVersion") == "18",
      str(app_pl.get("CFBundleVersion")))
check("Widget Info.plist: version 1.0.6",
      wid_pl.get("CFBundleShortVersionString") == "1.0.6",
      str(wid_pl.get("CFBundleShortVersionString")))
check("Widget Info.plist: build 18",
      wid_pl.get("CFBundleVersion") == "18",
      str(wid_pl.get("CFBundleVersion")))
check("App Info.plist: MinOS 15.0",
      app_pl.get("MinimumOSVersion") == "15.0",
      str(app_pl.get("MinimumOSVersion")))
check("Widget Info.plist: MinOS 15.0",
      wid_pl.get("MinimumOSVersion") == "15.0",
      str(wid_pl.get("MinimumOSVersion")))
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: MARKETING_VERSION 1.0.6 (4x)",
      pbx.count("MARKETING_VERSION = 1.0.6;") == 4
      and "MARKETING_VERSION = 1.0.5;" not in pbx)
build_yml = read(".github/workflows/build.yml")
check("build.yml: artifact 桌面歌词-1.0.6.ipa",
      "桌面歌词-1.0.6.ipa" in build_yml
      and "桌面歌词-1.0.5" not in build_yml)
check("DUAL_PROCESS.md: title 1.0.6",
      read("DUAL_PROCESS.md").startswith("# 1.0.6 单包双进程版"))
check("LIVE_CONTAINER.md: title 1.0.6 single package",
      "1.0.6" in read("LIVE_CONTAINER.md").splitlines()[0])

print("\n== 2. 分流构建已删，只剩一个 workflow、一个产物 ==")
check("livecontainer.yml deleted",
      not os.path.exists(os.path.join(ROOT, ".github/workflows/livecontainer.yml")))
check("scripts/build-livecontainer.sh deleted",
      not os.path.exists(os.path.join(ROOT, "scripts/build-livecontainer.sh")))
check("only build.yml in .github/workflows",
      sorted(os.listdir(os.path.join(ROOT, ".github/workflows"))) == ["build.yml"])
check("build.yml: on push",
      re.search(r"^on:\s*\n\s+push:", build_yml, re.M) is not None
      or "on: push:" in build_yml)
check("build.yml: single upload-artifact (one IPA)",
      build_yml.count("upload-artifact") == 1)
for rel in ["DUAL_PROCESS.md", "LIVE_CONTAINER.md"]:
    check(f"exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))
app_swift = read("App/TrollLyricsDeskApp.swift")
check("DualProcessBridge class still in TrollLyricsDeskApp.swift",
      "final class DualProcessBridge" in app_swift)
check("DualProcessBridge.start() called at launch",
      "DualProcessBridge.shared.start()" in app_swift)

print("\n== 3. 桥接串在位 ==")
check("bridge port 38473", "38473" in app_swift)
check("bridge token key tlds.bridge.token",
      'static let tokenKey = "tlds.bridge.token"' in app_swift)
check("bridge freshness key tlds.bridge.lastReceived",
      'static let freshnessKey = "tlds.bridge.lastReceived"' in app_swift)
check("bridge binds loopback only",
      '"127.0.0.1"' in app_swift)
check("bridge server requires activation",
      "ActivationStore.isActivated" in app_swift)
check("bridge token is UUID (not a TLD- code)",
      "UUID().uuidString" in app_swift)

print("\n== 4. 运行时环境判断（取代编译期分流）==")
store = read("Lyrics/LyricStore.swift")
check("detector: LC_HOME_PATH env signal",
      'environment["LC_HOME_PATH"]' in store)
check("detector: bundle path signal /Documents/Applications/",
      '"/Documents/Applications/"' in store)
check("detector: bundle path signal /LiveContainer/Applications/",
      '"/LiveContainer/Applications/"' in store)
check("detector: cached once (static let, not computed var)",
      "static let isLiveContainer: Bool = {" in store)
check("detector: defaults to standalone (return false at end)",
      "return false\n    }()" in store)
check("ObjC bridge TLDSEnvironment exists",
      "@objc(TLDSEnvironment)" in store
      and "isLiveContainerGuest" in store)
check("mode logged at startup (TrollLyricsDeskApp.swift)",
      "运行环境：LiveContainer 客人" in app_swift
      and "运行环境：独立版" in app_swift)
check("LyricStore.defaults still switches on isLiveContainer",
      "isLiveContainer ? .standard : UserDefaults(suiteName: groupID)"
      in store)
# No compile-time split left in current source (historical RUN/check
# docs from 1.0.5 legitimately mention the old mechanism; exclude them).
flag_hits = []
for rel in tracked_files():
    if rel.startswith(("check_", "RUN_")) or rel == "BUILD_NOTES.md":
        continue
    try:
        if "TLDS_LIVE_CONTAINER" in read(rel) \
                or "TLDSLiveContainer" in read(rel):
            flag_hits.append(rel)
    except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
        # FileNotFoundError: file deleted in worktree, not yet committed
        # (livecontainer.yml / build-livecontainer.sh) — that is the point.
        pass
check("no TLDS_LIVE_CONTAINER / TLDSLiveContainer in current source",
      not flag_hits, str(flag_hits))
app_del = read("Overlay/TLDSAppDelegate.m")
scene_del = read("Overlay/TLDSSceneDelegate.m")
check("AppDelegate: no #ifdef/#ifndef TLDS_LIVE_CONTAINER",
      "#ifdef TLDS_LIVE_CONTAINER" not in app_del
      and "#ifndef TLDS_LIVE_CONTAINER" not in app_del)
check("SceneDelegate: no #ifdef/#ifndef TLDS_LIVE_CONTAINER",
      "#ifdef TLDS_LIVE_CONTAINER" not in scene_del
      and "#ifndef TLDS_LIVE_CONTAINER" not in scene_del)
check("AppDelegate: runtime gate on startFloatingOverlay",
      "[TLDSEnvironment isLiveContainerGuest]" in app_del
      and "startFloatingOverlay" in app_del)
check("SceneDelegate: runtime gate forces main scene in LC guest",
      "[TLDSEnvironment isLiveContainerGuest]" in scene_del)
check("AppDelegate: startFloatingOverlay still defined",
      "- (void)startFloatingOverlay" in app_del)
check("AppDelegate: FBSystemShellInitialize still present",
      "FBSystemShellInitialize" in app_del)

print("\n== 5. Info.plist 三项都在（单包保留 TrollStore 键）==")
check("App plist: UIBackgroundModes == [audio]",
      app_pl.get("UIBackgroundModes") == ["audio"],
      str(app_pl.get("UIBackgroundModes")))
check("App plist: NSSupportsLiveActivities == true",
      app_pl.get("NSSupportsLiveActivities") is True)
check("App plist: BSServiceDomains present",
      "BSServiceDomains" in app_pl)
check("App plist: no TLDSLiveContainer key",
      "TLDSLiveContainer" not in app_pl)
check("App plist: display name 桌面歌词 (not LC)",
      app_pl.get("CFBundleDisplayName") == "桌面歌词",
      str(app_pl.get("CFBundleDisplayName")))

print("\n== 6. 激活串仍在位（1.0.3 回归）==")
act = read("App/ActivationView.swift")
for s in ["api/verify", "tld.activated", "tld.activationType",
          "首次使用需要激活码", "需要联网激活", "激活码不正确"]:
    check(f"activation string in place: {s}", s in act or s in store)
check("ActivationGateView wraps root",
      "ActivationGateView" in app_swift)
check("activation: no TLD- code literal in ActivationView",
      re.search(r"TLD-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}", act) is None)

print("\n== 7. 源码里扫不到 TLD- 格式码值 ==")
code_re = re.compile(r"TLD-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}")
hits = []
for dirpath, _dirs, files in os.walk(ROOT):
    if ".git" in dirpath or "hidden_files" in dirpath:
        continue
    for fn in files:
        if fn.startswith("check_") or fn.startswith("RUN_") \
                or fn in ("BUILD_NOTES.md",):
            continue
        p = os.path.join(dirpath, fn)
        try:
            with open(p, encoding="utf-8", errors="ignore") as f:
                if code_re.search(f.read()):
                    hits.append(os.path.relpath(p, ROOT))
        except IsADirectoryError:
            pass
check("no TLD- code values in source (excluding old check/RUN/docs)",
      not hits, str(hits))

print("\n== 8. ActivityKit 弱链接（1.0.3 回归）==")
check("pbxproj: ActivityKit weak-linked (4x: App 2 + Widget 2)",
      pbx.count('"-weak_framework"') == 4
      and pbx.count('"ActivityKit"') == 4,
      f"weak={pbx.count(chr(34) + '-weak_framework' + chr(34))}")
check("pbxproj: no strong ActivityKit link phase entry",
      "ActivityKit.framework" not in pbx)

print("\n== 9. 红线（diff vs c68acc6）==")
names = diff_names()
expected_modified = sorted([
    ".github/workflows/build.yml",
    "App/TrollLyricsDeskApp.swift",
    "DUAL_PROCESS.md", "LIVE_CONTAINER.md",
    "Lyrics/LyricStore.swift",
    "Overlay/TLDSAppDelegate.m", "Overlay/TLDSSceneDelegate.m",
    "TrollLyricsDesk.xcodeproj/project.pbxproj",
    "TrollLyricsDesk/Info.plist",
    "TrollLyricsWidget/Info.plist",
])
expected_new = sorted(["RUN_1.0.5.md", "check_1.0.5.py", "check_1.0.6.py"])
expected_deleted = sorted([
    ".github/workflows/livecontainer.yml",
    "scripts/build-livecontainer.sh",
])
expected = sorted(expected_modified + expected_new + expected_deleted)
check("red line: changed files == expected set "
      "(10 modified + 3 new + 2 deleted)",
      names == expected,
      f"got {len(names)} files; extra="
      f"{sorted(set(names) - set(expected))}; "
      f"missing={sorted(set(expected) - set(names))}")
# Lockscreen behaviour untouched: publishLiveLyrics + Activity config stay.
pc = read("PlaybackEngine/PlaybackCoordinator.swift")
check("red line: publishLiveLyrics still in PlaybackCoordinator",
      "private func publishLiveLyrics()" in pc
      and pc.count("publishLiveLyrics()") == 3)
live = read("LiveActivity/LyricsLiveActivity.swift")
check("red line: LiveActivity file untouched (ActivityConfiguration)",
      "ActivityConfiguration(for: LyricsLiveAttributes.self)" in live)
check("red line: no BackBoard/TLHUDApplication/-hud/dynamic_lookup "
      "introduced",
      "BackBoard" not in app_swift and "TLHUDApplication" not in app_swift
      and "-hud" not in app_swift
      and "dynamic_lookup" not in app_swift)

print("\n== OPEN（真机必验）==")
open_item("LiveContainer 认不认单包（最大未知数）",
          "单包保留 plist 三键＋Widget＋zsign 签名；1.0.5 的 LC 包是无签名"
          "去键版。如果皇上真机导入失败，1.0.5 的 LC 包"
          "（桌面歌词-1.0.5-LiveContainer.ipa）是已知的退路，不要删它")
open_item("运行时判断在真机上准不准",
          "日志页看模式：TrollStore 装的应显示独立版，LiveContainer 里"
          "导入的应显示 LC 客人；误判方向决定修哪边")
open_item("桥接（两 App 同一台 iPhone 11 上配对）",
          "先装独立版并启动、复制配对码，再在同一台手机的 LiveContainer"
          "里导入同一个包、粘贴配对码；跨手机连不上（本机回环）")
open_item("loopback 可达性（DUAL_PROCESS.md）",
          "LC 客人在 LiveContainer 里能不能连上 127.0.0.1:38473，要真机验")
open_item("后台挂起（DUAL_PROCESS.md）",
          "独立版被挂起或杀死时桥不可用，没有系统守护进程兜底")
open_item("宿主网络限制（DUAL_PROCESS.md）",
          "LiveContainer 宿主的网络限制会不会挡住本机回环，要真机验")
open_item("切歌／暂停／拖进度（DUAL_PROCESS.md）",
          "桥接下切歌、暂停、拖进度跟不跟，旧快照会不会残留显示")
open_item("配对失败和重连（DUAL_PROCESS.md）",
          "配对码错了、独立版没开、重连时 LC 客人的表现")
open_item("未连接时旧快照可能仍显示（DUAL_PROCESS.md）",
          "连接状态只表示收到快照，不保证音乐仍在播放")
open_item("小组件与 LC 客人不同存储",
          "LC 客人写标准偏好，小组件读 App Group——LC 客人里的歌词"
          "不会进小组件；独立版不受影响")
open_item("Telegram 行点了没反应（1.0.3 结转，1.0.6 没修）",
          "等皇上回 QQ 行对照测试结果；不要宣称 1.0.6 修了")
open_item("锁屏歌词显示后不见（1.0.3 结转，1.0.6 没修）",
          "等皇上确认不见时屏幕亮不亮＋锁屏开关状态；不要宣称 1.0.6 修了")
open_item("1.0.2 五件真机验（结转）",
          "背景图／悬浮窗固定／日志复制清除／Telegram 行／提示文字＋标题居中")
open_item("1.0.3 激活真机验（结转，已通一次）",
          "首次打开输码、错码／没网各提示各的、杀掉重开不再要码、"
          "卸载重装要重新激活")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens), "items (see above)")
sys.exit(1 if fails else 0)
