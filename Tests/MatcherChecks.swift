import Foundation
@main struct MatcherChecks {
 static func main() {
  let track = MusicTrack(title: "晴天", artist: "周杰伦", duration: 269, platform: .manual)
  func record(_ title: String, _ artist: String, _ duration: Double, _ instrumental: Bool = false) -> LRCLyricsRecord {
   LRCLyricsRecord(id: 1, trackName: title, artistName: artist, albumName: nil, duration: duration, instrumental: instrumental, plainLyrics: nil, syncedLyrics: "[00:01]test")
  }
  precondition(LyricMatcher.bestMatch(records: [record("晴天", "周杰伦", 269)], track: track) != nil)
  precondition(LyricMatcher.bestMatch(records: [record("雨天", "周杰伦", 269)], track: track) == nil)
  precondition(LyricMatcher.bestMatch(records: [record("晴天", "其他歌手", 269)], track: track) == nil)
  precondition(LyricMatcher.bestMatch(records: [record("晴天", "周杰伦", 300)], track: track) == nil)
  precondition(LyricMatcher.bestMatch(records: [record("晴天", "周杰伦", 269, true)], track: track) == nil)
  print("Matcher checks passed")
 }
}
