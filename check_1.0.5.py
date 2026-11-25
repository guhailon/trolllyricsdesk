#!/usr/bin/env python3
"""Verify TrollLyricsDesk 1.0.5 project: structure, ids, Lee's files verbatim,
no built-in songs, no activation, adapters public-only, LRC sample parse,
plists/entitlements/pbxproj/scheme valid, icons complete.

FAILED: none is the goal. OPEN items are recorded, not failures:
things that cannot be verified on Linux (macOS compile, device) or that
are still waiting on Lee (push+build approval).
"""
import hashlib
import json
import os
import plistlib
import re
import sys

ROOT = os.path.expanduser("~/workspace/trolllyricsdesk")
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


# A file ref's on-disk path is its parent group's path + the ref path
# (Xcode semantics). The old checks assumed ref paths were
# project-root-relative ("Lyrics/X.swift"); that assumption is exactly
# the doubled-path bug (group path + ref path was "Lyrics/Lyrics/X.swift").
# Resolve through the group tree instead.
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
            m3 = re.match(r'\t\t\tpath = "([^"]+)";', ln)
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


def sha256(b):
    return hashlib.sha256(b).hexdigest()


print("== project size / manifest ==")
total = 0
manifest = []
for dirpath, _, filenames in os.walk(ROOT):
    if ".git" in dirpath:
        continue
    for fn in sorted(filenames):
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, ROOT)
        data = open(p, "rb").read()
        total += len(data)
        manifest.append((rel, len(data), sha256(data)[:12]))
print(f"total: {total} B across {len(manifest)} files")
for rel, size, h in manifest:
    print(f"  {h} {size:>7}  {rel}")

print("\n== 1. Lee's new tree (02:15, exact structure) ==")
lee_tree = [
    "App/ContentView.swift",
    "App/PlaybackDashboardView.swift",
    "App/LyricsSearchView.swift",
    "PlaybackEngine/PlaybackState.swift",
    "PlaybackEngine/PlaybackAdapter.swift",
    "PlaybackEngine/PlaybackCoordinator.swift",
    "PlaybackEngine/LyricMatcher.swift",
    "MusicProviders/MusicTrack.swift",
    "MusicProviders/AppleMusicAdapter.swift",
    "MusicProviders/MediaRemoteAdapter.swift",
    "MusicProviders/NetEaseAdapter.swift",
    "MusicProviders/QQMusicAdapter.swift",
    "MusicProviders/ExternalTrackInput.swift",
    "Lyrics/LRCLibClient.swift",
    "Lyrics/LyricParser.swift",
    "Lyrics/LyricStore.swift",
    "Lyrics/LyricLine.swift",
    "Lyrics/LocalLRCImporter.swift",
    "App/SettingsView.swift",
    "App/AboutView.swift",
    "App/LogView.swift",
    "TrollLyricsDesk/LyricLogger.swift",
    "TrollLyricsDesk/Assets.xcassets",
    "TrollLyricsWidget/TrollLyricsWidget.swift",
    "TrollLyricsWidget/TimelineProvider.swift",
    "TrollLyricsWidget/WidgetView.swift",
    "TrollLyricsWidget/TrollLyricsWidgetBundle.swift",
]
for rel in lee_tree:
    if rel == "TrollLyricsWidget/TimelineProvider.swift":
        # Provider lives inside TrollLyricsWidget.swift (Lee's file); no separate file.
        content = read("TrollLyricsWidget/TrollLyricsWidget.swift")
        check("TimelineProvider.swift -> inside TrollLyricsWidget.swift (Lee's file)",
              "struct TrollLyricsProvider: TimelineProvider" in content)
        continue
    check(f"tree item exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))
for dead_dir in ["Shared", "LocalLyrics", "LyricsSearch"]:
    check(f"old group gone: {dead_dir}/",
          not os.path.exists(os.path.join(ROOT, dead_dir)))

print("\n== 2. Lee's files verbatim (content markers) ==")
markers = {
    "Lyrics/LyricLine.swift": ["struct LyricLine: Codable, Identifiable",
                               "var time: TimeInterval", "var text: String"],
    "Lyrics/LyricParser.swift": ['#"\\[(\\d{1,2}):(\\d{2})(?:\\.(\\d{1,3}))?\\](.*)"#',
                                 "static func parse(_ lrc: String) -> [LyricLine]",
                                 "return result.sorted"],
    "Lyrics/LyricStore.swift": ['"group.com.hailong.TrollLyricsDesk"',
                                "struct LyricSnapshot: Codable",
                                "static func currentLyric("],
    "App/ContentView.swift": ["加载测试歌词", "demoLyrics",
                              "透明动漫歌词桌面", "请在主屏幕添加 TrollLyrics Widget",
                              "歌词搜索与导入", "LyricsSearchView()",
                              "统一音乐播放引擎", "PlaybackDashboardView()"],
    "TrollLyricsWidget/TrollLyricsWidget.swift": ["struct TrollLyricsProvider: TimelineProvider",
                                                  'let kind = "TrollLyricsWidget"',
                                                  "supportedFamilies([",
                                                  ".configurationDisplayName(\"Troll Lyrics\")",
                                                  "预先安排后续歌词",
                                                  "finalDate.addingTimeInterval(30)"],
    "TrollLyricsWidget/WidgetView.swift": ["struct TrollLyricsWidgetView: View",
                                           "LyricStore.currentLyric(",
                                           "打开 App 加载歌词"],
    "TrollLyricsWidget/TrollLyricsWidgetBundle.swift": ["@main",
                                                        "struct TrollLyricsWidgetBundle: WidgetBundle",
                                                        "TrollLyricsWidget()"],
    "MusicProviders/MusicTrack.swift": ["enum MusicPlatform: String, Codable, CaseIterable, Identifiable",
                                        "struct MusicTrack: Codable, Identifiable, Equatable",
                                        'case netEase = "网易云音乐"',
                                        'case qqMusic = "QQ音乐"'],
    "MusicProviders/NetEaseAdapter.swift": ["struct NetEaseAdapter {",
                                            "func makeTrack(",
                                            "platform: .netEase"],
    "MusicProviders/QQMusicAdapter.swift": ["struct QQMusicAdapter {",
                                            "func makeTrack(",
                                            "platform: .qqMusic"],
    "MusicProviders/ExternalTrackInput.swift": ["enum ExternalTrackInput",
                                                "static func makeTrack(",
                                                "platform: platform"],
    "MusicProviders/AppleMusicAdapter.swift": ["final class AppleMusicAdapter: PlaybackAdapter",
                                               "MPMusicPlayerController.systemMusicPlayer",
                                               "MPMediaItemPropertyTitle",
                                               "func requestMusicPermission(",
                                               "MPMediaLibrary.requestAuthorization",
                                               "completion(status == .authorized)"],
    "MusicProviders/MediaRemoteAdapter.swift": ["final class MediaRemoteAdapter: PlaybackAdapter",
                                                "MRMediaRemoteGetNowPlayingInfo",
                                                "kMRMediaRemoteNowPlayingInfoTimestamp",
                                                "kMRMediaRemoteNowPlayingInfoPlaybackRate",
                                                "static func cleanTitle(",
                                                "platform: .manual"],
    "PlaybackEngine/PlaybackState.swift": ["enum PlaybackStatus: String, Codable",
                                           "struct PlaybackState: Equatable",
                                           "var trackKey: String"],
    "PlaybackEngine/PlaybackAdapter.swift": ["@MainActor",
                                             "protocol PlaybackAdapter",
                                             "func currentState() -> PlaybackState?"],
    "PlaybackEngine/LyricMatcher.swift": ["struct LyricMatcher",
                                          "static func bestMatch(",
                                          "value += 60",
                                          "value += 40"],
    "PlaybackEngine/PlaybackCoordinator.swift": ["final class PlaybackCoordinator: ObservableObject",
                                                 "withTimeInterval: 1.0",
                                                 "LyricMatcher.bestMatch(",
                                                 "防止搜索期间歌曲已经切换"],
    "App/PlaybackDashboardView.swift": ["struct PlaybackDashboardView: View",
                                        "PlaybackCoordinator(",
                                        "adapter: MediaRemoteAdapter()",
                                        "开始检测音乐",
                                        "网易云 / QQ / 本地歌词"],
    "Lyrics/LRCLibClient.swift": ["final class LRCLibClient",
                                  "https://lrclib.net",
                                  '"/api/search"',
                                  "fetchSyncedLyrics"],
    "Lyrics/LocalLRCImporter.swift": ["enum LocalLRCImporter",
                                      "startAccessingSecurityScopedResource",
                                      "LyricParser.parse(content)"],
    "App/LyricsSearchView.swift": ["struct LyricsSearchView: View",
                                   "LRCLibClient.shared.search",
                                   "fileImporter",
                                   "歌词管理"],
    "App/AboutView.swift": ["struct AboutView: View",
                            "LogView()",
                            "当前版本",
                            "加入官方群组",
                            "166623677",
                            "mqqapi://card/show_pslcard",
                            "作者",
                            "China fly",
                            "Telegram 频道",
                            "@seadragonjb",
                            "tg://join?invite=I-I8aw7HUAw1NGY9",
                            "https://t.me/+I-I8aw7HUAw1NGY9"],
    "App/LogView.swift": ["struct LogView: View",
                          "LyricLogger.read()",
                          "暂无日志",
                          "ShareLink"],
}
for rel, ms in markers.items():
    text = read(rel)
    for m in ms:
        check(f"{rel} contains {m[:48]!r}", m in text)
check("ContentView links to AboutView", "AboutView()" in read("App/ContentView.swift"))
check("SettingsView links to AboutView", "AboutView()" in read("App/SettingsView.swift"))

print("\n== 3. SettingsView (Lee's original, 02:37) ==")
settings = read("App/SettingsView.swift")
check("SettingsView.swift at App/SettingsView.swift (Lee's tree)",
      os.path.exists(os.path.join(ROOT, "App/SettingsView.swift")))
check("SettingsView.swift old placeholder gone",
      not os.path.exists(os.path.join(ROOT, "TrollLyricsDesk/SettingsView.swift")))
check("SettingsView.swift: no placeholder text", "PLACEHOLDER" not in settings)
check("SettingsView.swift in pbxproj at App/ path",
      "App/SettingsView.swift" in
      pbx_resolved_files(read("TrollLyricsDesk.xcodeproj/project.pbxproj")))
for key in ["lyricsFontSize", "lyricsOpacity", "backgroundOpacity",
            "lyricsDisplayMode", "showNextLine", "animeBackgroundEnabled",
            "selectedBackgroundData"]:
    check(f"SettingsView @AppStorage key in App Group store: {key}",
          f'@AppStorage("{key}", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))' in settings)
check("SettingsView: no plain @AppStorage left (all 7 migrated, Lee 02:39)",
      settings.count('@AppStorage("') == 7 and
      all(f'@AppStorage("{k}")' not in settings for k in
          ["lyricsFontSize", "lyricsOpacity", "backgroundOpacity",
           "lyricsDisplayMode", "showNextLine", "animeBackgroundEnabled",
           "selectedBackgroundData"]))
# Lee's 7 features (his 02:38 list — all in his original file):
check("SettingsView f1: font-size slider 14-36",
      "value: $lyricsFontSize" in settings and "in: 14...36" in settings)
check("SettingsView f2: lyrics-opacity slider 0.1-1.0",
      "value: $lyricsOpacity" in settings and "in: 0.1...1.0" in settings)
check("SettingsView f3: display mode highlight/karaoke",
      "逐句高亮" in settings and "逐字卡拉OK" in settings)
check("SettingsView f4: background-opacity slider 0-1",
      "value: $backgroundOpacity" in settings and "in: 0...1" in settings)
check("SettingsView f5: anime bg toggle + PhotosPicker + preview",
      "animeBackgroundEnabled" in settings and "PhotosPicker" in settings
      and "backgroundImage" in settings)
check("SettingsView f6: saveSettings stores @AppStorage + bg JPEG",
      "private func saveSettings()" in settings
      and "jpegData(compressionQuality: 0.8)" in settings)
check("SettingsView f7: save reloads widget timelines",
      "WidgetCenter.shared.reloadAllTimelines()" in settings)
open_item("SettingsView settings now in App Group store; widget still reads snapshot",
          "7 keys migrated to UserDefaults(suiteName: group...) (Lee 02:39); "
          "widget still reads opacity/fontSize from LyricSnapshot (App Group) — "
          "Lee decides whether the widget reads the shared keys or the snapshot")
open_item("karaoke is an option only, not implemented (Lee 02:39)",
          "lyricsDisplayMode 'karaoke' has no per-character timeline parsing yet; "
          "needs per-character lyric data structure + sync logic — follow-up work, not this round")

print("\n== 3b. App Group consistency (Lee 02:39) ==")
GROUP = "group.com.hailong.TrollLyricsDesk"
pbx3b = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
for rel in ["TrollLyricsDesk/TrollLyricsDesk.entitlements",
            "TrollLyricsWidget/TrollLyricsWidget.entitlements"]:
    ent = plistlib.loads(open(os.path.join(ROOT, rel), "rb").read())
    check(f"{rel}: app group is {GROUP}",
          ent.get("com.apple.security.application-groups") == [GROUP],
          str(ent.get("com.apple.security.application-groups")))
check("pbxproj: App target CODE_SIGN_ENTITLEMENTS -> TrollLyricsDesk entitlements",
      pbx3b.count('CODE_SIGN_ENTITLEMENTS = "TrollLyricsDesk/TrollLyricsDesk.entitlements"') == 2)
check("pbxproj: Widget target CODE_SIGN_ENTITLEMENTS -> TrollLyricsWidget entitlements",
      pbx3b.count('CODE_SIGN_ENTITLEMENTS = "TrollLyricsWidget/TrollLyricsWidget.entitlements"') == 2)
check("pbxproj: no other CODE_SIGN_ENTITLEMENTS values",
      pbx3b.count("CODE_SIGN_ENTITLEMENTS") == 4)

print("\n== 4. Bundle IDs / App Group consistency ==")
APP_ID = "com.hailong.TrollLyricsDesk"
WIDGET_ID = "com.hailong.TrollLyricsDesk.TrollLyricsWidget"
GROUP_ID = "group.com.hailong.TrollLyricsDesk"
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: app bundle id", f"PRODUCT_BUNDLE_IDENTIFIER = {APP_ID}" in pbx or
      f'PRODUCT_BUNDLE_IDENTIFIER = "{APP_ID}"' in pbx)
check("pbxproj: widget bundle id", WIDGET_ID in pbx)
check("pbxproj: deployment target 16.0", "IPHONEOS_DEPLOYMENT_TARGET = 16.0" in pbx)
check("pbxproj: Swift 5.0", "SWIFT_VERSION = 5.0" in pbx)
for rel, want in [("TrollLyricsDesk/Info.plist", APP_ID),
                  ("TrollLyricsWidget/Info.plist", WIDGET_ID)]:
    pl = plistlib.loads(open(os.path.join(ROOT, rel), "rb").read())
    check(f"{rel}: bundle id", pl.get("CFBundleIdentifier") == want, pl.get("CFBundleIdentifier"))
    check(f"{rel}: version 1.0.5", pl.get("CFBundleShortVersionString") == "1.0.5")
    check(f"{rel}: min OS 16.0", pl.get("MinimumOSVersion") == "16.0", str(pl.get("MinimumOSVersion")))
app_pl = plistlib.loads(open(os.path.join(ROOT, "TrollLyricsDesk/Info.plist"), "rb").read())
check("app Info.plist: NSAppleMusicUsageDescription (Lee's text)",
      app_pl.get("NSAppleMusicUsageDescription") == "用于读取用户授权的音乐资料和显示歌曲信息。",
      str(app_pl.get("NSAppleMusicUsageDescription")))
for rel in ["TrollLyricsDesk/TrollLyricsDesk.entitlements",
            "TrollLyricsWidget/TrollLyricsWidget.entitlements"]:
    ent = plistlib.loads(open(os.path.join(ROOT, rel), "rb").read())
    groups = ent.get("com.apple.security.application-groups", [])
    check(f"{rel}: app group", groups == [GROUP_ID], str(groups))
app_ent = plistlib.loads(open(
    os.path.join(ROOT, "TrollLyricsDesk/TrollLyricsDesk.entitlements"), "rb").read())
check("app entitlements: mediaremote now-playing-read-access (follow uses them again, Lee 02:30)",
      app_ent.get("com.apple.mediaremote.now-playing-read-access") is True)
check("app entitlements: mediaremote full-now-playing-read-access (follow uses them again, Lee 02:30)",
      app_ent.get("com.apple.mediaremote.full-now-playing-read-access") is True)
check("LyricStore groupID matches", f'"{GROUP_ID}"' in read("Lyrics/LyricStore.swift"))
check("widget Info.plist: widgetkit extension point",
      plistlib.loads(open(os.path.join(
          ROOT, "TrollLyricsWidget/Info.plist"), "rb").read())
      .get("NSExtension", {}).get("NSExtensionPointIdentifier")
      == "com.apple.widgetkit-extension")

print("\n== 5. pbxproj / scheme structure ==")
check("pbxproj: app target present", '"TrollLyricsDesk"' in pbx and
      "com.apple.product-type.application" in pbx)
check("pbxproj: widget target present", '"TrollLyricsWidget"' in pbx and
      "com.apple.product-type.app-extension" in pbx)
check("pbxproj: Embed App Extensions phase", "Embed App Extensions" in pbx)
check("pbxproj: embed dstSubfolderSpec 13 (PlugIns)", "dstSubfolderSpec = 13" in pbx)
check("pbxproj: App Groups capability enabled (both targets)",
      pbx.count("com.apple.ApplicationGroups") >= 2, str(pbx.count("com.apple.ApplicationGroups")))
check("pbxproj: app entitlements path",
      "TrollLyricsDesk/TrollLyricsDesk.entitlements" in pbx)
check("pbxproj: widget entitlements path",
      "TrollLyricsWidget/TrollLyricsWidget.entitlements" in pbx)
check("pbxproj: widget extension API only", "APPLICATION_EXTENSION_API_ONLY = YES" in pbx)
check("pbxproj: new groups App/PlaybackEngine/Lyrics/MusicProviders",
      all(g in pbx for g in ['name = "App"', 'name = "PlaybackEngine"',
                             'name = "Lyrics"', 'name = "MusicProviders"']))
check("pbxproj: old groups Shared/LocalLyrics/LyricsSearch gone",
      all(g not in pbx for g in ['name = "Shared"', 'name = "LocalLyrics"',
                                  'name = "LyricsSearch"']))
_resolved = pbx_resolved_files(pbx)
for f in ["App/ContentView.swift",
          "HUD/LyricsHUDView.swift", "HUD/LyricsHUDController.swift",
          "HUD/LyricsHUDBridge.swift", "HUD/FloatingLyricsController.swift",
          "HUD/FloatingLyricsPanel.swift", "HUD/FloatingLyricsStyle.swift",
          "App/TLAppRoot.swift",
          "App/PlaybackDashboardView.swift", "App/LyricsSearchView.swift",
          "PlaybackEngine/PlaybackState.swift", "PlaybackEngine/PlaybackAdapter.swift",
          "PlaybackEngine/PlaybackCoordinator.swift", "PlaybackEngine/LyricMatcher.swift",
          "MusicProviders/MusicTrack.swift", "MusicProviders/AppleMusicAdapter.swift",
          "MusicProviders/MediaRemoteAdapter.swift",
          "MusicProviders/NetEaseAdapter.swift", "MusicProviders/QQMusicAdapter.swift",
          "MusicProviders/ExternalTrackInput.swift", "Lyrics/LRCLibClient.swift",
          "Lyrics/LyricParser.swift", "Lyrics/LyricStore.swift", "Lyrics/LyricLine.swift",
          "Lyrics/LocalLRCImporter.swift", "Core/MediaRemoteBridge.swift",
          "Core/MediaRemoteSymbols.swift", "Core/PlaybackStateEngine.swift",
          "Core/TrackIdentifier.swift"]:
    check(f"pbxproj: references {f}", f in _resolved)
check("pbxproj: deleted files fully gone (MusicPlatformAdapter/NowPlayingFollower)",
      "MusicPlatformAdapter" not in pbx and "NowPlayingFollower" not in pbx)
check("pbxproj: deleted files fully gone (LyricSearchService/ImportSearchView)",
      "LyricSearchService" not in pbx and "ImportSearchView" not in pbx)
check("pbxproj: MediaPlayer.framework linked (app target)",
      "MediaPlayer.framework" in pbx and
      "System/Library/Frameworks/MediaPlayer.framework" in pbx)
# every file referenced in pbxproj must exist on disk (resolved via group tree)
missing = [r for r in _resolved if not os.path.exists(os.path.join(ROOT, r))]
check("pbxproj: all referenced files exist on disk", not missing, str(missing))
# every build file's fileRef must resolve to a real object
obj_ids = set(re.findall(r"\t\t([0-9A-F]{24}) /\* \w+ \*/ = \{", pbx))
dangling = [fr for fr in re.findall(r"fileRef = ([0-9A-F]{24});", pbx) if fr not in obj_ids]
check("pbxproj: no dangling fileRefs", not dangling, str(dangling))
scheme = read("TrollLyricsDesk.xcodeproj/xcshareddata/xcschemes/TrollLyricsDesk.xcscheme")
check("scheme exists", os.path.exists(os.path.join(
    ROOT, "TrollLyricsDesk.xcodeproj/xcshareddata/xcschemes/TrollLyricsDesk.xcscheme")))
check("scheme: no placeholder target ids", "APP_TARGET_ID" not in scheme and
      "WIDGET_TARGET_ID" not in scheme)
for tid in re.findall(r'BlueprintIdentifier = "([0-9A-F]{24})"', scheme):
    check(f"scheme target {tid} exists in pbxproj", tid in pbx)
check("workflow exists", os.path.exists(os.path.join(ROOT, ".github/workflows/build.yml")))
wf = read(".github/workflows/build.yml")
check("workflow: xcodebuild archive unsigned", "CODE_SIGNING_ALLOWED=NO" in wf)
check("workflow: install zsign", "brew install zsign" in wf)
check("workflow: zsign sign app + widget", wf.count("zsign -a") >= 2)
check("workflow: package IPA", "TrollLyricsDesk-1.0.5.ipa" in wf)

print("\n== 6. No built-in songs / no activation ==")
all_swift = ""
for dirpath, _, filenames in os.walk(ROOT):
    for fn in filenames:
        if fn.endswith(".swift"):
            all_swift += open(os.path.join(dirpath, fn), encoding="utf-8").read() + "\n"
for bad in ["激活", "activation", "LW-", "codes-", "licenseCode"]:
    check(f"no activation string {bad!r}", bad not in all_swift)
# NSLayoutConstraint.activate( is UIKit layout, not an activation code —
# Lee's LyricsHUDView.swift (verbatim, v0.5) uses it.
check("no activation string 'activate(' (excluding NSLayoutConstraint.activate)",
      re.search(r"(?<!NSLayoutConstraint\.)activate\(", all_swift) is None)
check("no 123-song library", "audio-ssl.itunes.apple.com" not in all_swift)
check("no SONGS array", re.search(r'\bSONGS\s*=', all_swift) is None)
check("demo lyrics only in ContentView (Lee's demo)",
      all_swift.count("TrollLyricsDesk Demo") == 1)

print("\n== 7. No AGPL / no Textyl ==")
# Textyl/AGPL must not appear in Swift code at all now (the warning comment
# that used to live in NowPlayingFollower.swift moved to BUILD_NOTES.md).
for bad in ["textyl", "Textyl", "AGPL", "GNU Affero"]:
    check(f"no {bad!r} in Swift code", bad not in all_swift)
bn = read("BUILD_NOTES.md")
check("warning about Textyl/AGPL lives in BUILD_NOTES.md (documentation)",
      "Textyl" in bn and "AGPL" in bn)

print("\n== 8. New structure (02:15) + engine ==")
# Follow restored as MediaRemoteAdapter (Lee 02:30: 改回 MediaRemote 跟随）.
check("MediaRemoteAdapter.swift exists (follow restored as a PlaybackAdapter)",
      os.path.exists(os.path.join(ROOT, "MusicProviders/MediaRemoteAdapter.swift")))
check("MusicPlatformAdapter.swift deleted (superseded by PlaybackAdapter)",
      not os.path.exists(os.path.join(ROOT, "MusicProviders/MusicPlatformAdapter.swift")))
check("old NowPlayingFollower.swift path still gone (replaced by MediaRemoteAdapter)",
      not os.path.exists(os.path.join(ROOT, "TrollLyricsDesk/NowPlayingFollower.swift")))
check("no Swift code references deleted files",
      "NowPlayingFollower" not in all_swift and "MusicPlatformAdapter" not in all_swift
      and "importTrack" not in all_swift)
mra = read("MusicProviders/MediaRemoteAdapter.swift")
check("MediaRemoteAdapter: loads MRMediaRemoteGetNowPlayingInfo via dlopen (no direct link)",
      "MediaRemoteBridge" in mra and "MediaRemoteSymbols.getNowPlayingInfo" in mra and
      "@_silgen_name" not in mra)
bridge = read("Core/MediaRemoteBridge.swift")
check("MediaRemoteBridge: dlopen + dlsym + dlclose",
      "dlopen" in bridge and "dlsym" in bridge and "dlclose" in bridge)
check("MediaRemoteBridge: framework path from MediaRemoteSymbols",
      "MediaRemoteSymbols.frameworkPath" in bridge)
symbols = read("Core/MediaRemoteSymbols.swift")
check("MediaRemoteSymbols: framework path + 4 symbol names",
      all(s in symbols for s in ["MediaRemote.framework/MediaRemote",
                                 "MRMediaRemoteGetNowPlayingInfo",
                                 "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
                                 "MRMediaRemoteRegisterForNowPlayingNotifications",
                                 "MRMediaRemoteGetNowPlayingApplicationDisplayID"]))
check("PlaybackStatus defined once (no duplicate enum in Core)",
      all_swift.count("enum PlaybackStatus") == 1)
check("MediaRemoteAdapter: timestamp + elapsed + rate keys",
      all(k in mra for k in ["kMRMediaRemoteNowPlayingInfoTimestamp",
                             "kMRMediaRemoteNowPlayingInfoElapsedTime",
                             "kMRMediaRemoteNowPlayingInfoPlaybackRate"]))
check("MediaRemoteAdapter: title cleaning (brackets + markers)",
      "cleanTitle" in mra and "Nightcore" in mra)
check("MediaRemoteAdapter: tracks are platform .manual (source app unknown)",
      "platform: .manual" in mra)
check("MediaRemoteAdapter: 2s cache bound",
      "cacheLifetime" in mra and "2.0" in mra)
check("MediaRemote API used only by MediaRemoteAdapter.swift",
      all("MRMediaRemote" not in read(rel) and "kMRMediaRemoteNowPlayingInfo" not in read(rel) for rel in
          ["MusicProviders/AppleMusicAdapter.swift", "PlaybackEngine/PlaybackCoordinator.swift",
           "App/PlaybackDashboardView.swift", "Lyrics/LRCLibClient.swift"]))
lsv = read("App/LyricsSearchView.swift")
check("LyricsSearchView: platform picker (Apple/网易云/QQ/手动）",
      "MusicPlatform.allCases" in lsv)
check("LyricsSearchView: online search via LRCLibClient",
      "LRCLibClient.shared.search" in lsv)
check("LyricsSearchView: import local .lrc", "fileImporter" in lsv and '"lrc"' in lsv)
check("LyricsSearchView: uses makeTrack (new adapters, no importTrack)",
      lsv.count(".makeTrack(") == 2, f"count={lsv.count('.makeTrack(')}")
check("LyricsSearchView: selectLyrics isPlaying TRUE (Lee 02:04 correction)",
      lsv.count("isPlaying: true") == 1, f"count={lsv.count('isPlaying: true')}")
check("LyricsSearchView: importLocalFile isPlaying FALSE (Lee 02:04 correction)",
      lsv.count("isPlaying: false") == 1, f"count={lsv.count('isPlaying: false')}")
check("LyricsSearchView: never invent lyrics (no match -> error text)",
      "没有找到相关歌曲" in lsv)
check("LyricsSearchView: no credentials", all(b not in lsv for b in
      ["password", "api_key", "secret", "Cookie:", "Authorization"]))
cv = read("App/ContentView.swift")
check("ContentView: NavigationLink to LyricsSearchView (Lee's wiring)",
      "LyricsSearchView()" in cv and "歌词搜索与导入" in cv)
check("ContentView: NavigationLink to PlaybackDashboardView (Lee 02:19)",
      "PlaybackDashboardView()" in cv and "统一音乐播放引擎" in cv)
# currentElapsed formula (Lee 02:19)
ls = read("Lyrics/LyricStore.swift")
check("LyricStore.currentElapsed: playing = elapsedWhenPaused + timeIntervalSince(startedAt)",
      "snapshot.elapsedWhenPaused" in ls and "date.timeIntervalSince(" in ls
      and "snapshot.startedAt" in ls)
check("LyricStore.currentElapsed: paused = elapsedWhenPaused",
      ls.count("return snapshot.elapsedWhenPaused") == 1)
# coordinator: title+artist guard (Lee 02:20)
pc = read("PlaybackEngine/PlaybackCoordinator.swift")
check("PlaybackCoordinator.savePlayback: title AND artist guard (Lee 02:20)",
      "snapshot.title == state.track.title" in pc and
      "snapshot.artist == state.track.artist" in pc)
check("PlaybackCoordinator.savePlayback: no title-only guard left",
      "guard snapshot.title == state.track.title else" not in pc)
# dashboard: button + onAppear both start directly, no permission gate
# (Lee 02:26: onAppear 不用授权；Lee 02:30: MediaRemote needs no MediaLibrary grant)
pdv = read("App/PlaybackDashboardView.swift")
check("Dashboard button: direct coordinator.start(), no requestMusicPermission gate",
      "requestMusicPermission" not in pdv and "coordinator.start()" in pdv)
check("Dashboard onAppear: direct coordinator.start() (Lee 02:26: onAppear 不用授权）",
      ".onAppear {\n            coordinator.start()\n        }" in pdv)
check("Dashboard uses MediaRemoteAdapter (Lee 02:30: 改回 MediaRemote 跟随）",
      "adapter: MediaRemoteAdapter()" in pdv and "adapter: AppleMusicAdapter()" not in pdv)
# AppleMusicAdapter permission function (retained, unwired now)
ama = read("MusicProviders/AppleMusicAdapter.swift")
check("AppleMusicAdapter: requestMusicPermission present (Lee's function verbatim, retained but unwired)",
      "func requestMusicPermission(" in ama and
      "MPMediaLibrary.requestAuthorization" in ama)
open_item("AppleMusicAdapter retained but unwired (Lee's file; dashboard uses MediaRemoteAdapter)",
          "requestMusicPermission + NSAppleMusicUsageDescription stay, unused by the dashboard flow")
# LyricSnapshot stays inside LyricStore.swift (Lee's tree lists no LyricSnapshot.swift)
check("LyricSnapshot type stays in LyricStore.swift (no separate file)",
      "struct LyricSnapshot: Codable" in ls and
      not os.path.exists(os.path.join(ROOT, "Lyrics/LyricSnapshot.swift")))
# old groups gone from Swift code paths (no stale path strings)
check("no stale group paths in Swift code",
      all(s not in all_swift for s in ["Shared/", "LocalLyrics/", "LyricsSearch/"]))
# LyricLogger still present (kept per task; no callers after follower removal)
check("LyricLogger.swift kept", os.path.exists(
    os.path.join(ROOT, "TrollLyricsDesk/LyricLogger.swift")))
open_item("LyricLogger has no callers after NowPlayingFollower removal (kept per task)",
          "PlaybackCoordinator does not log yet")
# MediaRemote no longer directly linked (Lee 10:44: dlopen via Core/MediaRemoteBridge).
# NOTE (v0.5): the old check also asserted "PrivateFrameworks" absent from the
# pbxproj — that is no longer true: the HUD weak-links BackBoardServices /
# GraphicsServices / SpringBoardServices. Only MediaRemote must stay unlinked.
check("pbxproj: MediaRemote NOT directly linked (dlopen instead)",
      "MediaRemote.framework" not in pbx)

print("\n== 9. LRC sample parse (Lee's sample) ==")
# Replicate Lee's LyricParser regex in Python (same pattern, same semantics).
pattern = re.compile(r"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)")
sample = open(os.path.join(ROOT, "sample.lrc"), encoding="utf-8").read()
parsed = []
for line in sample.splitlines():
    for m in pattern.finditer(line):
        minutes, seconds, frac, text = m.group(1), m.group(2), m.group(3), m.group(4)
        t = int(minutes) * 60 + int(seconds) + (float("0." + frac) if frac else 0)
        parsed.append((t, text.strip()))
parsed.sort(key=lambda x: x[0])
expect = [(12.0, "第一句歌词"), (16.5, "第二句歌词"), (20.0, "第三句歌词"), (62.5, "第四句歌词")]
check("sample.lrc parses to 4 lines", len(parsed) == 4, str(parsed))
check("sample.lrc times 12.0/16.5/20.0/62.5 sorted", parsed == expect, str(parsed))

# Lee's 《晴天》 sample: [ti:]/[ar:]/[al:] metadata lines must be skipped.
qt = open(os.path.join(ROOT, "qingtian.lrc"), encoding="utf-8").read()
qparsed = []
for line in qt.splitlines():
    for m in pattern.finditer(line):
        minutes, seconds, frac, text = m.group(1), m.group(2), m.group(3), m.group(4)
        t = int(minutes) * 60 + int(seconds) + (float("0." + frac) if frac else 0)
        qparsed.append((t, text.strip()))
qparsed.sort(key=lambda x: x[0])
qexpect = [(15.0, "故事的小黄花"), (19.5, "从出生那年就飘着"), (24.0, "童年的荡秋千")]
check("qingtian.lrc parses to 3 lines ([ti:]/[ar:]/[al:] metadata skipped)",
      len(qparsed) == 3, str(qparsed))
check("qingtian.lrc times 15.0/19.5/24.0 sorted", qparsed == qexpect, str(qparsed))

print("\n== 10. Assets.xcassets / icons ==")
try:
    from PIL import Image
    icon_dir = os.path.join(ROOT, "TrollLyricsDesk/Assets.xcassets/AppIcon.appiconset")
    contents = json.load(open(os.path.join(icon_dir, "Contents.json")))
    want = {}
    for img in contents["images"]:
        size = img["size"].split("x")[0]
        scale = int(img["scale"].replace("x", ""))
        want[img["filename"]] = int(size) * scale
    ok = True
    for fn, px in sorted(want.items()):
        p = os.path.join(icon_dir, fn)
        if not os.path.exists(p):
            ok = False
            print(f"  missing {fn}")
            continue
        w, h = Image.open(p).size
        if (w, h) != (px, px):
            ok = False
            print(f"  {fn}: {w}x{h} != {px}x{px}")
    check("AppIcon set: all 9 sizes present + correct", ok, f"{len(want)} files")
except ImportError:
    open_item("PIL not available — icon sizes not checked")

print("\n== 11. Toolchain (Linux limits) ==")
import shutil
if shutil.which("swiftc"):
    check("swiftc available", True)
else:
    open_item("swiftc NOT available on this Linux sandbox — Swift syntax cannot be compile-checked here",
              "macOS build will be the first compile")

print("\n== 12. Known gaps (recorded, not failures) ==")
open_item("macOS compile not done (no Xcode here)", "first compile is the GitHub Actions run")
open_item("MediaPlayer.framework link unproven (pbxproj link phase, SDK layout assumed)",
          "the macOS link step is the first real test")
open_item("NSAppleMusicUsageDescription stays in the plist (Lee's text; dashboard no longer asks)",
          "AppleMusicAdapter + requestMusicPermission retained but unwired")
open_item("MediaRemote follow reads any app's now-playing — sandboxed read on iOS 16.5 UNPROVEN",
          "device test decides (same caveat as the LyricWall follow mode)")
open_item("Widget refresh is system-throttled (per-line pre-scheduled timeline)",
          "near-live, not per-second; App itself is the live view")
open_item("LyricParser keeps empty lyric lines (Lee's parser verbatim)", "blank line shows blank in widget")
open_item("NetEase/QQ adapters are data-model only (Lee's files)",
          "they build a MusicTrack; lyric lookup is LRCLIB-only now — the previous build's NetEase/QQ network search is gone with LyricSearchService.swift, so the NetEase encryption question is moot")

print("\n== 13. v0.5 floating lyrics HUD (XExternalHUD mechanism, original TL host code) ==")
# 13a. new files exist
v05_files = [
    "HUD/LyricsHUDView.swift", "HUD/LyricsHUDController.swift",
    "HUD/LyricsHUDBridge.swift", "HUD/FloatingLyricsController.swift",
    "HUD/FloatingLyricsPanel.swift", "HUD/FloatingLyricsStyle.swift",
    "sources/TLLyricsIPC.h", "sources/TLLyricsIPC.mm",
    "sources/TLPrivate.h", "sources/TLHelper.h", "sources/TLHelper.mm",
    "sources/TLHUDWindow.h", "sources/TLHUDWindow.mm",
    "sources/TLHUDApplication.h", "sources/TLHUDApplication.mm",
    "sources/TLAppDelegate.h", "sources/TLAppDelegate.mm",
    "sources/main.mm",
    "App/TLAppRoot.swift",
    "TrollLyricsDesk/TrollLyricsDesk-Bridging-Header.h",
    "Makefile",
]
for rel in v05_files:
    check(f"v0.5 file exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))

# 13b. Lee's files byte-identical to the originals he sent
# (hidden_files/floating-overlay/ — the staging copies).
def _bytes(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return f.read()

for rel in ["HUD/LyricsHUDView.swift", "HUD/LyricsHUDBridge.swift",
            "HUD/FloatingLyricsController.swift", "HUD/FloatingLyricsPanel.swift",
            "HUD/FloatingLyricsStyle.swift"]:
    check(f"v0.5 Lee file byte-identical: {rel}",
          _bytes(rel) == _bytes("hidden_files/floating-overlay/" + os.path.basename(rel)))

# 13c. TLLyricsIPC: 1.0.5 replaced the 1.0.4 implementation with the audit
# patch (ChatGPT first-round review, hidden_files/audit-patch/Patch/).
# New design: App Group container JSON + notify_register_dispatch /
# notify_post + stopObserving. The 1.0.4 static-C-callback rewrite is gone;
# the patch files must be byte-identical to the patch Lee sent.
patch_ipc_h = read("hidden_files/audit-patch/Patch/sources/TLLyricsIPC.h")
patch_ipc_mm = read("hidden_files/audit-patch/Patch/sources/TLLyricsIPC.mm")
new_ipc_h = read("sources/TLLyricsIPC.h")
new_ipc = read("sources/TLLyricsIPC.mm")
check("v0.5 TLLyricsIPC.h byte-identical to audit patch",
      new_ipc_h == patch_ipc_h)
check("v0.5 TLLyricsIPC.mm byte-identical to audit patch",
      new_ipc == patch_ipc_mm)
check("v0.5 TLLyricsIPC: App Group container (group.com.hailong.TrollLyricsDesk)",
      "group.com.hailong.TrollLyricsDesk" in new_ipc and
      "containerURLForSecurityApplicationGroupIdentifier" in new_ipc)
check("v0.5 TLLyricsIPC: JSON in shared container (Library/Caches/TrollLyricsDesk/lyrics.json)",
      "Library/Caches/TrollLyricsDesk/lyrics.json" in new_ipc and
      "NSJSONSerialization" in new_ipc)
check("v0.5 TLLyricsIPC: notify_register_dispatch + notify_post, new name",
      "notify_register_dispatch" in new_ipc and
      "notify_post" in new_ipc and
      "com.hailong.TrollLyricsDesk.v05.lyrics.changed" in new_ipc)
check("v0.5 TLLyricsIPC: stopObserving present",
      "+ (void)stopObserving" in new_ipc and "notify_cancel" in new_ipc)
check("v0.5 TLLyricsIPC: publishLyrics returns BOOL",
      "+ (BOOL)publishLyrics" in new_ipc)
check("v0.5 TLLyricsIPC: no CFNotificationCenter observer, no XEPrivate, no TL_LYRICS_PATH",
      "CFNotificationCenterAddObserver" not in new_ipc and
      "XEPrivate" not in new_ipc and "TL_LYRICS_PATH" not in new_ipc)

# 13d. host code (ours) contains no upstream names at all — attribution lives
# only in BUILD_NOTES.md / README.md, never in code.
host_files = [
    "sources/TLPrivate.h", "sources/TLHelper.h", "sources/TLHelper.mm",
    "sources/TLHUDWindow.h", "sources/TLHUDWindow.mm",
    "sources/TLHUDApplication.h", "sources/TLHUDApplication.mm",
    "sources/TLAppDelegate.h", "sources/TLAppDelegate.mm",
    "sources/main.mm", "sources/TLLyricsIPC.mm",
    "HUD/LyricsHUDController.swift", "App/TLAppRoot.swift",
    "TrollLyricsDesk/TrollLyricsDesk-Bridging-Header.h",
]
for rel in host_files:
    t = read(rel)
    for bad in ["XEHUD", "XExternalHUD", "XEHelper", "XEPrivate"]:
        check(f"v0.5 no upstream name in {rel}: {bad}", bad not in t)

# 13e. TL_ naming + private-API declarations + TL_ constants
tlpriv = read("sources/TLPrivate.h")
for decl in ["GSInitialize", "GSEventInitialize", "GSEventPushRunLoopMode",
             "BKSDisplayServicesStart", "UIApplicationInitialize",
             "UIApplicationInstantiateSingleton", "_accessibilityInit",
             "__completeAndRunAsPlugin", "_installEventRunLoopSources:",
             "setEventFetcherSink:", "_contextId", "_initWithFrame:",
             "attached:(BOOL)attached",
             "SBSAccessibilityWindowHostingController",
             "registerWindowWithContextID:"]:
    check(f"v0.5 TLPrivate.h declares {decl}", decl in tlpriv)
for const, val in [("TL_NOTIFY_LYRICS", "com.trolllyricsdesk.v05/lyrics"),
                   ("TL_NOTIFY_DISMISS", "com.trolllyricsdesk.v05/dismiss"),
                   ("TL_LYRICS_PATH", "/var/mobile/Library/Preferences/com.trolllyricsdesk.v05.plist"),
                   ("TL_PID_PATH", "/var/mobile/Library/Caches/com.trolllyricsdesk.v05.pid")]:
    check(f"v0.5 TLPrivate.h {const} = {val}", val in tlpriv)
for rel, names in [("sources/TLHelper.h", ["@interface TLHelper", "startHUD", "stopHUD",
                                           "isHUDRunning", "writePidFile", "killHUDByPid"]),
                   ("sources/TLHUDWindow.h", ["@interface TLHUDWindow"]),
                   ("sources/TLHUDWindow.mm", ["_isSystemWindow", "_isWindowServerHostingManaged",
                                               "_usesWindowServerHitTesting", "_ignoresHitTest",
                                               "_initWithFrame:attached:"]),
                   ("sources/TLHUDApplication.h", ["@interface TLHUDApplication",
                                                   "@interface TLHUDAppDelegate"]),
                   ("sources/TLHUDApplication.mm", ["10000010.0",
                                                    "SBSAccessibilityWindowHostingController",
                                                    "registerWindowWithContextID",
                                                    "TL_NOTIFY_DISMISS",
                                                    "updateWithTitle:"]),
                   ("sources/TLAppDelegate.h", ["@interface TLAppDelegate"]),
                   ("sources/TLAppDelegate.mm", ["makeRootViewController"]),
                   ("sources/main.mm", ["UIApplicationMain", '"-exit"', '"-check"', '"-hud"',
                                        "TLAppDelegate", "TLHUDApplication", "TLHUDAppDelegate",
                                        "__completeAndRunAsPlugin",
                                        "SBSpringBoardDidLaunchNotification"]),
                   ("HUD/LyricsHUDController.swift", ["final class LyricsHUDController",
                                                      "LyricsHUDView", "updateLyrics",
                                                      "TLHelper.stopHUD",
                                                      "UIPinchGestureRecognizer", "handlePinch",
                                                      "0.65", "1.8"]),
                   ("App/TLAppRoot.swift", ["final class TLAppRoot", "makeRootViewController",
                                            "UIHostingController", "ContentView()",
                                            "keyWindowRootView"])]:
    t = read(rel)
    for n in names:
        check(f"v0.5 {rel} contains {n!r}", n in t)
check("v0.5 TLHelper.mm: never spawns as root (no persona override)",
      "posix_spawnattr_set_persona" not in read("sources/TLHelper.mm") and
      "XE_SPAWN_AS_ROOT" not in read("sources/TLHelper.mm"))
check("v0.5 main.mm: no ImGui / HID callback (touch goes through the event dispatcher)",
      "BKSHIDEventRegisterEventCallback" not in read("sources/main.mm") and
      "_enqueueHIDEvent" not in read("sources/main.mm") and
      "ImGuiHUD" not in read("sources/main.mm"))

# 13f. bridging header + pbxproj wiring
bh = read("TrollLyricsDesk/TrollLyricsDesk-Bridging-Header.h")
check("v0.5 bridging header imports TLLyricsIPC.h", '#import "TLLyricsIPC.h"' in bh)
check("v0.5 bridging header imports TLHelper.h", '#import "TLHelper.h"' in bh)
check("v0.5 pbxproj: SWIFT_OBJC_BRIDGING_HEADER set on App Debug + Release only",
      pbx.count('SWIFT_OBJC_BRIDGING_HEADER = "TrollLyricsDesk/TrollLyricsDesk-Bridging-Header.h"') == 2)
check("v0.5 pbxproj: HUD + sources groups present",
      'name = "HUD"' in pbx and 'name = "sources"' in pbx)
for rel in ["HUD/LyricsHUDView.swift", "HUD/LyricsHUDController.swift",
            "HUD/LyricsHUDBridge.swift", "HUD/FloatingLyricsController.swift",
            "HUD/FloatingLyricsPanel.swift", "HUD/FloatingLyricsStyle.swift",
            "App/TLAppRoot.swift"]:
    check(f"v0.5 pbxproj references {rel}", rel in _resolved)
for fn, ft in [("TLLyricsIPC.h", "sourcecode.c.h"), ("TLLyricsIPC.mm", "sourcecode.cpp.objcpp"),
               ("TLPrivate.h", "sourcecode.c.h"), ("TLHelper.h", "sourcecode.c.h"),
               ("TLHelper.mm", "sourcecode.cpp.objcpp"),
               ("TLHUDWindow.h", "sourcecode.c.h"), ("TLHUDWindow.mm", "sourcecode.cpp.objcpp"),
               ("TLHUDApplication.h", "sourcecode.c.h"),
               ("TLHUDApplication.mm", "sourcecode.cpp.objcpp"),
               ("TLAppDelegate.h", "sourcecode.c.h"), ("TLAppDelegate.mm", "sourcecode.cpp.objcpp"),
               ("main.mm", "sourcecode.cpp.objcpp")]:
    check(f'v0.5 pbxproj file ref: {fn} ({ft})',
          f'name = "{fn}"' in pbx and f'path = "{fn}"' in pbx)
_src_phase = re.search(
    r"4821909E9BF9E73E471FEA84 /\* PBXSourcesBuildPhase \*/ = \{(.*?)\n\t\t\};",
    pbx, re.S).group(1)
for bf in ["DCEFBED932F5EDBA023A6F24", "2192B4F9ADF4453D3056D557",
           "F2A1D151EDF8E3FDDFF7FC54", "87D27C29C2BAA88B2DCFD473",
           "77C1DC25EC74FFAAB999A9DE", "38C2596CB4C6E23EDC28E5F8",
           "EF1FCF9624888119C176E6FB", "868FF40D24AC83E5EE3936EE",
           "6281B91DC67C862834F92750", "DA9CEB4D39FAF88F6662A4C8",
           "8B185C7CA44B77909247FB4B", "65E1DB3CEE86C2A6E76B3523",
           "5536421856D0351EC5BD8EC1"]:
    check(f"v0.5 App Sources phase contains build file {bf}", bf in _src_phase)
_fw_phase = re.search(
    r"6EFAB1ECC0D092E20FE51FCD /\* PBXFrameworksBuildPhase \*/ = \{(.*?)\n\t\t\};",
    pbx, re.S).group(1)
for bf in ["DF071546DBC39458B9EC4DE6", "F11C4DB38DFC0D308712204A",
           "01C579C143BEA6A21453C8AE"]:
    check(f"v0.5 App Frameworks phase does NOT link {bf} (dynamic_lookup instead)",
          bf not in _fw_phase)
for fw in ["BackBoardServices", "GraphicsServices", "SpringBoardServices"]:
    check(f"v0.5 {fw}.framework file ref kept (unused, no link)",
          f"System/Library/PrivateFrameworks/{fw}.framework" in pbx)
check("v0.5 private frameworks not linked at all (no -weak_framework)",
      "BackBoardServices.framework in Frameworks" not in pbx and
      "GraphicsServices.framework in Frameworks" not in pbx and
      "SpringBoardServices.framework in Frameworks" not in pbx)
check("v0.5 OTHER_LDFLAGS has -undefined dynamic_lookup in both App configs",
      pbx.count('"-undefined",') == 2 and pbx.count('"dynamic_lookup",') == 2)
check("v0.5 FRAMEWORK_SEARCH_PATHS gone (dead path in iPhoneOS26.5.sdk)",
      "FRAMEWORK_SEARCH_PATHS" not in pbx)

# 13g. @main entry gone, main.mm is the only entry
check("v0.5 App/TrollLyricsDeskApp.swift deleted (@main entry gone)",
      not os.path.exists(os.path.join(ROOT, "App/TrollLyricsDeskApp.swift")))
check("v0.5 pbxproj: no TrollLyricsDeskApp reference left",
      "TrollLyricsDeskApp" not in pbx)
check("v0.5 no second @main entry (WidgetBundle @main is the widget's own, untouched)",
      read("App/TLAppRoot.swift").count("@main") == 0 and
      "struct TrollLyricsDeskApp" not in read("App/TLAppRoot.swift"))

# 13h. entitlements (App only; Widget untouched)
app_ent2 = plistlib.loads(open(os.path.join(
    ROOT, "TrollLyricsDesk/TrollLyricsDesk.entitlements"), "rb").read())
for key in ["com.apple.backboard.client",
            "com.apple.springboard.accessibility-window-hosting",
            "com.apple.assistivetouch.daemon",
            "com.apple.backboardd.launchapplications",
            "com.apple.springboard.launchapplications",
            "com.apple.private.security.no-sandbox",
            "platform-application",
            "get-task-allow",
            "task_for_pid-allow",
            "com.apple.private.security.task_for_pid-allow"]:
    check(f"v0.5 app entitlements: {key} = true", app_ent2.get(key) is True)
check("v0.5 app entitlements: mach-lookup.global-name = [AXSpringBoardServer]",
      app_ent2.get("com.apple.security.exception.mach-lookup.global-name")
      == ["com.apple.accessibility.AXSpringBoardServer"])
check("v0.5 app entitlements: mach-register.global-name = [com.trolllyricsdesk.v05.gsEvents]",
      app_ent2.get("com.apple.security.exception.mach-register.global-name")
      == ["com.trolllyricsdesk.v05.gsEvents"])
check("v0.5 app entitlements: mach-register.local-name = [com.trolllyricsdesk.v05]",
      app_ent2.get("com.apple.security.exception.mach-register.local-name")
      == ["com.trolllyricsdesk.v05"])
check("v0.5 app entitlements: old keys intact (App Groups + 2 mediaremote)",
      app_ent2.get("com.apple.security.application-groups") == [GROUP_ID] and
      app_ent2.get("com.apple.mediaremote.now-playing-read-access") is True and
      app_ent2.get("com.apple.mediaremote.full-now-playing-read-access") is True)
check("v0.5 Widget entitlements untouched (App Groups only)",
      plistlib.loads(open(os.path.join(
          ROOT, "TrollLyricsWidget/TrollLyricsWidget.entitlements"), "rb").read())
      == {"com.apple.security.application-groups": [GROUP_ID]})

# 13i. wiring: ContentView HUD section + coordinator publish hook
cv2 = read("App/ContentView.swift")
for s in ["歌词悬浮窗", "开启歌词悬浮窗", "关闭悬浮窗", "预览悬浮歌词",
          "TLHelper.startHUD", "TLHelper.stopHUD",
          "FloatingLyricsController.shared.show",
          "TLAppRoot.keyWindowRootView"]:
    check(f"v0.5 ContentView HUD section contains {s!r}", s in cv2)
pc2 = read("PlaybackEngine/PlaybackCoordinator.swift")
for s in ["lastHUDLyricIndex", "publishHUDLyrics", "LyricsHUDBridge.update",
          "LyricStore.currentElapsed", "lastIndex",
          "snapshot.lyrics[index - 1]", "snapshot.lyrics[index + 1]"]:
    check(f"v0.5 PlaybackCoordinator HUD hook contains {s!r}", s in pc2)

# 13j. Theos Makefile (second route, not CI)
mk = read("Makefile")
for g in ["sources/*.mm", "sources/*.m", "HUD/*.swift", "App/*.swift",
          "Lyrics/*.swift", "Core/*.swift", "PlaybackEngine/*.swift",
          "MusicProviders/*.swift", "TrollLyricsDesk/*.swift"]:
    check(f"v0.5 Makefile globs {g}", g in mk)
check("v0.5 Makefile: Theos is second route, not CI (header comment)",
      "尚未接 CI" in mk and "build.yml" in mk)
check("v0.5 Makefile: codesign entitlements = TrollLyricsDesk entitlements",
      "-STrollLyricsDesk/TrollLyricsDesk.entitlements" in mk)

# 13k. docs carry the attribution (code must not — see 13d)
bn2 = read("BUILD_NOTES.md")
check("v0.5 BUILD_NOTES.md: v0.5 section present", "v0.5" in bn2)
check("v0.5 BUILD_NOTES.md: TrollSpeed MIT attribution (Lessica)",
      "TrollSpeed" in bn2 and "MIT" in bn2 and "Lessica" in bn2)
check("v0.5 BUILD_NOTES.md: XExternalHUD credited, no code copied",
      "XExternalHUD" in bn2 and "没有复制" in bn2)
rm = read("README.md")
check("v0.5 README.md: v0.5 section + same attribution",
      "v0.5" in rm and "TrollSpeed" in rm and "XExternalHUD" in rm)

print("\n== 13l. v0.5 acceptance (Lee's table, section 7) — what ran vs what did not ==")
open_item("v0.5 Theos build: NOT passed in this run (see BUILD_NOTES.md v0.5)",
          "sandbox attempt ran; record the exact failing step there, do not mark passed")
open_item("v0.5 Xcode build: Release build = GitHub Actions (push+build need Lee's approval)",
          "not pushed, not built; the Actions run is the first real compile")
open_item("v0.5 HUD start / lyrics sync: needs macOS build + device",
          "startHUD/-hud spawn and the IPC path are code-level only until then")
open_item("v0.5 global display + drag: device-only (iPhone 13 Pro, Lee's item)",
          "window registration, TrollStore entitlements grant and post-hosting touch are unverified")
open_item("v0.5 lifecycle: close/restart/uninstall leaves no HUD (stopHUD dismiss + -exit fallback)",
          "mechanism in code; device confirms it")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens), "items (see above)")
sys.exit(1 if fails else 0)
