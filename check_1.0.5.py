#!/usr/bin/env python3
"""Verify TrollLyricsDesk 1.0.5 (1.0.3 + DualProcess merge):
1.0.5 = 1.0.3 底子＋皇上发来的 1.0.4 DualProcess 源码包融合。
独立版（TrollStore）保留 MediaRemote、FrontBoard、Live Activity、激活；
新增 DualProcessBridge：独立版在 127.0.0.1:38473 起只读 TCP 服务，
LC 版（LiveContainer）每秒读歌词快照；两端分别激活；配对码是本机
UUID（tlds.bridge.token），不是激活码。LC 开关双保险：运行时读
Info.plist 的 TLDSLiveContainer 键（LyricStore.isLiveContainer），
编译期 -DTLDS_LIVE_CONTAINER=1 只进 Overlay 的 .m 文件；TrollStore
构建两者都没有，行为与 1.0.3 一致（只多一个本机桥服务＋配对码按钮）。
1.0.5 不修 Telegram 行点了没反应、不修锁屏歌词不见（那两件还在等
皇上回对照测试结果）。

红线锚点是固定基点 0e1e014（1.0.3 末提交），提交后再重跑才算数。
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
BASE = "0e1e014"
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


def diff_names():
    out = subprocess.check_output(
        ["git", "diff", "--name-only", BASE, "HEAD"],
        cwd=ROOT, text=True).strip().splitlines()
    return sorted(f for f in out if f.strip())


def diff_text(rel):
    return subprocess.check_output(
        ["git", "diff", BASE, "HEAD", "--", rel],
        cwd=ROOT, text=True)


def added_removed(rel):
    """(added_lines, removed_lines) in the BASE..HEAD diff of one path,
    excluding the ---/+++ headers."""
    added, removed = [], []
    for ln in diff_text(rel).splitlines():
        if ln.startswith("+++") or ln.startswith("---"):
            continue
        if ln.startswith("+"):
            added.append(ln[1:])
        elif ln.startswith("-"):
            removed.append(ln[1:])
    return added, removed


def plist(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return plistlib.load(f)


print("== 1. 版本（1.0.5/build 17，两处一致）==")
app_pl = plist("TrollLyricsDesk/Info.plist")
wid_pl = plist("TrollLyricsWidget/Info.plist")
check("App Info.plist: version 1.0.5",
      app_pl.get("CFBundleShortVersionString") == "1.0.5",
      str(app_pl.get("CFBundleShortVersionString")))
check("App Info.plist: build 17",
      app_pl.get("CFBundleVersion") == "17",
      str(app_pl.get("CFBundleVersion")))
check("Widget Info.plist: version 1.0.5",
      wid_pl.get("CFBundleShortVersionString") == "1.0.5",
      str(wid_pl.get("CFBundleShortVersionString")))
check("Widget Info.plist: build 17",
      wid_pl.get("CFBundleVersion") == "17",
      str(wid_pl.get("CFBundleVersion")))
check("App Info.plist: MinOS 15.0",
      app_pl.get("MinimumOSVersion") == "15.0",
      str(app_pl.get("MinimumOSVersion")))
check("Widget Info.plist: MinOS 15.0",
      wid_pl.get("MinimumOSVersion") == "15.0",
      str(wid_pl.get("MinimumOSVersion")))
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: MARKETING_VERSION 1.0.5 (4x)",
      pbx.count("MARKETING_VERSION = 1.0.5;") == 4
      and "MARKETING_VERSION = 1.0.3;" not in pbx
      and "MARKETING_VERSION = 1.0.4;" not in pbx)
build_yml = read(".github/workflows/build.yml")
check("build.yml: artifact 桌面歌词-1.0.5.ipa",
      "桌面歌词-1.0.5.ipa" in build_yml
      and "桌面歌词-1.0.4" not in build_yml
      and "桌面歌词-1.0.3" not in build_yml)
lc_yml = read(".github/workflows/livecontainer.yml")
check("livecontainer.yml: dist TrollLyricsDesk-1.0.5-LiveContainer.ipa",
      "dist/TrollLyricsDesk-1.0.5-LiveContainer.ipa" in lc_yml
      and "1.0.4-LiveContainer" not in lc_yml)
check("DUAL_PROCESS.md: title 1.0.5",
      read("DUAL_PROCESS.md").startswith("# 1.0.5 双进程实验版"))

print("\n== 2. DualProcess 文件都在 ==")
for rel in [".github/workflows/livecontainer.yml",
            "DUAL_PROCESS.md", "LIVE_CONTAINER.md",
            "scripts/build-livecontainer.sh"]:
    check(f"exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))
app_swift = read("App/TrollLyricsDeskApp.swift")
check("DualProcessBridge class in TrollLyricsDeskApp.swift",
      "final class DualProcessBridge" in app_swift
      and "static let shared = DualProcessBridge()" in app_swift)
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

print("\n== 4. LC 开关机制（TrollStore 版不带 LC 行为）==")
store = read("Lyrics/LyricStore.swift")
check("LyricStore.isLiveContainer reads plist key TLDSLiveContainer",
      'Bundle.main.object(forInfoDictionaryKey: "TLDSLiveContainer")'
      in store)
check("LyricStore.defaults switches on isLiveContainer",
      "isLiveContainer ? .standard : UserDefaults(suiteName: groupID)"
      in store)
check("TrollStore Info.plist: no TLDSLiveContainer key",
      "TLDSLiveContainer" not in app_pl)
check("build.yml: no TLDS_LIVE_CONTAINER flag",
      "TLDS_LIVE_CONTAINER" not in build_yml)
check("pbxproj: no TLDS_LIVE_CONTAINER flag",
      "TLDS_LIVE_CONTAINER" not in pbx)
lc_sh = read("scripts/build-livecontainer.sh")
check("LC script: sets TLDSLiveContainer=true in plist copy",
      "d['TLDSLiveContainer']=True" in lc_sh)
check("LC script: passes -DTLDS_LIVE_CONTAINER=1",
      "-DTLDS_LIVE_CONTAINER=1" in lc_sh)
check("LC script: strips PlugIns (no widget in LC IPA)",
      "rm -rf Payload/TrollLyricsDesk.app/PlugIns" in lc_sh)
check("LC script: removes BSServiceDomains/UIBackgroundModes/"
      "NSSupportsLiveActivities from LC plist copy",
      "for k in ('BSServiceDomains','UIBackgroundModes',"
      "'NSSupportsLiveActivities')" in lc_sh)
check("livecontainer.yml: runs the LC script",
      "bash scripts/build-livecontainer.sh" in lc_yml)
check("livecontainer.yml: artifact name TrollLyricsDesk-LiveContainer",
      "name: TrollLyricsDesk-LiveContainer" in lc_yml)

print("\n== 5. 两 workflow 都是 push 触发 ==")
check("build.yml: on push",
      re.search(r"^on:\s*\n\s+push:", build_yml, re.M) is not None
      or "on: push:" in build_yml)
check("livecontainer.yml: on push",
      "push:" in lc_yml)

print("\n== 6. Info.plist 三项都在（TrollStore 版）==")
check("App plist: UIBackgroundModes == [audio]",
      app_pl.get("UIBackgroundModes") == ["audio"],
      str(app_pl.get("UIBackgroundModes")))
check("App plist: NSSupportsLiveActivities == true",
      app_pl.get("NSSupportsLiveActivities") is True)
check("App plist: BSServiceDomains present",
      "BSServiceDomains" in app_pl)
check("App plist: no TLDSLiveContainer key (see §4)",
      "TLDSLiveContainer" not in app_pl)

print("\n== 7. 激活串仍在位（1.0.3 回归）==")
act = read("App/ActivationView.swift")
for s in ["api/verify", "tld.activated", "tld.activationType",
          "首次使用需要激活码", "需要联网激活", "激活码不正确"]:
    check(f"activation string in place: {s}", s in act or s in store)
check("ActivationGateView wraps root",
      "ActivationGateView" in app_swift)
check("activation: no TLD- code literal in ActivationView",
      re.search(r"TLD-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}", act) is None)

print("\n== 8. 源码里扫不到 TLD- 格式码值 ==")
code_re = re.compile(r"TLD-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}")
hits = []
for dirpath, _dirs, files in os.walk(ROOT):
    if ".git" in dirpath:
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

print("\n== 9. ActivityKit 弱链接（1.0.3 回归）==")
check("pbxproj: ActivityKit weak-linked (4x: App 2 + Widget 2)",
      pbx.count('"-weak_framework"') == 4
      and pbx.count('"ActivityKit"') == 4,
      f"weak={pbx.count(chr(34) + '-weak_framework' + chr(34))}")
check("pbxproj: no strong ActivityKit link phase entry",
      "ActivityKit.framework" not in pbx)

print("\n== 10. 红线（diff vs 0e1e014）==")
names = diff_names()
expected_modified = sorted([
    ".github/workflows/build.yml",
    "App/ActivationView.swift", "App/ContentView.swift",
    "App/LyricsSearchView.swift", "App/PlaybackDashboardView.swift",
    "App/SettingsView.swift", "App/TrollLyricsDeskApp.swift",
    "BUILD_NOTES.md", "RUN_1.0.3.md",
    "Lyrics/LyricStore.swift",
    "Overlay/TLDSAppDelegate.m", "Overlay/TLDSSceneDelegate.m",
    "PlaybackEngine/LyricsLiveActivityController.swift",
    "PlaybackEngine/PlaybackCoordinator.swift",
    "TrollLyricsDesk/Info.plist",
    "TrollLyricsDesk.xcodeproj/project.pbxproj",
    "TrollLyricsWidget/Info.plist",
])
expected_new = sorted([
    ".github/workflows/livecontainer.yml",
    "DUAL_PROCESS.md", "LIVE_CONTAINER.md",
    "check_1.0.5.py", "scripts/build-livecontainer.sh",
])
check("red line: changed files == expected set (17 modified + 5 new)",
      names == sorted(expected_modified + expected_new),
      f"got {len(names)} files; extra="
      f"{sorted(set(names) - set(expected_modified + expected_new))}; "
      f"missing={sorted(set(expected_modified + expected_new) - set(names))}")
# Overlay/: only #ifndef/#ifdef guard lines may be added, nothing removed.
for rel in ["Overlay/TLDSAppDelegate.m", "Overlay/TLDSSceneDelegate.m"]:
    added, removed = added_removed(rel)
    allowed = {"#ifndef TLDS_LIVE_CONTAINER", "#endif",
               "#ifdef TLDS_LIVE_CONTAINER", "isMain = YES;",
               "isFloating = NO;", ""}
    check(f"red line: {rel} only gains LC guards",
          not removed and all(a.strip() in allowed for a in added),
          f"added={len(added)} removed={len(removed)}")
# LyricsLiveActivityController: only the defaults line changes.
added, removed = added_removed(
    "PlaybackEngine/LyricsLiveActivityController.swift")
check("red line: LyricsLiveActivityController only swaps defaults source",
      len(added) == 1 and len(removed) == 1
      and "LyricStore.defaults" in added[0]
      and "UserDefaults(suiteName: LyricStore.groupID)" in removed[0],
      f"added={added} removed={removed}")
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

print("\n== OPEN（真机必验，DUAL_PROCESS.md 未验证清单原样记）==")
open_item("loopback 可达性（DUAL_PROCESS.md）",
          "LC 版在 LiveContainer 里能不能连上 127.0.0.1:38473，要真机验")
open_item("后台挂起（DUAL_PROCESS.md）",
          "独立版被挂起或杀死时桥不可用，没有系统守护进程兜底")
open_item("宿主网络限制（DUAL_PROCESS.md）",
          "LiveContainer 宿主的网络限制会不会挡住本机回环，要真机验")
open_item("切歌／暂停／拖进度（DUAL_PROCESS.md）",
          "桥接下切歌、暂停、拖进度跟不跟，旧快照会不会残留显示")
open_item("配对失败和重连（DUAL_PROCESS.md）",
          "配对码错了、独立版没开、重连时 LC 版的表现")
open_item("未连接时旧快照可能仍显示（DUAL_PROCESS.md）",
          "连接状态只表示收到快照，不保证音乐仍在播放")
open_item("LC 偏好隔离／网络激活／导入行为未验证（LIVE_CONTAINER.md）",
          "原工程私有框架链接设置保留，可能需要进一步精简")
open_item("LC 版没有全局悬浮窗和锁屏歌词（LIVE_CONTAINER.md）",
          "这是设计：LC 版不提供这两项，不要当 bug 报")
open_item("Telegram 行点了没反应（1.0.3 结转，1.0.5 没修）",
          "等皇上回 QQ 行对照测试结果；不要宣称 1.0.5 修了")
open_item("锁屏歌词显示后不见（1.0.3 结转，1.0.5 没修）",
          "等皇上确认不见时屏幕亮不亮＋锁屏开关状态；不要宣称 1.0.5 修了")
open_item("1.0.2 五件真机验（结转）",
          "背景图／悬浮窗固定／日志复制清除／Telegram 行／提示文字＋标题居中")
open_item("1.0.3 激活真机验（结转，已通一次）",
          "首次打开输码、错码／没网各提示各的、杀掉重开不再要码、"
          "卸载重装要重新激活")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens), "items (see above)")
sys.exit(1 if fails else 0)
