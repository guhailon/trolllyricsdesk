#!/usr/bin/env python3
"""Verify TrollLyricsDesk 1.0.3 (1.0.2 + server-verified activation):
1.0.3 = 1.0.2 只加授权激活——整个 App 第一次打开就要码，POST
https://guhailong-repo.pages.dev/api/verify 服务端验证（码先 trim 再大写）；
验过写 App Group 标记 tld.activated=true、tld.activationType=master/code，
以后直接进主界面。未激活：主界面全屏激活页、悬浮窗隐藏、小组件占位
「请先在 App 内激活」。码表只在服务端，App 源码与仓库里没有任何码值；
锁屏（A Live Activities + B 锁屏小组件）一字未动，MinOS 15.0 不动。
红线锚点是固定基点 7e39edf（1.0.2 末提交），提交后再重跑才算数。

FAILED: none is the goal. OPEN items are recorded, not failures:
things that cannot be verified on Linux (macOS compile, device) or that
need Lee's device test (PLAN §7/§8).
"""
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
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


def git_head(rel):
    return subprocess.check_output(
        ["git", "show", f"HEAD:{rel}"],
        cwd=ROOT, text=True)


def pbx_resolved_files(pbx_text):
    # Same group-tree resolver as check_1.0.3.py (file ref path =
    # parent group path + ref path; the old doubled-path assumption was wrong).
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
            # Overlay 组用的是不带引号的 path = Overlay;（Lee 本地树的写法），
            # 上面的正则要同时吃带引号和不带引号两种，否则组内文件会解析成裸文件名。
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


def pbx_sources_files(pbx_text, phase_id):
    # Resolve a PBXSourcesBuildPhase's BuildFile ids to file paths
    # (Target Membership check: which target actually compiles a file).
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


print("== 1. 新文件 ==")
for rel in ["LiveActivity/LyricsLiveActivity.swift",
            "PlaybackEngine/LyricsLiveActivityController.swift"]:
    check(f"exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))

print("\n== 2. 版本 / MinOS ==")
for rel in ["TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist"]:
    pl = plistlib.loads(open(os.path.join(ROOT, rel), "rb").read())
    check(f"{rel}: version 1.0.3", pl.get("CFBundleShortVersionString") == "1.0.3",
          str(pl.get("CFBundleShortVersionString")))
    check(f"{rel}: build 16", pl.get("CFBundleVersion") == "16",
          str(pl.get("CFBundleVersion")))
    check(f"{rel}: min OS 15.0", pl.get("MinimumOSVersion") == "15.0",
          str(pl.get("MinimumOSVersion")))
app_pl = plistlib.loads(open(
    os.path.join(ROOT, "TrollLyricsDesk/Info.plist"), "rb").read())
check("app Info.plist: NSSupportsLiveActivities = true",
      app_pl.get("NSSupportsLiveActivities") is True)
check("app Info.plist: bundle id still Desk2",
      app_pl.get("CFBundleIdentifier") == "com.hailong.TrollLyricsDesk2")

print("\n== 3. 路子 A：Live Activities ==")
live = read("LiveActivity/LyricsLiveActivity.swift")
ctrl = read("PlaybackEngine/LyricsLiveActivityController.swift")
check("LyricsLiveActivity.swift: @available(iOS 16.1, *)",
      "@available(iOS 16.1, *)" in live)
check("LyricsLiveActivity.swift: ActivityAttributes + ContentState",
      "struct LyricsLiveAttributes: ActivityAttributes" in live
      and "struct ContentState: Codable, Hashable" in live)
check("LyricsLiveActivity.swift: lockScreen + DynamicIsland",
      "ActivityConfiguration(for: LyricsLiveAttributes.self)" in live
      and "DynamicIsland" in live)
check("LyricsLiveActivity.swift: expanded/compact/minimal",
      all(s in live for s in ["DynamicIslandExpandedRegion(.leading)",
                              "DynamicIslandExpandedRegion(.trailing)",
                              "DynamicIslandExpandedRegion(.center)",
                              "DynamicIslandExpandedRegion(.bottom)",
                              "compactLeading", "compactTrailing", "minimal"]))
check("LyricsLiveActivity.swift: shared 3-line view (lock screen + island)",
      "struct LyricsLiveLinesView: View" in live
      and "LyricsLiveLockScreenView(state: context.state)" in live)
check("LyricsLiveActivity.swift: lyric color from hex (取色器复用）",
      "lyricColorHex" in live and "init(hex: Int)" in live)
check("LyricsLiveActivity.swift: compact truncation (ChatGPT 问题 4)",
      ".font(.caption2)" in live and ".truncationMode(.tail)" in live
      and ".minimumScaleFactor(0.8)" in live)
check("LyricsLiveActivity.swift: no stray separator when artist empty + pause hint",
      "state.artist.isEmpty ? state.title" in live
      and "已暂停" in live)
check("controller: @available(iOS 16.1, *)",
      "@available(iOS 16.1, *)" in ctrl)
check("controller: singleton + @Published isActive/statusMessage",
      "static let shared = LyricsLiveActivityController()" in ctrl
      and "@Published private(set) var isActive" in ctrl
      and "@Published private(set) var statusMessage" in ctrl)
check("controller: start/stop/update/refresh",
      all(s in ctrl for s in ["func start()", "func stop()", "func update(",
                              "func refresh()"]))
check("controller: Activity.request local only (pushType nil)",
      "Activity.request(" in ctrl and "pushType: nil" in ctrl)
check("controller: end dismissalPolicy .immediate",
      "dismissalPolicy: .immediate" in ctrl)
check("controller: observes activity end (sync switch state)",
      "activityStateUpdates" in ctrl and ".ended" in ctrl and ".dismissed" in ctrl)
check("controller: checks areActivitiesEnabled",
      "ActivityAuthorizationInfo().areActivitiesEnabled" in ctrl)
check("controller: lyric color reads floatingLyric.textColorHex (default white)",
      '"floatingLyric.textColorHex"' in ctrl and "0xFFFFFF" in ctrl)
check("controller: 16.2 branches (request/update/end) + 16.1 fallback (ChatGPT 问题 2)",
      ctrl.count("if #available(iOS 16.2, *)") == 3
      and "contentState: placeholderState()" in ctrl
      and "await current.update(using:" in ctrl
      and "await current.end(" in ctrl and "using: placeholderState()" in ctrl,
      f"16.2-branches={ctrl.count('if #available(iOS 16.2, *)')}")
check("controller: update serial coalescing queue (BUG-06)",
      "pendingUpdate" in ctrl and "updateTask" in ctrl
      and "while let pending = self.pendingUpdate" in ctrl)
check("controller: Activity id check before update/end-clear (BUG-06/问题 B)",
      "activityID" in ctrl and "self.activity?.id == id" in ctrl)
check("controller: observeEnd stored as observationTask + refresh re-binds (问题 A/B)",
      "observationTask" in ctrl and "observationTask?.cancel()" in ctrl
      and "observeEnd()" in ctrl)
check("controller: stop waits for end() before clearing state (问题 C)",
      "isBusy" in ctrl and "isBusy = true" in ctrl and "isBusy = false" in ctrl)

pc = read("PlaybackEngine/PlaybackCoordinator.swift")
check("coordinator: state = newState still present (no 1.0.6 regression)",
      "state = newState" in pc)
check("coordinator: publishLiveLyrics defined",
      "private func publishLiveLyrics()" in pc)
check("coordinator: publishLiveLyrics called at end of poll() + track-change branch",
      pc.count("publishLiveLyrics()") == 3,  # 1 def + 2 call sites
      f"count={pc.count('publishLiveLyrics()')}")
check("coordinator: full-state dedup (BUG-02/04) + Activity id (BUG-01 第二层）",
      "lastLiveState" in pc and "lastLiveActivityID" in pc
      and "lastLiveLyricIndex" not in pc and "lastLiveTrackKey" not in pc
      and "key == lastLiveState" in pc
      and "activityID != lastLiveActivityID" in pc)
check("coordinator: isActive guard resets dedup when Live Activity off (BUG-01 第一层）",
      "guard LyricsLiveActivityController.shared.isActive else" in pc
      and "lastLiveState = nil" in pc)
check("coordinator: prelude shows ♪ {title} + first line as next (BUG-03)",
      '"♪ \\(snapshot.title)"' in pc
      and "next = snapshot.lyrics.first?.text ?? \"\"" in pc)
check("coordinator: content length cap 120 (P2 超长歌词）",
      "clipped(" in pc and "text.count > 120" in pc)
check("coordinator: ensureRunning() idempotent, no direct start() from lock screen",
      "func ensureRunning()" in pc and "var isRunning: Bool" in pc)
check("coordinator: lastLiveState is a plain Equatable key struct, NOT a stored ContentState (run 45737184426 fix)",
      "private struct LiveLyricKey: Equatable" in pc
      and "private var lastLiveState: LiveLyricKey?" in pc
      and "LyricsLiveAttributes.ContentState?" not in pc
      and "@available(iOS 16.1, *)\n    private var lastLiveState" not in pc)
check("coordinator: staleDate = next line + 5s",
      "addingTimeInterval(nextIn + 5)" in pc)
check("coordinator: call sites guarded by if #available(iOS 16.1, *)",
      "if #available(iOS 16.1, *)" in pc)
check("coordinator: poll() detection logic untouched (no-state branch still returns early)",
      'message = "没有检测到可读取的音乐"' in pc)

cv = read("App/ContentView.swift")
check("ContentView: 锁屏歌词 section",
      '"锁屏歌词"' in cv)
check("ContentView: start/stop buttons + status text",
      '"开启锁屏歌词"' in cv and '"停止锁屏歌词"' in cv
      and "liveActivity.statusMessage" in cv)
check("ContentView: LiveActivitySectionView @available(iOS 16.1, *)",
      "struct LiveActivitySectionView: View" in cv
      and "@available(iOS 16.1, *)" in cv)
check("ContentView: iOS <16.1 hint line",
      '"锁屏歌词需要 iOS 16.1 或以上"' in cv)
check("ContentView: lock-screen widget add hint (B)",
      "长按锁屏 → 自定 → 添加小组件" in cv)
check("ContentView: existing sections untouched (音乐检测／歌词透明度／悬浮窗透明度）",
      '"音乐检测"' in cv and '"歌词透明度"' in cv and '"悬浮窗透明度"' in cv)
check("ContentView: lock-screen start ensures engine running (审查第 7 项）",
      "coordinator.ensureRunning()" in cv
      and "liveActivity.start()" in cv)
check("ContentView: refresh() on appear (前台恢复时同步开关状态）",
      "liveActivity.refresh()" in cv)

print("\n== 4. 路子 B：锁屏小组件 ==")
wg = read("TrollLyricsWidget/TrollLyricsWidget.swift")
check("widget: .accessoryRectangular in supportedFamilies",
      ".accessoryRectangular" in wg)
check("widget: .accessoryRectangular guarded by if #available(iOS 16.0, *)",
      "if #available(iOS 16.0, *)" in wg)
check("widget: systemSmall/systemMedium still present",
      ".systemSmall" in wg and ".systemMedium" in wg)
check("widget: getTimeline untouched (pre-scheduled per-line entries)",
      "预先安排后续歌词" in wg)
wv = read("TrollLyricsWidget/WidgetView.swift")
check("WidgetView: lock-screen branch uses @Environment widgetFamily (ChatGPT fix)",
      "@Environment(\\.widgetFamily)" in wv
      and "family == .accessoryRectangular" in wv)
check("WidgetView: no undefined 'context' (ChatGPT: cannot find 'context' in scope)",
      "context.family" not in wv)
check("WidgetView: lock-screen view (title + current + next)",
      "lockScreenView" in wv and "桌面歌词 · " in wv)
check("WidgetView: main-screen layout kept (moved verbatim to mainScreenView)",
      "mainScreenView" in wv and "打开 App 加载歌词" in wv
      and '"等待歌词..."' in wv and "LyricStore.currentLyric(" in wv)
wb = read("TrollLyricsWidget/TrollLyricsWidgetBundle.swift")
check("WidgetBundle: LyricsLiveActivity registered (ChatGPT 问题 3，接线遗漏）",
      "LyricsLiveActivity()" in wb
      and "if #available(iOS 16.1, *)" in wb)

print("\n== 5. pbxproj ==")
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: LiveActivity group present",
      'name = "LiveActivity"' in pbx and 'path = "LiveActivity"' in pbx)
check("pbxproj: both new files in App Sources phase",
      "LyricsLiveActivity.swift in Sources" in pbx
      and "LyricsLiveActivityController.swift in Sources" in pbx)
_widget_sources = pbx_sources_files(pbx, "37A859133C5B7A49CE597D35")
check("pbxproj: LyricsLiveActivity.swift in Widget Extension Sources (Target Membership)",
      "LyricsLiveActivity.swift" in _widget_sources,
      str(_widget_sources))
check("pbxproj: ActivityKit weak-linked (4x: App 2 + Widget 2)",
      pbx.count('"-weak_framework"') == 4 and pbx.count('"ActivityKit"') == 4,
      f"weak={pbx.count(chr(34) + '-weak_framework' + chr(34))}")
check("pbxproj: no strong ActivityKit link phase entry",
      "ActivityKit.framework" not in pbx)
check("pbxproj: MinOS still 15.0 everywhere",
      "IPHONEOS_DEPLOYMENT_TARGET = 15.0" in pbx
      and "IPHONEOS_DEPLOYMENT_TARGET = 16.0" not in pbx)
check("pbxproj: MARKETING_VERSION 1.0.3 (4x)",
      pbx.count("MARKETING_VERSION = 1.0.3;") == 4
      and "MARKETING_VERSION = 1.0.2" not in pbx)
_resolved = pbx_resolved_files(pbx)
for f in ["LiveActivity/LyricsLiveActivity.swift",
          "PlaybackEngine/LyricsLiveActivityController.swift",
          "App/ActivationView.swift"]:
    check(f"pbxproj: resolves {f}", f in _resolved)
_app_sources = pbx_sources_files(pbx, "4821909E9BF9E73E471FEA84")
check("pbxproj: ActivationView.swift in App Sources (Target Membership)",
      "ActivationView.swift" in _app_sources,
      str(_app_sources))
missing = [r for r in _resolved if not os.path.exists(os.path.join(ROOT, r))]
check("pbxproj: all referenced files exist on disk", not missing, str(missing))
obj_ids = set(re.findall(r"\t\t([0-9A-F]{24}) /\* \w+ \*/ = \{", pbx))
dangling = [fr for fr in re.findall(r"fileRef = ([0-9A-F]{24});", pbx)
            if fr not in obj_ids]
check("pbxproj: no dangling fileRefs", not dangling, str(dangling))
check("pbxproj: braces/parens balanced",
      pbx.count("{") == pbx.count("}") and pbx.count("(") == pbx.count(")"))

print("\n== 6. 红线 ==")
# 红线锚点是固定基点 7e39edf（1.0.2 末提交）：不要用 `git diff HEAD`
# （提交后工作区干净，diff 永远是空），也不要用 HEAD~1（每多一个提交就漂走）。
# 1.0.3 只许四处改动：Overlay/ 只动 FloatingLyricViewController.swift 一处
# （applyVisibility 加激活判断）；锁屏文件一字未动；其余改动在 App/、
# Lyrics/LyricStore.swift（只加 ActivationStore）、WidgetView.swift（只加占位门）。
# 以下 diff 一律用 `git diff 7e39edf HEAD -- <路径>`，提交后再重跑才算数。
def diff_names(rel):
    out = subprocess.check_output(
        ["git", "diff", "--name-only", "7e39edf", "HEAD", "--", rel],
        cwd=ROOT, text=True).strip().splitlines()
    return [f for f in out if f.strip()]

def diff_text(rel):
    return subprocess.check_output(
        ["git", "diff", "7e39edf", "HEAD", "--", rel],
        cwd=ROOT, text=True)

diff_overlay_files = diff_names("Overlay/")
check("Overlay/: only FloatingLyricViewController.swift changed (activation gate)",
      diff_overlay_files == ["Overlay/FloatingLyricViewController.swift"],
      str(diff_overlay_files))
diff_fl = diff_text("Overlay/FloatingLyricViewController.swift")
check("Overlay diff: only applyVisibility activation gate (no scene/entry changes)",
      "ActivationStore.isActivated" in diff_fl
      and "applyVisibility" in diff_fl
      and "registerWindowWithContextID" not in diff_fl
      and "FBSystemShellInitialize" not in diff_fl
      and "positionLocked" not in [ln for ln in diff_fl.splitlines() if ln.startswith("+")])
for rel in ["LiveActivity/LyricsLiveActivity.swift",
            "PlaybackEngine/LyricsLiveActivityController.swift",
            "PlaybackEngine/PlaybackCoordinator.swift",
            "TrollLyricsWidget/TrollLyricsWidget.swift",
            "TrollLyricsWidget/TrollLyricsWidgetBundle.swift"]:
    check(f"{rel}: unchanged vs 7e39edf (lockscreen untouched)",
          diff_names(rel) == [], str(diff_names(rel)))
diff_app_files = diff_names("App/")
check("App/: only ActivationView.swift (new) + TrollLyricsDeskApp.swift (gate)",
      sorted(diff_app_files) == ["App/ActivationView.swift",
                                 "App/TrollLyricsDeskApp.swift"],
      str(diff_app_files))
diff_wv = diff_text("TrollLyricsWidget/WidgetView.swift")
check("WidgetView diff: only activation placeholder gate (lockscreen branches intact)",
      "请先在 App 内激活" in diff_wv
      and "notActivatedView" in diff_wv
      and "lockScreenView" in diff_wv
      and "mainScreenView" in diff_wv)
diff_ls = diff_text("Lyrics/LyricStore.swift")
added_ls = [ln for ln in diff_ls.splitlines()
            if ln.startswith("+") and not ln.startswith("+++")]
removed_ls = [ln for ln in diff_ls.splitlines()
              if ln.startswith("-") and not ln.startswith("---")]
check("LyricStore diff: pure addition, only ActivationStore appended",
      not removed_ls
      and "enum ActivationStore" in diff_ls
      and "verifyURLString" in diff_ls
      and "tld.activated" in diff_ls
      and "markActivated" in diff_ls,
      f"added={len(added_ls)} removed={len(removed_ls)}")
for rel in ["TrollLyricsDesk/TrollLyricsDesk.entitlements",
            "TrollLyricsWidget/TrollLyricsWidget.entitlements"]:
    head = git_head(rel)
    check(f"{rel}: unchanged vs HEAD (zero new entitlements)",
          read(rel) == head)
all_swift = ""
for dirpath, _, filenames in os.walk(ROOT):
    if ".git" in dirpath or "hidden_files" in dirpath:
        continue
    for fn in filenames:
        if fn.endswith(".swift"):
            all_swift += open(os.path.join(dirpath, fn),
                              encoding="utf-8").read() + "\n"
for bad in ["BackBoard", "TLHUD", "TLHUDApplication", "TLHUDWindow",
            "registerWindowWithContextID", "SBSAccessibilityWindowHostingController",
            "TLLyricsIPC", "LyricWord", "LyricSyncEngine"]:
    check(f"no BackBoard/逐字 string {bad!r}", bad not in all_swift)
for f in ["LiveActivity/LyricsLiveActivity.swift",
          "PlaybackEngine/LyricsLiveActivityController.swift",
          "PlaybackEngine/PlaybackCoordinator.swift",
          "App/ContentView.swift",
          "App/ActivationView.swift",
          "Lyrics/LyricStore.swift",
          "TrollLyricsWidget/TrollLyricsWidget.swift",
          "TrollLyricsWidget/WidgetView.swift"]:
    t = read(f)
    check(f"{f}: braces balanced", t.count("{") == t.count("}"),
          f"{{={t.count(chr(123))} }}={t.count(chr(125))}")
    check(f"{f}: parens balanced", t.count("(") == t.count(")"),
          f"(={t.count(chr(40))} )={t.count(chr(41))}")

print("\n== 6.5 否定检查（1.0.1：Engine V2 与 1.0.6 改进一律未并） ==")
check("no Engine V2 files (Tests/, ENGINE_V2.md)",
      not os.path.exists(os.path.join(ROOT, "Tests"))
      and not os.path.exists(os.path.join(ROOT, "ENGINE_V2.md")))
check("no Engine V2 strings in coordinator (generation/freezeSnapshot/0.8s re-anchor)",
      "generation" not in pc and "freezeSnapshot" not in pc
      and "missingSince" not in pc and "nextPoll" not in pc)
for rel in ["MusicProviders/MediaRemoteAdapter.swift",
            "PlaybackEngine/LyricMatcher.swift"]:
    d = subprocess.check_output(
        ["git", "diff", "--stat", "7e39edf", "HEAD", "--", rel], cwd=ROOT, text=True)
    check(f"{rel}: unchanged vs 7e39edf (no Engine V2)", d.strip() == "", d.strip())
check("no 1.0.6 playback improvements in coordinator (idle-saving poll tiers)",
      "pollInterval" not in pc and "scheduleTimer" not in pc
      and "activePollInterval" not in pc)
check("no 1.0.6 keep-alive switch in ContentView (2288444 的开关未并）",
      "keepAlive" not in cv.lower() and "保活开关" not in cv)
check("no BackBoard/-hud/dynamic_lookup anywhere (pbxproj + swift)",
      "dynamic_lookup" not in pbx
      and "-hud" not in all_swift and "TLHUDApplication" not in all_swift
      and "TLLyricsIPC" not in all_swift and "BackBoard" not in all_swift)
check("build number is 16 (1.0.3, not 1.0.2 build 15)",
      app_pl.get("CFBundleVersion") == "16")
build_yml = read(".github/workflows/build.yml")
check("build.yml: product name 桌面歌词-1.0.3.ipa",
      "桌面歌词-1.0.3.ipa" in build_yml and "桌面歌词-1.0.2.ipa" not in build_yml
      and "1.0.4" not in build_yml)


print("\n== 6.6 1.0.2：Telegram 公开频道＋日志清除／复制 ==")
about = read("App/AboutView.swift")
check("AboutView: Telegram label is @Guhailon",
      '"@Guhailon"' in about)
check("AboutView: Telegram opens tg://resolve?domain=Guhailon, falls back to https://t.me/Guhailon",
      '"tg://resolve?domain=Guhailon"' in about
      and '"https://t.me/Guhailon"' in about)
check("AboutView: no old invite link, no @seadragonjb",
      "tg://join?invite=" not in about and "I-I8aw7HUAw1NGY9" not in about
      and "@seadragonjb" not in about)
logger = read("TrollLyricsDesk/LyricLogger.swift")
check("LyricLogger: clear() deletes the log file",
      "static func clear()" in logger and "removeItem" in logger)
check("LyricLogger: read() still returns empty after clear (maxBytes/trim untouched)",
      "maxBytes = 200 * 1024" in logger and "trimIfNeeded" in logger)
lv = read("App/LogView.swift")
check("LogView: copy button copies full log via UIPasteboard",
      "UIPasteboard.general.string = LyricLogger.read()" in lv
      and '"doc.on.doc"' in lv)
check("LogView: copy feedback shows 已复制 then restores (~1.5s)",
      '"已复制"' in lv and "asyncAfter" in lv)
check("LogView: clear button asks for confirmation then clears",
      '"确定要清除全部日志吗？"' in lv and "role: .destructive" in lv
      and "LyricLogger.clear()" in lv and "entries = []" in lv)
check("LogView: share button kept as-is",
      '"分享"' in lv and "ShareLink(item: shareText)" in lv)
check("LogView: copy/clear/share disabled when log is empty",
      lv.count(".disabled(entries.isEmpty)") == 3,
      f"count={lv.count('.disabled(entries.isEmpty)')}")

print("\n== 6.7 1.0.2：背景图任意更换 ==")
cv = read("App/ContentView.swift")
check("AppBackgroundView exists in ContentView.swift (no new file)",
      "struct AppBackgroundView: View" in cv)
check("AppBackgroundView reads all three background keys from the App Group",
      '"animeBackgroundEnabled"' in cv and '"backgroundOpacity"' in cv
      and '"selectedBackgroundData"' in cv
      and cv.count('UserDefaults(suiteName: LyricStore.groupID)') >= 3)
check("AppBackgroundView: switch off -> pure black, no image/gradient",
      "Color.black" in cv and "if animeBackgroundEnabled" in cv)
check("AppBackgroundView: custom image fullscreen, opacity = 1 - backgroundOpacity",
      "UIImage(data: selectedBackgroundData)" in cv
      and ".scaledToFill()" in cv
      and ".opacity(1 - backgroundOpacity)" in cv)
check("AppBackgroundView: no custom image -> original gradient, same opacity",
      "Color.purple.opacity(0.8)" in cv and "Color.blue.opacity(0.5)" in cv)
check("SettingsHubView / ContentView / AboutView / PlaybackDashboardView use AppBackgroundView",
      cv.count("AppBackgroundView()") == 2
      and "AppBackgroundView()" in read("App/AboutView.swift")
      and "AppBackgroundView()" in read("App/PlaybackDashboardView.swift"))
check("No hardcoded root gradient left outside AppBackgroundView",
      cv.count("LinearGradient(") == 1
      and "LinearGradient(" not in read("App/AboutView.swift")
      and "LinearGradient(" not in read("App/PlaybackDashboardView.swift"))
check("Version is 1.0.3 / build 16 (1.0.3 bumped version)",
      read("TrollLyricsDesk/Info.plist").count("<string>1.0.3</string>") == 1
      and read("TrollLyricsDesk/Info.plist").count("<string>16</string>") == 1)

print("\n== 6.8 1.0.2：悬浮窗固定位置开关 ==")
pd = read("App/PlaybackDashboardView.swift")
check("PlaybackDashboardView: positionLocked key (App Group, default false)",
      '"floatingLyric.positionLocked"' in pd
      and "private var positionLocked = false" in pd
      and pd.count('UserDefaults(suiteName: LyricStore.groupID)') >= 3)
check("PlaybackDashboardView: Toggle 固定悬浮窗位置 in the floating-lyric area",
      '"固定悬浮窗位置"' in pd
      and pd.index('"固定悬浮窗位置"') > pd.index('"显示悬浮歌词窗"')
      and pd.index('"固定悬浮窗位置"') < pd.index('"悬浮窗歌词颜色"'))
fl = read("Overlay/FloatingLyricViewController.swift")
check("FloatingLyricViewController: positionLockedKey + Bool read (default false)",
      '"floatingLyric.positionLocked"' in fl
      and "private let positionLockedKey" in fl
      and "prefs?.bool(forKey: positionLockedKey) ?? false" in fl)
check("FloatingLyricViewController: handlePan returns early when locked",
      "guard !positionLocked else { return }" in fl
      and fl.index("guard !positionLocked else { return }")
      < fl.index("let translation = gesture.translation"))
check("FloatingLyricViewController: save/restore position untouched",
      "private func savePosition(center: CGPoint)" in fl
      and "private func restorePosition()" in fl
      and '"floatingLyric.posX"' in fl and '"floatingLyric.posY"' in fl)
check("PlaybackDashboardView: hint text follows the lock (moved from Overlay)",
      '"悬浮窗口 · 已固定 · 双击隐藏"' in pd
      and '"悬浮窗口 · 长按拖动 · 双击隐藏"' in pd)
check("Version is 1.0.3 / build 16 (1.0.3 bumped version)",
      read("TrollLyricsDesk/Info.plist").count("<string>1.0.3</string>") == 1
      and read("TrollLyricsDesk/Info.plist").count("<string>16</string>") == 1)

print("\n== 6.9 1.0.2：提示文字移到界面＋标题居中 ==")
fl = read("Overlay/FloatingLyricViewController.swift")
check("FloatingLyricViewController: no hintLabel left",
      "hintLabel" not in fl)
check("FloatingLyricViewController: no hint strings left",
      "长按拖动" not in fl and "已固定" not in fl)
check("FloatingLyricViewController: lyric stack anchored to card (12pt top/bottom)",
      "stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12)" in fl
      and "stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)" in fl)
check("FloatingLyricViewController: lock guard + save/restore untouched",
      "guard !positionLocked else { return }" in fl
      and "private func savePosition(center: CGPoint)" in fl
      and "private func restorePosition()" in fl)
pd = read("App/PlaybackDashboardView.swift")
check("PlaybackDashboardView: hint line between song card and floating toggle",
      '"悬浮窗口 · 长按拖动 · 双击隐藏"' in pd
      and '"悬浮窗口 · 已固定 · 双击隐藏"' in pd
      and pd.index('"悬浮窗口 · 长按拖动 · 双击隐藏"') > pd.index('进度：')
      and pd.index('"悬浮窗口 · 长按拖动 · 双击隐藏"') < pd.index('"显示悬浮歌词窗"'))
check("PlaybackDashboardView: title centered (ZStack, gear stays top-right)",
      "ZStack(alignment: .topTrailing)" in pd
      and '.frame(maxWidth: .infinity, alignment: .center)' in pd
      and '"桌面歌词"' in pd
      and ".padding(.top, 80)" in pd
      and "gearshape.fill" in pd
      and pd.index('ZStack(alignment: .topTrailing)') < pd.index('"桌面歌词"'))
check("Version is 1.0.3 / build 16 (1.0.3 bumped version)",
      read("TrollLyricsDesk/Info.plist").count("<string>1.0.3</string>") == 1
      and read("TrollLyricsDesk/Info.plist").count("<string>16</string>") == 1)

print("\n== 6.10 1.0.3：授权激活（服务器验证） ==")
ls = read("Lyrics/LyricStore.swift")
check("ActivationStore in LyricStore.swift (shared by App + Widget targets)",
      "enum ActivationStore" in ls)
check("ActivationStore: verify URL is /api/verify",
      '"https://guhailong-repo.pages.dev/api/verify"' in ls
      and "verifyURLString" in ls)
check("ActivationStore: keys tld.activated / tld.activationType",
      '"tld.activated"' in ls and '"tld.activationType"' in ls)
check("ActivationStore: isActivated / activationType / markActivated(type:)",
      "static var isActivated: Bool" in ls
      and "static var activationType: String?" in ls
      and "static func markActivated(type: String)" in ls)
check("ActivationStore: no code values in LyricStore (keys + URL only)",
      "TLD-" not in ls)
av = read("App/ActivationView.swift")
check("ActivationGateView: @AppStorage reads tld.activated from App Group",
      "struct ActivationGateView" in av
      and "@AppStorage(ActivationStore.activatedKey" in av
      and "UserDefaults(suiteName: LyricStore.groupID)" in av)
check("ActivationGateView: unactivated shows ActivationView, else content",
      "if activated" in av and "ActivationView()" in av)
check("ActivationVerifier: normalizes code (trim + uppercase)",
      "trimmingCharacters(in: .whitespacesAndNewlines).uppercased()" in av)
check("ActivationVerifier: POSTs to verifyURLString with JSON body",
      'request.httpMethod = "POST"' in av
      and "URLSession.shared.data(for: request)" in av
      and '"application/json"' in av)
check("ActivationVerifier: wrongCode vs needsNetwork distinguished",
      "case wrongCode" in av and "case needsNetwork" in av
      and "decoded.valid" in av and "http.statusCode == 200" in av)
check("ActivationView: input + activate button, full screen",
      "struct ActivationView: View" in av
      and 'TextField("输入激活码"' in av
      and '"激活"' in av and "AppBackgroundView()" in av)
check("ActivationView: wrong-code message / needs-network message",
      '"激活码不正确，请重新输入"' in av
      and '"需要联网激活，请检查网络后重试"' in av)
check("ActivationView: success writes App Group mark + reloads widget timelines",
      "ActivationStore.markActivated(type: type)" in av
      and "WidgetCenter.shared.reloadAllTimelines()" in av)
check("ActivationView: log lines never interpolate the code value",
      "\\(code)" not in av and "\\(type)" in av)
check("ActivationView: no code values in source (no TLD- literal)",
      "TLD-" not in av)
runtime = read("App/TrollLyricsDeskApp.swift")
check("makeRootViewController wraps PlaybackDashboardView in ActivationGateView",
      "ActivationGateView {" in runtime
      and "PlaybackDashboardView()" in runtime
      and runtime.index("ActivationGateView") < runtime.index("PlaybackDashboardView()"))
check("FloatingLyricViewController: hidden when not activated",
      "view.isHidden = !floatingEnabled || !ActivationStore.isActivated" in fl)
check("WidgetView: activation gate first, placeholder text",
      "if !ActivationStore.isActivated" in wv
      and '"请先在 App 内激活"' in wv
      and "notActivatedView" in wv
      and wv.index("if !ActivationStore.isActivated") < wv.index("family == .accessoryRectangular"))
check("WidgetView: placeholder covers both families (gate is above the family branch)",
      wv.index("if !ActivationStore.isActivated") < wv.index("lockScreenView"))

# 码值绝不进源码／仓库／日志：从 worker 的码表读码逐值比对，只比对、不打印。
# 码表在 ~/workspace/trolllyricsdesk-worker/codes-tld.json（12 个码），不在仓库里。
import json as _json
codes_path = os.path.expanduser("~/workspace/trolllyricsdesk-worker/codes-tld.json")
if os.path.exists(codes_path):
    with open(codes_path, encoding="utf-8") as _f:
        _codes_raw = _json.load(_f)
    _code_values = []
    def _collect(_o):
        if isinstance(_o, str):
            _code_values.append(_o)
        elif isinstance(_o, list):
            for _x in _o:
                _collect(_x)
        elif isinstance(_o, dict):
            for _x in _o.values():
                _collect(_x)
    _collect(_codes_raw)
    _code_values = [c for c in _code_values
                    if isinstance(c, str) and c.startswith("TLD-")]
    check("codes-tld.json loads (12 codes)", len(_code_values) == 12,
          f"count={len(_code_values)}")
    _tracked = subprocess.check_output(["git", "ls-files"], cwd=ROOT,
                                       text=True).splitlines()
    _hits = []
    for _rel in _tracked:
        _p = os.path.join(ROOT, _rel)
        if not os.path.isfile(_p):
            continue
        try:
            _content = open(_p, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for _c in _code_values:
            if _c in _content:
                _hits.append(f"{_rel} contains a code value")
    check("no code value in any tracked file", not _hits, str(_hits[:5]))
    _all_text = ""
    for dirpath, _, filenames in os.walk(ROOT):
        if ".git" in dirpath or "hidden_files" in dirpath:
            continue
        for fn in filenames:
            if fn.endswith((".swift", ".m", ".h", ".plist", ".yml", ".md", ".py")):
                _all_text += open(os.path.join(dirpath, fn),
                                  encoding="utf-8", errors="ignore").read() + "\n"
    check("no activation-code-shaped literal in source",
          len(re.findall(r"TLD-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}",
                         _all_text)) == 0)
else:
    open_item("codes-tld.json not found — code-value scan skipped",
              "码表不在本机时无法逐值比对；有码表再跑一次")

print("\n== 7. OPEN（PLAN 第 8 节，如实列，不编通过） ==")
open_item("1.0.3 激活要真机验：首次打开全屏激活页",
          "全新安装（或清掉 App Group 后）第一次打开：全屏激活页，不进主界面；"
          "输对码后直接进主界面，不用重启；杀掉重开直接进主界面，不再要码")
open_item("1.0.3 激活要真机验：码不对／没网",
          "输错码提示「激活码不正确」，仍在激活页；断网（飞行模式）点激活提示"
          "「需要联网激活」，仍在激活页；两种情况都不放行")
open_item("1.0.3 激活要真机验：小组件占位",
          "未激活时主屏幕小组件和锁屏小组件都显示「请先在 App 内激活」，不显示歌词；"
          "激活后小组件恢复正常内容（时间轴已刷新）")
open_item("1.0.3 激活要真机验：悬浮窗未激活隐藏",
          "未激活时放音乐悬浮窗也不出歌词；激活后 0.25s 内自动出现，不用重启")
open_item("1.0.3 激活要真机验：master／code 两类码",
          "两类码都要有人在真机上试过：master 码与普通码各至少一次，激活后"
          "类型记录正确")
open_item("1.0.3：激活标记存在 App Group，卸载重装要重新激活",
          "iOS 删 App 时 App Group 数据一般随之清除，重装后应重新要码；"
          "真机上验证一次")
open_item("macOS 编译未做（Linux 没 Xcode/swiftc）",
          "1.0.1 的 ActivityKit 弱链接写法（App＋Widget 各两配置）、DynamicIsland "
          "展开区、if #available 组合条件，都要 macOS 构建那一步才见分晓")
open_item("1.0.2 新功能要真机验：Telegram 行点开进频道、日志复制／清除",
          "Telegram 行改成 @Guhailon（tg://resolve?domain=Guhailon，退回 https://t.me/Guhailon）："
          "点开要能直接进 SeaDragon 越狱源公开频道；没装 Telegram 时退回网页版；"
          "日志页复制要能把整份日志贴到别处，清除要点确认后页面变空、文件删掉，"
          "再写日志时文件要重建；"
          "注：lastLiveState 编译错已在 1.0.1 修好（LiveLyricKey），run 45737671775 编过，"
          "1.0.4 build 17 Archive 失败基本坐实是同根原因，不再单列")
open_item("1.0.2 背景更换要真机验（新增第三件）",
          "设置页「背景设置」选图后，主界面／设置页／关于页要立即换成这张图；"
          "开关关掉变纯黑；透明度滑杆拖动图跟着变透（默认 0.25 即图 75% 显示）；"
          "没选过图时是原来的紫／黑／蓝渐变；悬浮窗与小组件不受影响")
open_item("1.0.2 悬浮窗固定位置要真机验（新增第四件）",
          "主界面悬浮歌词区打开「固定悬浮窗位置」后，悬浮窗拖不动、主界面的提示行变成"
          "“悬浮窗口 · 已固定 · 双击隐藏”，双击隐藏仍可用；关掉开关又能拖；"
          "重启 App 后悬浮窗还在上次存好的位置（位置本来就会记住，开关只锁拖动）")
open_item("1.0.2 提示文字移到界面＋标题居中要真机验（新增第五件）",
          "悬浮窗里只剩歌词，没有任何提示小字；主界面歌曲卡片和开关之间有一行提示，"
          "开锁时变“悬浮窗口 · 已固定 · 双击隐藏”，关锁时变“悬浮窗口 · 长按拖动 · 双击隐藏”；"
          "「桌面歌词」标题横向居中，齿轮仍在右上角原位")
open_item("otool 弱链接核实（编成后验包新增）",
          "App 与 Widget Extension 两个二进制各跑 otool -l | grep ActivityKit，"
          "都要是 LC_LOAD_WEAK_DYLIB；强链接则 iOS 15 有启动失败风险")
open_item("Activity 更新会不会被系统节流（PLAN §8.1）",
          "设计上变行才推（一行 4–5 秒一次）远低于上限，理论上不会被节流；"
          "iOS 27 下的实际节流阈值没验过，真机连续听 10 首歌看横幅跟不跟")
open_item("8 小时到期后要不要自动重开（PLAN §8.2，已按审查更正）",
          "Live Activity 最长约 8 小时，系统结束后内容最多再留约 4 小时；"
          "App 被划掉不等于 Activity 立即消失，ActivityKit 也不给检测引擎后台执行能力；"
          "默认：到期横幅消失，用户回 App 再点开关；保活开着时可顺手重开，等真机验了再定")
open_item("锁屏横幅取色器颜色会不会被系统压暗（PLAN §8.3）",
          "先按取色值画，真机颜色不对就退回白色")
open_item(".accessoryRectangular 在 iOS 15 上编不编得过（PLAN §8.4）",
          "已用 if #available(iOS 16.0, *) 运行时判断包起来（比 PLAN 的写法更稳妥），"
          "仍需 macOS 编译＋iOS 15 真机验证")
open_item("ActivityKit 弱链接写法（PLAN §8.5）",
          "用的是 OTHER_LDFLAGS 加 -weak_framework ActivityKit（App 两配置＋Widget 两配置，共 4 处）；"
          "以编过且 iOS 15 真机不闪退为准，另加 otool 核实见上")
open_item("LiveContainer 下 A/B 能不能用（PLAN §8.6）",
          "公开接口理论上能用，但 LiveContainer 的进程模型＋后台行为没验过")
open_item("锁屏小组件的刷新延迟到底多大（PLAN §8.7）",
          "系统说了算；实测延迟要写进给皇上的回报，不要报没测过的数字")
open_item("Live Activity 与 Overlay 同时开会两层歌词叠着（PLAN §8.8）",
          "内容一致（同一份快照），不冲突；锁屏上横幅和悬浮窗同时出现，用户关一个就行")
open_item("逐字同步没有（PLAN §8.9）",
          "锁屏歌词是逐句；逐字要 LyricWord.swift／LyricSyncEngine.swift，两边都没有")
open_item("iPhone 11 没有常亮显示（PLAN §8.10）",
          "「关屏一直显示」在 iPhone 11 上做不到，任何路子都做不到；只有 15 Pro 的常亮显示能做到")
open_item("真机必验 12 项（PLAN §7）都没验",
          "横幅／灵动岛三态／常亮／限流／滑掉同步／暂停／LiveContainer／小组件添加与延迟／外观／iOS 15")
open_item("同曲进度跳转同步（审查第 7 项，未做，独立修复）",
          "同一首歌内拖动进度条、播放状态不变时，快照可能仍沿用旧时间基准；"
          "这也影响原有桌面歌词，审查建议独立处理，等皇上定再做")
open_item("默认白色在浅色锁屏上清不清晰（ChatGPT 问题 4，需真机）",
          "第 51、110 行默认白色在浅色／深色锁屏背景下不一定清晰，真机测了再定要不要改默认色")
open_item("横幅与展开态两套布局，未按设计共用三行歌词子视图（已知出入）",
          "设计原文要求共用，实际代码是两套布局——不是编译错误，与设计原文不一致；"
          "统一是重构项，1.0.1 先不动，等皇上定")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens), "items (see above)")
sys.exit(1 if fails else 0)
