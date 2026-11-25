#!/usr/bin/env python3
"""Verify TrollLyricsDesk 1.0.0 project: structure, ids, Lee's files verbatim,
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
    "App/TrollLyricsDeskApp.swift",
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
    "App/TrollLyricsDeskApp.swift": ["@main", "struct TrollLyricsDeskApp: App",
                                     "ContentView()"],
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
}
for rel, ms in markers.items():
    text = read(rel)
    for m in ms:
        check(f"{rel} contains {m[:48]!r}", m in text)

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
    check(f"{rel}: version 1.0.0", pl.get("CFBundleShortVersionString") == "1.0.0")
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
for f in ["App/TrollLyricsDeskApp.swift", "App/ContentView.swift",
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
check("workflow: ldid sign app + widget", wf.count("ldid -S") >= 2)
check("workflow: package IPA", "TrollLyricsDesk-1.0.0.ipa" in wf)

print("\n== 6. No built-in songs / no activation ==")
all_swift = ""
for dirpath, _, filenames in os.walk(ROOT):
    for fn in filenames:
        if fn.endswith(".swift"):
            all_swift += open(os.path.join(dirpath, fn), encoding="utf-8").read() + "\n"
for bad in ["激活", "activation", "LW-", "codes-", "licenseCode", "activate("]:
    check(f"no activation string {bad!r}", bad not in all_swift)
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
# MediaRemote no longer directly linked (Lee 10:44: dlopen via Core/MediaRemoteBridge)
check("pbxproj: MediaRemote NOT directly linked (dlopen instead)",
      "PrivateFrameworks" not in pbx and '"MediaRemote",' not in pbx)

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

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens), "items (see above)")
sys.exit(1 if fails else 0)
