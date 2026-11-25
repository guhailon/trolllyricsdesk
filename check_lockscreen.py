#!/usr/bin/env python3
"""Verify TrollLyricsDesk lockscreen lyrics (1.0.0 build 15, overlay-base):
A Live Activities + B lock-screen widget, per hidden_files/lockscreen-design/PLAN.md §6.

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


print("== 1. 新文件 ==")
for rel in ["LiveActivity/LyricsLiveActivity.swift",
            "PlaybackEngine/LyricsLiveActivityController.swift"]:
    check(f"exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))

print("\n== 2. 版本 / MinOS ==")
for rel in ["TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist"]:
    pl = plistlib.loads(open(os.path.join(ROOT, rel), "rb").read())
    check(f"{rel}: version 1.0.0", pl.get("CFBundleShortVersionString") == "1.0.0",
          str(pl.get("CFBundleShortVersionString")))
    check(f"{rel}: build 15", pl.get("CFBundleVersion") == "15",
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

pc = read("PlaybackEngine/PlaybackCoordinator.swift")
check("coordinator: state = newState still present (no 1.0.6 regression)",
      "state = newState" in pc)
check("coordinator: publishLiveLyrics defined",
      "private func publishLiveLyrics()" in pc)
check("coordinator: publishLiveLyrics called at end of poll() + track-change branch",
      pc.count("publishLiveLyrics()") == 3,  # 1 def + 2 call sites
      f"count={pc.count('publishLiveLyrics()')}")
check("coordinator: lastLiveLyricIndex / lastLiveTrackKey (变行才推）",
      "lastLiveLyricIndex" in pc and "lastLiveTrackKey" in pc)
check("coordinator: no-lyrics placeholder ♪ {title} once per track",
      '"♪ \\(snapshot.title)"' in pc)
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
check("ContentView: existing sections untouched (音乐检测／保活开关）",
      '"音乐检测"' in cv and '"后台保活（静音音频）"' in cv)

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
check("WidgetView: lock-screen branch (family == .accessoryRectangular)",
      "context.family == .accessoryRectangular" in wv)
check("WidgetView: lock-screen view (title + current + next)",
      "lockScreenView" in wv and "桌面歌词 · " in wv)
check("WidgetView: main-screen layout kept (moved verbatim to mainScreenView)",
      "mainScreenView" in wv and "打开 App 加载歌词" in wv
      and '"等待歌词..."' in wv and "LyricStore.currentLyric(" in wv)

print("\n== 5. pbxproj ==")
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: LiveActivity group present",
      'name = "LiveActivity"' in pbx and 'path = "LiveActivity"' in pbx)
check("pbxproj: both new files in App Sources phase",
      "LyricsLiveActivity.swift in Sources" in pbx
      and "LyricsLiveActivityController.swift in Sources" in pbx)
check("pbxproj: ActivityKit weak-linked (2x -weak_framework)",
      pbx.count('"-weak_framework"') == 2 and pbx.count('"ActivityKit"') == 2,
      f"weak={pbx.count(chr(34) + '-weak_framework' + chr(34))}")
check("pbxproj: no strong ActivityKit link phase entry",
      "ActivityKit.framework" not in pbx)
check("pbxproj: MinOS still 15.0 everywhere",
      "IPHONEOS_DEPLOYMENT_TARGET = 15.0" in pbx
      and "IPHONEOS_DEPLOYMENT_TARGET = 16.0" not in pbx)
check("pbxproj: MARKETING_VERSION still 1.0.0",
      "MARKETING_VERSION = 1.0.0" in pbx)
_resolved = pbx_resolved_files(pbx)
for f in ["LiveActivity/LyricsLiveActivity.swift",
          "PlaybackEngine/LyricsLiveActivityController.swift"]:
    check(f"pbxproj: resolves {f}", f in _resolved)
missing = [r for r in _resolved if not os.path.exists(os.path.join(ROOT, r))]
check("pbxproj: all referenced files exist on disk", not missing, str(missing))
obj_ids = set(re.findall(r"\t\t([0-9A-F]{24}) /\* \w+ \*/ = \{", pbx))
dangling = [fr for fr in re.findall(r"fileRef = ([0-9A-F]{24});", pbx)
            if fr not in obj_ids]
check("pbxproj: no dangling fileRefs", not dangling, str(dangling))
check("pbxproj: braces/parens balanced",
      pbx.count("{") == pbx.count("}") and pbx.count("(") == pbx.count(")"))

print("\n== 6. 红线 ==")
diff_overlay = subprocess.check_output(
    ["git", "diff", "--stat", "HEAD", "--", "Overlay/"],
    cwd=ROOT, text=True)
check("Overlay/ untouched (git diff vs HEAD empty)", diff_overlay.strip() == "",
      diff_overlay.strip())
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
          "TrollLyricsWidget/TrollLyricsWidget.swift",
          "TrollLyricsWidget/WidgetView.swift"]:
    t = read(f)
    check(f"{f}: braces balanced", t.count("{") == t.count("}"),
          f"{{={t.count(chr(123))} }}={t.count(chr(125))}")
    check(f"{f}: parens balanced", t.count("(") == t.count(")"),
          f"(={t.count(chr(40))} )={t.count(chr(41))}")

print("\n== 7. OPEN（PLAN 第 8 节，如实列，不编通过） ==")
open_item("macOS 编译未做（Linux 没 Xcode/swiftc）",
          "ActivityKit 弱链接写法、DynamicIsland 展开区、if #available 组合条件，"
          "都要 macOS 构建那一步才见分晓")
open_item("Activity 更新会不会被系统节流（PLAN §8.1）",
          "设计上变行才推（一行 4–5 秒一次）远低于上限，理论上不会被节流；"
          "iOS 27 下的实际节流阈值没验过，真机连续听 10 首歌看横幅跟不跟")
open_item("8 小时到期后要不要自动重开（PLAN §8.2）",
          "默认：到期横幅消失，用户回 App 再点开关；保活开着时可顺手重开，等真机验了再定")
open_item("锁屏横幅取色器颜色会不会被系统压暗（PLAN §8.3）",
          "先按取色值画，真机颜色不对就退回白色")
open_item(".accessoryRectangular 在 iOS 15 上编不编得过（PLAN §8.4）",
          "已用 if #available(iOS 16.0, *) 运行时判断包起来（比 PLAN 的写法更稳妥），"
          "仍需 macOS 编译＋iOS 15 真机验证")
open_item("ActivityKit 弱链接写法（PLAN §8.5）",
          "用的是 OTHER_LDFLAGS 加 -weak_framework ActivityKit（两 App 配置）；"
          "以编过且 iOS 15 真机不闪退为准")
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

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens), "items (see above)")
sys.exit(1 if fails else 0)
