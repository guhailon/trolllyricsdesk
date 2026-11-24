import Foundation

/// MediaRemote 跟随：读系统正在放的歌（任何 App——QQ音乐/酷我/网易云/Apple Music）。
/// 机制和歌词墙的跟随同一路子（新写，没抄任何代码）：
/// MRMediaRemoteGetNowPlayingInfo 取一次快照 → 时间戳反推当前进度 →
/// 歌名清洗 → 协调器拿 track 去 LRCLIB 搜词。
/// 沙盒 App 在 iOS 16.5 上能不能读到，只有真机说了算；读不到就返回 nil，
/// 协调器会显示“没有检测到可读取的音乐”，不崩。
/// 思路学 Lyrication（只学思路，不抄代码，不用它的私有接口）。

@_silgen_name("MRMediaRemoteGetNowPlayingInfo")
func MRMediaRemoteGetNowPlayingInfo(
_ queue: DispatchQueue,
_ completion: @escaping (CFDictionary?) -> Void
)

@MainActor
final class MediaRemoteAdapter: PlaybackAdapter {

let platform: MusicPlatform = .manual

private var cachedInfo: [String: Any]?
private var cachedAt: Date?
private var fetching = false

/// 缓存最长保鲜 2 秒；协调器每秒问一次，最多 2 秒就能跟上换歌。
private let cacheLifetime: TimeInterval = 2.0

func currentState() -> PlaybackState? {

refreshIfNeeded()

guard let info = cachedInfo else {
return nil
}

guard
let rawTitle = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
!rawTitle.trimmingCharacters(in: .whitespaces).isEmpty
else {
return nil
}

let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
?? "未知歌手"

let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
?? ""

let duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double

let elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double
?? 0

let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date

let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double
?? 0

// 时间戳反推当前进度（和歌词墙跟随同一公式）。
let position: TimeInterval
if let timestamp {
position = max(
0,
Date().timeIntervalSince(timestamp) + elapsed
)
} else {
position = max(0, elapsed)
}

let status: PlaybackStatus =
rate == 0 ? .paused : .playing

// 歌名先清洗再查词（面板上显示的也是清洗后的名字）。
let title = Self.cleanTitle(rawTitle)

let track = MusicTrack(
id: "manual|\(title)|\(artist)".lowercased(),
title: title,
artist: artist,
album: album,
duration: duration,
platform: .manual
)

return PlaybackState(
track: track,
status: status,
position: position,
duration: duration,
observedAt: Date()
)
}

private func refreshIfNeeded() {

if fetching {
return
}

if let cachedAt,
Date().timeIntervalSince(cachedAt) < cacheLifetime {
return
}

fetching = true

MRMediaRemoteGetNowPlayingInfo(
DispatchQueue.global(qos: .background)
) { [weak self] info in

Task { @MainActor in
guard let self else { return}

self.cachedInfo = info as? [String: Any]
self.cachedAt = Date()
self.fetching = false
}
}
}

/// 剥掉歌名里的后缀和标记词，再去 LRCLIB 查：
/// （Live）/（伴奏）/【翻唱】/【】/「」/♪/♫/LYRICS/CLEAN/NMV/AMV/Nightcore。
/// 清空了就用原名，绝不返回空歌名。
static func cleanTitle(_ raw: String) -> String {

var title = raw

// 符号直接去掉。
title = title
.replacingOccurrences(of: "♪", with: "")
.replacingOccurrences(of: "♫", with: "")

// 括号后缀一对一对剥，直到剥不动。
// 【】/「」里的内容基本是标记，直接剥；
// （）/() 只剥内容带标记词的那种（Live/伴奏/翻唱/Official/MV/Lyrics/…），
// 免得把歌名本身的一部分误剥了。
let markers = [
"live", "伴奏", "翻唱", "official", "mv",
"lyrics", "clean", "nmv", "amv", "nightcore",
"remix", "cover", "演唱", "现场",
]
let bracketPattern = #"\s*[\(\[\uFF08\u3010\u300C][^\)\]\uFF09\u3011\u300D]*[\)\]\uFF09\u3011\u300D]\s*$"#

while true {

guard
let range = title.range(
of: bracketPattern,
options: .regularExpression
)
else {
break
}

let group = String(title[range])

let inner = group
.trimmingCharacters(in: .whitespaces)
.dropFirst()
.dropLast()
let innerText = String(inner).lowercased()

let isSquare = group.contains("\u{3010}")
|| group.contains("\u{300C}")
let isMarker = markers.contains { innerText.contains($0)}

guard isSquare || isMarker else {
break
}

title = String(title[..<range.lowerBound])
.trimmingCharacters(in: .whitespaces)
}

// 末尾单独的标记词（空格或横杠隔开的）也剥掉。
let wordPattern = #"(?i)\s*[\-\u2013\u2014]?\s*(lyrics|clean|nmv|amv|nightcore|live|\u4F34\u594F)\s*$"#
while let range = title.range(
of: wordPattern,
options: .regularExpression
) {
title = String(title[..<range.lowerBound])
.trimmingCharacters(in: .whitespaces)
}

// 多余空格压成一个。
title = title
.components(separatedBy: .whitespaces)
.filter {!$0.isEmpty}
.joined(separator: " ")

return title.isEmpty ? raw : title
}
}
