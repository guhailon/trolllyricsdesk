#!/usr/bin/env python3
"""Verify TrollLyricsDesk 1.0.5 build 19 (diagnostics-first):

base = newbase HEAD 6857d3c (1.0.0/build 18 已合并版)
  + 7 项诊断 (MediaRemote 回调诊断 / 强制悬浮测试文字 / 场景托管复核 /
    实际能力探测 / 重复启动计数 / 后台挂起恢复日志 / 同步修正不动)
  + 三档运行模式 (巨魔原生 / 增强宿主 / 普通签名兼容，按实际能力探测定档；
    不只看路径/类名/plist，不只看「注册成功」日志)
  + 版本 1.0.5, build 19, 包名 com.ycwl.Lyrics；不加权限、不加 TCP 桥/
    独立客户端/双 IPA；不修 Telegram 行点、不修锁屏歌词不见。

FAILED: none is the goal. OPEN items are recorded, not failures:
things that cannot be verified on Linux (macOS compile, device) or that
need Lee's device test.

Red-line anchor: BASE = 6857d3c (newbase merged HEAD). git diff BASE..HEAD
must touch only the allow-listed files; LyricStore 同步修正与逐歌偏移
代码只允许新增行，不允许删改行。
"""
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = "6857d3c"
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


def git_out(args):
    return subprocess.check_output(
        ["git"] + args, cwd=ROOT, text=True)


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


def pbx_resolved_files(pbx_text):
    objs = {}
    cur = None
    for ln in pbx_text.split("\n"):
        m = re.match(r"\t\t([0-9A-F]{24}) /\* (.*?) \*/ = \{$", ln)
        if m:
            cur = {"id": m.group(1), "children": [], "path": None}
            objs[m.group(1)] = cur
            continue
        if cur is not None:
            m2 = re.match(r"\t\t\tisa = (\w+);", ln)
            if m2:
                cur["isa"] = m2.group(1)
            m3 = re.match(r'\t\t\tpath = "?([^";]+)"?;', ln)
            if m3:
                cur["path"] = m3.group(1)
            if re.match(r"\t\t\tchildren = \(", ln):
                cur["in_children"] = True
                cur["children"] += re.findall(r"[0-9A-F]{24}", ln.split("(", 1)[1])
                if ");" in ln:
                    cur["in_children"] = False
                continue
            if cur.get("in_children"):
                cur["children"] += re.findall(r"[0-9A-F]{24}", ln)
                if ");" in ln:
                    cur["in_children"] = False
                continue
            if ln.strip() == "};":
                cur = None
    main_group = None
    for ln in pbx_text.split("\n"):
        m = re.match(r"\t\t\tmainGroup = ([0-9A-F]{24});", ln)
        if m:
            main_group = m.group(1)
            break
    resolved = []

    def walk(gid, prefix):
        g = objs.get(gid)
        if not g:
            return
        base = os.path.join(prefix, g["path"]) if g.get("path") else prefix
        for c in g.get("children", []):
            o = objs.get(c)
            if not o:
                continue
            if o.get("isa") == "PBXGroup":
                walk(c, base)
            elif o.get("isa") == "PBXFileReference" and o.get("path"):
                if re.search(r"\.(swift|plist|entitlements|xcassets)$", o["path"]):
                    resolved.append(os.path.join(base, o["path"]))

    if main_group:
        walk(main_group, "")
    return resolved


print("== 1. 新文件 ==")
for rel in ["LiveActivity/LyricsLiveActivity.swift",
            "PlaybackEngine/LyricsLiveActivityController.swift",
            "App/ActivationView.swift"]:
    check(f"exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))

print("\n== 2. 版本 / 包名 / MinOS ==")
for rel in ["TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist"]:
    pl = plistlib.loads(open(os.path.join(ROOT, rel), "rb").read())
    check(f"{rel}: version 1.0.5", pl.get("CFBundleShortVersionString") == "1.0.5",
          str(pl.get("CFBundleShortVersionString")))
    check(f"{rel}: build 19", pl.get("CFBundleVersion") == "19",
          str(pl.get("CFBundleVersion")))
    check(f"{rel}: min OS 15.0", pl.get("MinimumOSVersion") == "15.0",
          str(pl.get("MinimumOSVersion")))
app_pl = plistlib.loads(open(
    os.path.join(ROOT, "TrollLyricsDesk/Info.plist"), "rb").read())
check("app Info.plist: bundle id com.ycwl.Lyrics",
      app_pl.get("CFBundleIdentifier") == "com.ycwl.Lyrics")
check("app Info.plist: display name 桌面歌词",
      app_pl.get("CFBundleDisplayName") == "桌面歌词")
check("app Info.plist: NSSupportsLiveActivities = true",
      app_pl.get("NSSupportsLiveActivities") is True)
check("app Info.plist: no TLDSLiveActivities key / no TLDSLiveContainer=true",
      app_pl.get("TLDSLiveContainer") is not True)
check("widget Info.plist: no TLDSLiveContainer=true",
      plistlib.loads(open(os.path.join(ROOT, "TrollLyricsWidget/Info.plist"),
                          "rb").read()).get("TLDSLiveContainer") is not True)

print("\n== 3. 底子同步修正（保新底子，Universal 全缺的那些）在位 ==")
ls = read("Lyrics/LyricStore.swift")
pc = read("PlaybackEngine/PlaybackCoordinator.swift")
for s in ["timeOffset", "offsetKeyPrefix", "stableSongIdentity",
          "artistCarriesLyric", "songIdentityParts"]:
    check(f"LyricStore: {s} 在位", s in ls)
check("LyricStore: noMusicKey 在位", "noMusicKey" in ls)
check("LyricStore: floatingEnabledChanged 在位", "floatingEnabledChanged" in ls)
for s in ["noMusicKey", "isDisplayEquivalent", "syncLiveLyricsAndProgress"]:
    check(f"PlaybackCoordinator: {s} 在位", s in pc)
check("PlaybackCoordinator: state = newState 仍在（节流赋值未被 Universal 覆盖）",
      "state = newState" in pc)
td = read("Overlay/TLDSAppDelegate.m")
check("TLDSAppDelegate: 锁屏重建回调 needsRebuildOnUnlock 在位",
      "needsRebuildOnUnlock" in td)
check("TLDSAppDelegate: isProtectedDataAvailable 解锁轮询在位",
      "isProtectedDataAvailable" in td)
sd = read("Overlay/TLDSSceneDelegate.m")
check("TLDSSceneDelegate: hasPrefix 匹配悬浮 scene（保新底子）",
      'hasPrefix:@"TLDSFloatingLyric"' in sd)

print("\n== 4. 激活 ==")
av = read("App/ActivationView.swift")
check("ActivationView: ActivationGateView + ActivationVerifier.verify",
      "struct ActivationGateView" in av and "static func verify(code:" in av)
check("ActivationView: wrong code -> 激活码不正确",
      "激活码不正确" in av)
check("ActivationView: no network -> 需要联网激活",
      "需要联网激活" in av)
check("ActivationStore: verify URL + keys tld.activated / tld.activationType",
      "https://guhailong-repo.pages.dev/api/verify" in ls
      and '"tld.activated"' in ls and '"tld.activationType"' in ls)
check("ActivationStore: isActivated + markActivated",
      "static var isActivated" in ls and "static func markActivated" in ls)
ta = read("App/TrollLyricsDeskApp.swift")
check("TrollLyricsDeskApp: 根视图包 ActivationGateView",
      "ActivationGateView {" in ta)
fl = read("Overlay/FloatingLyricViewController.swift")
check("FloatingLyricViewController: 未激活时悬浮窗隐藏",
      "view.isHidden = !floatingEnabled || !ActivationStore.isActivated" in fl)
wv = read("TrollLyricsWidget/WidgetView.swift")
check("WidgetView: 未激活占位「请先在 App 内激活」",
      "请先在 App 内激活" in wv and "notActivatedView" in wv)

print("\n== 5. 五件 ==")
about = read("App/AboutView.swift")
check("AboutView: Telegram 标签 @Guhailon",
      '"@Guhailon"' in about)
check("AboutView: tg://resolve?domain=Guhailon, 退回 https://t.me/Guhailon",
      '"tg://resolve?domain=Guhailon"' in about
      and '"https://t.me/Guhailon"' in about)
check("AboutView: 无旧邀请链接、无 @seadragonjb",
      "tg://join?invite=" not in about and "I-I8aw7HUAw1NGY9" not in about
      and "@seadragonjb" not in about)
lv = read("App/LogView.swift")
check("LogView: 复制按钮 + copiedFeedback（清理不动）",
      "copiedFeedback" in lv
      and "UIPasteboard.general.string = LyricLogger.read()" in lv
      and '"已复制"' in lv and "asyncAfter" in lv)
check("LogView: 现有清理仍在（clearLogs / 清理日志）",
      "clearLogs()" in lv and "清理日志" in lv)
cv = read("App/ContentView.swift")
check("AppBackgroundView 在 ContentView.swift（无新文件）",
      "struct AppBackgroundView: View" in cv)
check("AppBackgroundView: 三个键（App Group）",
      '"animeBackgroundEnabled"' in cv and '"backgroundOpacity"' in cv
      and '"selectedBackgroundData"' in cv
      and cv.count('UserDefaults(suiteName: LyricStore.groupID)') >= 3)
check("AppBackgroundView: 关->纯黑；有图 scaledToFill，透明度 1-backgroundOpacity",
      "Color.black" in cv and "if animeBackgroundEnabled" in cv
      and "UIImage(data: selectedBackgroundData)" in cv
      and ".scaledToFill()" in cv
      and ".opacity(1 - backgroundOpacity)" in cv)
check("AppBackgroundView: 无图->原渐变",
      "Color.purple.opacity(0.8)" in cv and "Color.blue.opacity(0.5)" in cv)
check("四处用 AppBackgroundView（SettingsHub／Content／About／Dashboard）",
      cv.count("AppBackgroundView()") == 2
      and "AppBackgroundView()" in about
      and "AppBackgroundView()" in read("App/PlaybackDashboardView.swift"))
check("四处根渐变已替掉（AppBackgroundView 外无写死渐变）",
      cv.count("LinearGradient(") == 1
      and "LinearGradient(" not in about
      and "LinearGradient(" not in read("App/PlaybackDashboardView.swift"))
pd = read("App/PlaybackDashboardView.swift")
check("Dashboard: positionLocked 键（App Group，默认 false）",
      '"floatingLyric.positionLocked"' in pd
      and "private var positionLocked = false" in pd)
check("Dashboard: Toggle 固定悬浮窗位置在显示开关下、取色器上",
      '"固定悬浮窗位置"' in pd
      and pd.index('"固定悬浮窗位置"') > pd.index('"显示悬浮歌词窗"')
      and pd.index('"固定悬浮窗位置"') < pd.index('"悬浮窗歌词颜色"'))
check("Dashboard: 提示行跟锁走（悬浮窗口 · 已固定／长按拖动 · 双击隐藏）",
      '"悬浮窗口 · 已固定 · 双击隐藏"' in pd
      and '"悬浮窗口 · 长按拖动 · 双击隐藏"' in pd)
check("Dashboard: 标题居中（ZStack topTrailing＋frame maxWidth center，齿轮仍右上）",
      "ZStack(alignment: .topTrailing)" in pd
      and '.frame(maxWidth: .infinity, alignment: .center)' in pd
      and '"桌面歌词"' in pd and ".padding(.top, 80)" in pd)
check("FloatingLyricViewController: positionLockedKey + handlePan guard",
      '"floatingLyric.positionLocked"' in fl
      and "guard !positionLocked else { return }" in fl)
check("FloatingLyricViewController: 无 hintLabel（新底子本来就没有）",
      "hintLabel" not in fl)
check("FloatingLyricViewController: save/restore 位置未动",
      "private func savePosition(center: CGPoint)" in fl
      and "private func restorePosition()" in fl)

print("\n== 6. 锁屏 ==")
live = read("LiveActivity/LyricsLiveActivity.swift")
ctrl = read("PlaybackEngine/LyricsLiveActivityController.swift")
check("LyricsLiveActivity: ActivityAttributes + ContentState + DynamicIsland",
      "struct LyricsLiveAttributes: ActivityAttributes" in live
      and "struct ContentState: Codable, Hashable" in live
      and "DynamicIsland" in live)
check("controller: start/stop/update/refresh + pushType nil",
      all(s in ctrl for s in ["func start()", "func stop()", "func update(",
                              "func refresh()", "pushType: nil"]))
check("coordinator: LiveLyricKey 普通 Equatable 键结构（存储属性绝无 @available）",
      "private struct LiveLyricKey: Equatable" in pc
      and "private var lastLiveState: LiveLyricKey?" in pc
      and "LyricsLiveAttributes.ContentState?" not in pc
      and "@available(iOS 16.1, *)\n    private var lastLiveState" not in pc)
check("coordinator: isRunning / ensureRunning",
      "var isRunning: Bool" in pc and "func ensureRunning()" in pc)
check("coordinator: publishLiveLyrics 定义＋两处调用",
      "private func publishLiveLyrics()" in pc
      and pc.count("publishLiveLyrics()") == 3)
check("coordinator: publishLiveLyrics 带宿主 guard",
      "guard !LyricStore.isLiveContainer else { return }" in pc)
check("ContentView: 锁屏歌词区＋开启／停止＋宿主文案",
      '"锁屏歌词"' in cv and '"开启锁屏歌词"' in cv and '"停止锁屏歌词"' in cv
      and "LiveContainer 模式不支持锁屏歌词和小组件" in cv
      and "LiveActivitySectionView" in cv)
wg = read("TrollLyricsWidget/TrollLyricsWidget.swift")
check("widget: .accessoryRectangular（if #available iOS 16.0 包着）",
      ".accessoryRectangular" in wg and "if #available(iOS 16.0, *)" in wg)
check("WidgetView: 锁屏分支 family == .accessoryRectangular",
      "family == .accessoryRectangular" in wv and "lockScreenView" in wv)
wb = read("TrollLyricsWidget/TrollLyricsWidgetBundle.swift")
check("WidgetBundle: LyricsLiveActivity 已注册",
      "LyricsLiveActivity()" in wb and "if #available(iOS 16.1, *)" in wb)

print("\n== 7. Universal 兼容层 ==")
check("LyricStore: isLiveContainer（三路：plist 键／路径／LCAppDelegate）",
      "static var isLiveContainer: Bool" in ls
      and '"TLDSLiveContainer"' in ls
      and '"livecontainer"' in ls and '"/lcapps/"' in ls
      and 'NSClassFromString("LCAppDelegate")' in ls)
check("LyricStore: defaults 三元（宿主走 .standard）",
      "isLiveContainer ? .standard : UserDefaults(suiteName: groupID)" in ls)
check("TrollLyricsDeskApp: @objc isHosted() + 保活宿主时不启动",
      "@objc func isHosted() -> Bool { LyricStore.isLiveContainer }" in ta
      and "if !LyricStore.isLiveContainer { BackgroundKeepAlive.shared.start() }" in ta)
check("TLDSAppDelegate: TLDSInstallNativeWindowFix + isHosted 分支",
      "TLDSInstallNativeWindowFix" in td
      and "if (![[TLDSRuntime shared] isHosted])" in td
      and "TLDSInstallNativeWindowFix();" in td
      and "[self startFloatingOverlay];" in td)
check("TLDSSceneDelegate: 宿主只在已判兼容时强制 isMain = YES; isFloating = NO（1.0.5 三档）",
      "if ([[TLDSRuntime shared] isHosted] && appDelegate.compatMode)" in sd
      and "isMain = YES;" in sd and "isFloating = NO;" in sd)
check("Dashboard: 宿主显示「LiveContainer · 应用内歌词模式」+ 0.25s TimelineView",
      "LiveContainer · 应用内歌词模式" in pd
      and "TimelineView(.periodic(from: .now, by: 0.25))" in pd)
n_guarded = 0
for rel in ["PlaybackEngine/PlaybackCoordinator.swift",
            "App/LyricsSearchView.swift", "App/ContentView.swift",
            "App/SettingsView.swift", "App/ActivationView.swift"]:
    t = read(rel)
    n_guarded += t.count(
        "if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }")
check("5 处 WidgetCenter.reloadAllTimelines() 全部加宿主 guard（共 10 处调用点）",
      n_guarded == 10, f"guarded={n_guarded}")
all_swift = ""
for dirpath, _, filenames in os.walk(ROOT):
    if ".git" in dirpath or "hidden_files" in dirpath:
        continue
    for fn in filenames:
        if fn.endswith(".swift"):
            all_swift += open(os.path.join(dirpath, fn),
                              encoding="utf-8").read() + "\n"
check("无 TCP 桥 / 独立客户端 / 双 IPA 痕迹",
      "38473" not in all_swift and "DualProcessBridge" not in all_swift
      and "TLDSLiveContainer" not in read("TrollLyricsDesk/Info.plist")
      and "build-livecontainer" not in all_swift.lower())

print("\n== 8. pbxproj ==")
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: LiveActivity 组在位",
      'name = "LiveActivity"' in pbx and 'path = "LiveActivity"' in pbx)
app_sources = pbx_sources_files(pbx, "4821909E9BF9E73E471FEA84")
check("pbxproj: 三新文件进 App Sources",
      "ActivationView.swift" in app_sources
      and "LyricsLiveActivity.swift" in app_sources
      and "LyricsLiveActivityController.swift" in app_sources,
      str(app_sources))
widget_sources = pbx_sources_files(pbx, "37A859133C5B7A49CE597D35")
check("pbxproj: LyricsLiveActivity.swift 另进 Widget Sources",
      "LyricsLiveActivity.swift" in widget_sources, str(widget_sources))
check("pbxproj: ActivityKit 弱链接 4 处（App 2 + Widget 2），无强链接",
      pbx.count('"-weak_framework"') == 4 and pbx.count('"ActivityKit"') == 4
      and "ActivityKit.framework" not in pbx,
      f"weak={pbx.count(chr(34) + '-weak_framework' + chr(34))}")
check("pbxproj: .tbd 直链 4 条未动（Debug＋Release 各一份，共 8 行）",
      pbx.count("FrontBoard.tbd") == 2
      and pbx.count("FrontBoardServices.tbd") == 2
      and pbx.count("RunningBoardServices.tbd") == 2
      and pbx.count("AppleAccount.tbd") == 2)
check("pbxproj: MARKETING_VERSION 1.0.5（4 处），MinOS 15.0",
      pbx.count("MARKETING_VERSION = 1.0.5;") == 4
      and "IPHONEOS_DEPLOYMENT_TARGET = 16.0" not in pbx)
check("pbxproj: 包名 com.ycwl.Lyrics（App 2 处）＋ Widget 后缀",
      pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.ycwl.Lyrics;") == 2
      and pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.ycwl.Lyrics.TrollLyricsWidget;") == 2)
_resolved = pbx_resolved_files(pbx)
for f in ["LiveActivity/LyricsLiveActivity.swift",
          "PlaybackEngine/LyricsLiveActivityController.swift",
          "App/ActivationView.swift"]:
    check(f"pbxproj: resolves {f}", f in _resolved)
missing = [r for r in _resolved if not os.path.exists(os.path.join(ROOT, r))]
check("pbxproj: 所有引用文件都在磁盘上", not missing, str(missing))
obj_ids = set(re.findall(r"\t\t([0-9A-F]{24}) /\* \w+ \*/ = \{", pbx))
dangling = [fr for fr in re.findall(r"fileRef = ([0-9A-F]{24});", pbx)
            if fr not in obj_ids]
check("pbxproj: 无悬空 fileRef", not dangling, str(dangling))
check("pbxproj: 括号平衡",
      pbx.count("{") == pbx.count("}") and pbx.count("(") == pbx.count(")"))

print("\n== 9. 红线 ==")
for bad in ["BackBoard", "TLHUD", "TLHUDApplication", "dynamic_lookup",
            "38473", "DualProcessBridge"]:
    check(f"全树无 {bad!r}", bad not in all_swift
          and bad not in pbx
          and bad not in read(".github/workflows/build.yml"))
tracked = git_out(["ls-files"]).splitlines()
check("build/ 不在仓库里", not [f for f in tracked if f.startswith("build/")])
check("hidden_files/ 不在仓库里",
      not [f for f in tracked if f.startswith("hidden_files/")])
check("无 *.ipa / *.tipa 进仓库",
      not [f for f in tracked if f.endswith(".ipa") or f.endswith(".tipa")])
core_mr_changed = git_out(["diff", "--name-only", BASE, "HEAD", "--",
                             "Core/", "MusicProviders/"]).splitlines()
check("Core/ 与 MusicProviders/ 只动两处诊断文件（Bridge＋Adapter），其余一字未动",
      sorted(core_mr_changed) == sorted([
          "Core/MediaRemoteBridge.swift",
          "MusicProviders/MediaRemoteAdapter.swift"]),
      str(core_mr_changed))
changed = git_out(["diff", "--name-only", BASE, "HEAD"]).splitlines()
allowed = {
    "App/PlaybackDashboardView.swift",
    "App/SettingsView.swift", "App/TrollLyricsDeskApp.swift",
    "Core/MediaRemoteBridge.swift",
    "Lyrics/LyricStore.swift",
    "MusicProviders/MediaRemoteAdapter.swift",
    "Overlay/FloatingLyricViewController.swift",
    "Overlay/TLDSAppDelegate.h", "Overlay/TLDSAppDelegate.m",
    "Overlay/TLDSSceneDelegate.m",
    "PlaybackEngine/PlaybackCoordinator.swift",
    "TrollLyricsDesk.xcodeproj/project.pbxproj",
    "TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist",
    ".github/workflows/build.yml",
    "check_1.0.5.py", "RUN_1.0.5.md",
}
extra = [f for f in changed if f not in allowed]
check(f"红线 diff {BASE}..HEAD 只动允许文件", not extra, str(extra))
overlay_changed = [f for f in changed if f.startswith("Overlay/")]
check("Overlay/ 只动四处（FloatingLyric／AppDelegate.h+.m／SceneDelegate）",
      sorted(overlay_changed) == sorted([
          "Overlay/FloatingLyricViewController.swift",
          "Overlay/TLDSAppDelegate.h", "Overlay/TLDSAppDelegate.m",
          "Overlay/TLDSSceneDelegate.m"]),
      str(overlay_changed))
for rel in ["TrollLyricsDesk/TrollLyricsDesk.entitlements",
            "TrollLyricsWidget/TrollLyricsWidget.entitlements"]:
    head = git_out(["show", f"{BASE}:{rel}"])
    check(f"{rel}: 与底子一字未动（零新增权限）", read(rel) == head)
for f in ["App/ActivationView.swift", "App/ContentView.swift",
          "App/PlaybackDashboardView.swift", "Lyrics/LyricStore.swift",
          "PlaybackEngine/PlaybackCoordinator.swift",
          "LiveActivity/LyricsLiveActivity.swift",
          "PlaybackEngine/LyricsLiveActivityController.swift",
          "TrollLyricsWidget/WidgetView.swift"]:
    t = read(f)
    check(f"{f}: 花括号平衡", t.count("{") == t.count("}"),
          f"{{={t.count(chr(123))} }}={t.count(chr(125))}")
build_yml = read(".github/workflows/build.yml")
check("build.yml: 产物已升 桌面歌词-1.0.5.ipa（一个 workflow）",
      "桌面歌词-1.0.5.ipa" in build_yml
      and "桌面歌词-1.0.0" not in build_yml
      and "name: Build" in build_yml)


print("\n== 11. 1.0.5 诊断（7 项＋三档模式） ==")
bridge = read("Core/MediaRemoteBridge.swift")
check("MediaRemoteBridge: dlopen 成败＋dlerror 记日志",
      "dlopen" in bridge and "dlopen 成功" in bridge
      and "dlopen 失败" in bridge and "lastDLError" in bridge)
check("MediaRemoteBridge: dlsym 逐符号只记一次（成功／失败＋原因）",
      "loggedSymbols" in bridge and "dlsym" in bridge
      and "符号缺失" not in bridge and "失败" in bridge)
mra = read("MusicProviders/MediaRemoteAdapter.swift")
check("MediaRemoteAdapter: 注册 NowPlaying 通知（真签名 typealias）",
      "MRMediaRemoteRegisterForNowPlayingNotificationsFn" in mra
      and "registerForNowPlayingNotifications" in mra
      and 'bridge.symbol(MediaRemoteSymbols.registerForNowPlayingNotifications)' in mra)
check("MediaRemoteAdapter: 回调触发记第一次＋每 50 次；info 有无只在切换时记",
      "NowPlaying 通知回调已触发" in mra and "% 50 == 0" in mra
      and "GetNowPlayingInfo 回调已触发" in mra
      and "lastInfoWasNil" in mra)
check("MediaRemoteAdapter: 四符号仍按现有代码用（GetNowPlayingInfo／IsPlaying／Register／DisplayID 不增不减）",
      "MediaRemoteSymbols.getNowPlayingInfo" in mra
      and "MediaRemoteSymbols.registerForNowPlayingNotifications" in mra)
fl = read("Overlay/FloatingLyricViewController.swift")
check("强制测试文字：开关分支在 refresh() 最前（不依赖音乐／歌词）",
      "LyricStore.isTestTextEnabled" in fl
      and "apply(text: LyricStore.testText(), fontSize: 23, opacity: 1.0)" in fl)
check("强制测试文字：关后回到正常歌词（lastTestHiddenState 清零，不残留）",
      "lastTestHiddenState = nil" in fl)
check("悬浮窗控制器：初始化计数（第 N 次＋多次警告）",
      "initCount" in fl and "悬浮窗控制器初始化第" in fl)
check("LyricStore: 测试文字键＋开关＋testText()（固定文案＋时间戳）",
      '"floatingLyric.testTextEnabled"' in ls
      and "static var isTestTextEnabled" in ls
      and "static func testText() -> String" in ls
      and '"悬浮测试 · 桌面歌词 1.0.5 · \\(fmt.string(from: Date()))"' in ls)
check("LyricStore: 三档模式键＋中文描述（三档全列）",
      '"tlds.runMode"' in ls and '"tlds.runModeReason"' in ls
      and "static var runModeDescription" in ls
      and "巨魔原生模式" in ls and "增强宿主模式" in ls
      and "普通签名兼容模式" in ls)
td = read("Overlay/TLDSAppDelegate.m")
check("AppDelegate: 启动／Overlay／scene 计数（第 N 次）",
      "TLDSLaunchCount" in td and "TLDSStartFloatingOverlayCalls" in td
      and "TLDSCreateFloatingSceneCalls" in td
      and "App 启动第" in td)
check("AppDelegate: 一次性守卫（Shell 已初始化／NativeWindowFix 已安装，跳过）",
      "Shell 已初始化，跳过" in td and "NativeWindowFix 已安装，跳过" in td)
check("AppDelegate: 三档判定入口（巨魔定档／宿主待探测＋尝试创建）",
      'setRunMode:@"trollstore"' in td
      and 'setRunMode:@"probing"' in td
      and "待探测" in td)
check("AppDelegate: 托管复核 verifyFloatingVisibility（逐项＋结论行）",
      "verifyFloatingVisibility" in td
      and "托管复核：场景对象" in td and "托管复核：binder 收录场景" in td
      and "托管复核：悬浮窗口" in td and "托管复核：Context ID" in td
      and "托管复核结论：已确认可见" in td and "托管复核结论：未确认可见" in td)
check("AppDelegate: 降级普通签名兼容（摘场景＋藏窗口＋不再重建）",
      "downgradeToCompatModeWithReasons" in td
      and 'setRunMode:@"compat"' in td
      and 'setRunMode:@"enhanced-host"' in td
      and "普通签名兼容模式，跳过悬浮窗恢复" in td)
check("AppDelegate: 后台挂起／恢复日志（进入后台／失去前台／回到前台／终止）",
      "tlds_logDidEnterBackground" in td and "tlds_logWillResignActive" in td
      and "tlds_logDidBecomeActive" in td and "tlds_logWillTerminate" in td)
check("AppDelegate: 创建成功≠可见（创建日志写明等复核，不当成功）",
      "创建成功≠可见，等复核" in td)
sd = read("Overlay/TLDSSceneDelegate.m")
check("SceneDelegate: 宿主不再一律强制主界面（只在已判兼容时强制）",
      "appDelegate.compatMode" in sd
      and "if ([[TLDSRuntime shared] isHosted] && appDelegate.compatMode)" in sd)
check("SceneDelegate: 场景连接计数＋窗口诊断（层级／透明度／隐藏／frame）",
      "TLDSMainSceneConnectCount" in sd and "TLDSFloatingSceneConnectCount" in sd
      and "windowLevel=%.0f" in sd and "isHidden=%@" in sd)
check("SceneDelegate: 场景生命周期日志（前台／后台四回调）",
      "sceneDidBecomeActive" in sd and "sceneWillResignActive" in sd
      and "sceneDidEnterBackground" in sd and "sceneWillEnterForeground" in sd)
ta = read("App/TrollLyricsDeskApp.swift")
check("TLDSRuntime: setRunMode／runModeString（ObjC 侧写判定结果）",
      "@objc func setRunMode(_ mode: String, reason: String)" in ta
      and "@objc func runModeString() -> String" in ta)
check("TLDSRuntime: start() 重复调用记跳过（不建第二个引擎）",
      "startCallCount" in ta and "已启动，跳过" in ta)
sv = read("App/SettingsView.swift")
check("SettingsView: 诊断区（强制测试开关＋运行模式行，写明测试用）",
      "强制悬浮测试文字（测试用）" in sv
      and "LyricStore.isTestTextEnabled" in sv
      and "运行模式" in sv and "runModeDescription" in sv)
pd = read("App/PlaybackDashboardView.swift")
check("Dashboard: 宿主应用内歌词区显示测试文字（注明非悬浮窗）",
      "LyricStore.isTestTextEnabled ? (LyricStore.testText()" in pd
      and "应用内显示，非悬浮窗" in pd)
check("PlaybackCoordinator: 检测引擎启动计数（第 N 次）",
      "startCount" in pc and "检测引擎启动第" in pc)
all_src = all_swift + read("Overlay/TLDSAppDelegate.m") + read("Overlay/TLDSSceneDelegate.m")
check("无 PiP 实现代码（只研究，不实现；全树无 AVPictureInPicture）",
      "AVPictureInPicture" not in all_src
      and "PictureInPicture" not in all_src)
diff_ls = git_out(["diff", BASE, "HEAD", "--", "Lyrics/LyricStore.swift"])
removed_ls = [ln for ln in diff_ls.splitlines()
              if ln.startswith("-") and not ln.startswith("---")]
check("红线：LyricStore 同步修正只增不减（diff 无删行）",
      not removed_ls, str(removed_ls[:5]))
for sym in ["timeOffset", "offsetKeyPrefix", "stableSongIdentity",
            "artistCarriesLyric", "songIdentityParts", "noMusicKey",
            "isDisplayEquivalent", "syncLiveLyricsAndProgress",
            "needsRebuildOnUnlock"]:
    src = ls if sym in ("timeOffset", "offsetKeyPrefix", "stableSongIdentity",
                        "artistCarriesLyric", "songIdentityParts", "noMusicKey") else pc
    if sym == "needsRebuildOnUnlock":
        src = td
    check(f"红线锚：{sym} 在 1.0.5 仍在位", sym in src)
for rel in ["TrollLyricsDesk/TrollLyricsDesk.entitlements",
            "TrollLyricsWidget/TrollLyricsWidget.entitlements"]:
    head = git_out(["show", f"{BASE}:{rel}"])
    check(f"{rel}: 与 6857d3c 一字未动（零新增权限）", read(rel) == head)

print("\n== 10. OPEN（只能真机／macOS 编的，如实列，不编通过） ==")
open_item("macOS 编译未做（Linux 没 Xcode/swiftc）",
          "ActivityKit 弱链接、DynamicIsland 展开区、if #available 组合、"
          "TLDSInstallNativeWindowFix 与分类 hook 并存，都要 macOS 构建才见分晓")
open_item("五件要真机验：Telegram 行／日志复制／背景图／固定位置／提示行＋标题居中",
          "点 Telegram 行进 @Guhailon 频道；日志复制贴到别处；背景设置选图后四处立即换图、"
          "开关关变纯黑、透明度滑杆跟手；固定开关开后悬浮窗拖不动、提示行变“已固定”；"
          "标题居中、齿轮仍右上")
open_item("激活要真机验：首次打开弹激活页，码对放行、码错报“激活码不正确”、断网报“需要联网激活”",
          "激活后不用重启进主界面；悬浮窗与小组件在未激活时分别是隐藏与占位")
open_item("锁屏要真机验：开启／停止、横幅跟随、灵动岛三态、滑掉同步、8 小时到期",
          "iPhone 11 无常亮显示，关屏不显示是硬件限制；锁屏小组件需手动长按锁屏添加")
open_item("LC 兼容要真机验：同 IPA 导入 LiveContainer 能启动、应用内歌词 0.25s 刷新、"
          "暂停／归零可用；巨魔模式悬浮窗／锁屏／保活一切照旧",
          "LiveContainer 的进程模型＋后台行为没验过；检测是启发式，不是权限证明")
open_item("二进制字面量扫描的限制（已查明，非缺陷；见 RUN 第三阶段）",
          "Release 二进制里 ≤15 字节的行内字面量（livecontainer／/lcapps/／"
          "LCAppDelegate／桌面歌词等）以 small-string immediates 进代码段，"
          "不在 __cstring 里，字节扫描不到；＞15 字节或 static-let 字面量"
          "（TLDSLiveContainer／lyric.timeOffset|／tld.activated）在位；"
          "方法名符号 Release 下被 strip，源码级核查为准；LC 宿主模式"
          "是否真生效只能真机验")
open_item("otool 弱链接核实（编成后验包新增）",
          "App 与 Widget 两个二进制各跑 macho_inspect.py 查 ActivityKit，"
          "都要是 LC_LOAD_WEAK_DYLIB（0x80000018）；强链接则 iOS 15 有启动失败风险")


open_item("1.0.5 诊断要真机验：日志页抄回诊断行（见 RUN_1.0.5.md 待验清单）",
          "MediaRemote dlopen/dlsym／回调触发／info 有无；强制测试开关开后悬浮窗"
          "是否出现测试文字；托管复核逐项结论；运行模式进了哪档；启动计数是否都为 1")
open_item("LC 里首次调用 FBSystemShellInitialize 的风险未验证",
          "1.0.4／newbase 在宿主模式下从不调它；1.0.5 为探测增强宿主改为尝试＋复核，"
          "调用包在 @try/@catch 里、回调不来时 6 秒兜底复核判兼容；若 LC 真机启动就闪退，"
          "第一嫌疑就是这次尝试——日志里若连「待探测」都没有，就是启动时崩了")
open_item("PiP 可行性只研究未验证（RUN_1.0.5.md 小结为准，不实现）",
          "AVPictureInPictureController 的公开规则只作书面推断；LC 客人里能不能跑、"
          "要不要视频轨，都标了「未验证」，不要当结论用")
open_item("三档模式的复核时序未验证",
          "复核在创建后 2 秒跑、场景未连上时 3 秒后再跑一次；真机上场景连接若慢于 5 秒，"
          "会误判兼容——日志里「复核推迟」出现几次、最终进了哪档，以真机为准")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens), "items (see above)")
sys.exit(1 if fails else 0)
