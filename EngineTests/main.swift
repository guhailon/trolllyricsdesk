import Foundation
let a = LyricParser.parse("[00:10.00][00:35.00]hello\n[offset:500]")
precondition(a.count == 2 && a[0].time == 9.5 && a[1].time == 34.5 && a.allSatisfy { $0.text == "hello" })
let b = LyricParser.parse("[offset:-1000]\n[00:00.1]a\n[00:01.123]b")
precondition(abs(b[0].time - 1.1) < 0.00001 && abs(b[1].time - 2.123) < 0.00001)
precondition(LyricParser.parse("[ar:test]\ninvalid").isEmpty)
print("LRC tests passed")
let enhanced = LyricParser.parse("[00:10.00]<00:10.00>hello <00:11.00>world\n[offset:500]")
precondition(enhanced.count == 1 && enhanced[0].text == "hello world")
precondition(enhanced[0].activeWord(at: 10.6)?.text == "world")
let legacy = try JSONDecoder().decode(LyricLine.self, from: Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"time\":1,\"text\":\"old\"}".utf8))
precondition(legacy.words == nil)
precondition(MusicPlatform.fromBundleIdentifier("com.tencent.qqmusic") == .qqMusic)
precondition(MusicPlatform.fromBundleIdentifier("com.netease.cloudmusic") == .netEase)
precondition(MusicPlatform.fromBundleIdentifier(nil) == .manual)
let track = MusicTrack(title: "test", artist: "test", platform: .manual)
let paused = PlaybackState(track: track, status: .paused, position: 30, duration: 60, observedAt: Date())
precondition(paused.estimatedPosition(at: ProcessInfo.processInfo.systemUptime + 5) == 30)
let playing = PlaybackState(track: track, status: .playing, position: 59, duration: 60, observedAt: Date())
precondition(playing.estimatedPosition(at: ProcessInfo.processInfo.systemUptime + 5) == 60)

// 2.0.6: lyricsfile (YAML) word-sync parser — same file list as CI
// (LyricParser.swift + LyricMatcher.swift + LRCLibClient.swift).
let yaml = """
lines:
- text: '你好世界'
  start_ms: 1000
  words:
  - text: '你'
    start_ms: 1000
    end_ms: 1200
  - text: '好'
    start_ms: 1200
    end_ms: 1400
  - text: '世界'
    start_ms: 1400
    end_ms: 1800
- text: '第二行'
  start_ms: 2000
  words: []
"""
let fileLines = LyricsFileParser.parse(yaml)
precondition(fileLines.count == 2 && fileLines[0].text == "你好世界" && fileLines[0].startMs == 1000)
precondition(fileLines[0].words.count == 3 && fileLines[0].words[1].text == "好" && fileLines[0].words[1].startMs == 1200)
precondition(fileLines[1].words.isEmpty)
precondition(LyricsFileParser.parse("not yaml at all\n::: [[[").isEmpty)
precondition(LyricsFileParser.parse("").isEmpty)
let rows = LyricParser.parse("[00:01.00]你好世界\n[00:02.00]第二行")
let merged = LyricsFileParser.mergingWordSync(into: rows, lyricsFile: yaml)
precondition(merged.count == 2 && merged[0].time == 1.0 && (merged[0].words?.count ?? 0) == 3)
precondition(abs((merged[0].words?[2].time ?? -1) - 1.4) < 0.00001 && merged[0].words?[2].text == "世界")
precondition(merged[1].words == nil)
print("Build 36 regression tests passed")
