import Foundation

/// MediaRemote 跟随：读系统正在放的歌（任何 App——QQ音乐/酷我/网易云/Apple Music）。
/// 机制和歌词墙的跟随同一路子（新写，没抄任何代码）：
/// MRMediaRemoteGetNowPlayingInfo 取一次快照 → 时间戳反推当前进度 →
/// 歌名清洗 → 协调器拿 track 去 LRCLIB 搜词。
/// 沙盒 App 在 iOS 16.5 上能不能读到，只有真机说了算；读不到就返回 nil，
/// 协调器会显示“没有检测到可读取的音乐”，不崩。
/// 思路学 Lyrication（只学思路，不抄代码，不用它的私有接口）。

/// 运行时 dlopen 拿函数指针，不链接 MediaRemote 框架——
/// 新 SDK 里没有它的 .tbd，直接链接会断。框架打不开时 symbol 就是 nil，
/// 跟读不到一样返回 nil，不崩。
private typealias MRMediaRemoteGetNowPlayingInfoFn = @convention(c) (
    DispatchQueue,
    @escaping (CFDictionary?) -> Void
) -> Void

/// 1.0.5 诊断（第 1 项）：MRMediaRemoteRegisterForNowPlayingNotifications
/// 的真签名——注册成功不代表回调会来，只有回调真触发才算通道通。
/// 只记日志：注册成败记一次，回调触发记第一次＋每 50 次记一次，
/// info 有无内容只在 nil／非 nil 切换时记，不刷屏。
private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFn = @convention(c) (
    DispatchQueue,
    @escaping (CFNotificationCenter?, UnsafeRawPointer?, CFString?, UnsafeRawPointer?, CFDictionary?) -> Void
) -> Void

@MainActor
final class MediaRemoteAdapter: PlaybackAdapter {

let platform: MusicPlatform = .manual

private let bridge = MediaRemoteBridge()

private var cachedInfo: [String: Any]?
private var cachedAt: Date?
private var fetching = false

/// 1.0.5（ChatGPT 审查 bug 1，P0）：请求超时／编号／缓存过期。
/// fetching 是防重入锁，但私有接口没回回调时它会一直卡 true，后续检测全停——
/// 超过 fetchTimeout 没回就自动复位，下一次 poll 重新发请求。
/// 请求编号防旧回调：超时后重发的请求在途时，旧请求的迟到回调直接丢弃，
/// 不覆盖新缓存、不清新请求的 fetching。
/// 缓存硬过期：快照超过 cacheHardExpiry 再也不采用（返回 nil），
/// 防止卡死的旧快照无限期冒充当前播放；正常流程里回调几毫秒就到，
/// 硬过期只是兜底，日常不触发。

/// 1.0.5 诊断计数（只为日志节流，不影响逻辑；记录集中在 MediaRemoteDiagnostics）。
private var notificationRegistered = false

init() {
    registerForNowPlayingNotifications()
}

/// 只注册一次：符号找不到就记失败原因；注册了也不代表回调会来，
/// 回调真触发时（下面计数里）才会再记一行。
private func registerForNowPlayingNotifications() {
    guard !notificationRegistered else { return }
    notificationRegistered = true
    guard let sym = bridge.symbol(MediaRemoteSymbols.registerForNowPlayingNotifications) else {
        MediaRemoteDiagnostics.recordRegistration(success: false)
        return
    }
    let register = unsafeBitCast(sym, to: MRMediaRemoteRegisterForNowPlayingNotificationsFn.self)
    register(DispatchQueue.main) { _, _, name, _, _ in
        Task { @MainActor in
            MediaRemoteDiagnostics.recordNotificationFire(name: name as String?)
        }
    }
    MediaRemoteDiagnostics.recordRegistration(success: true)
}

/// 缓存保鲜 0.3 秒：换歌/开始播放要「即播即显」，2 秒缓存会让歌词慢半拍。
/// MediaRemote 是本机 XPC，读取很快，0.3 秒足够去重且不会拖慢检测。
private let cacheLifetime: TimeInterval = 0.3

/// 请求超时 2 秒：超过这个时间没回回调，fetching 自动复位重发。
/// 缓存硬过期 3 秒：快照超过 3 秒没被新回调替换就再也不采用。
/// 3 秒这个数与 ChatGPT「1.0.1 Engine Fix」ZIP 里核实的 3 秒最大缓存龄一致
/// （那包的 MediaRemoteAdapter 也是 2 秒超时＋requestID＋3 秒缓存龄）。
private let fetchTimeout: TimeInterval = 2.0
private let cacheHardExpiry: TimeInterval = 3.0
private var fetchStartedAt: Date?
private var requestID = 0

func currentState() -> PlaybackState? {

refreshIfNeeded()

guard let info = cachedInfo else {
return nil
}

// 1.0.5（ChatGPT 审查 bug 1）：过期缓存不采用——
// 快照超过硬过期还没被新回调替换，说明请求通道卡死了，
// 宁可返回 nil（显示「没有检测到」），也不拿旧快照冒充当前播放。
// 正常流程回调几毫秒就到，这行日常不触发。
if let cachedAt, Date().timeIntervalSince(cachedAt) > cacheHardExpiry {
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

// 时间戳反推当前进度（ChatGPT 审查 bug 1 修正：旧公式没乘 rate，
// 暂停后时间戳不刷新，算出来的进度还在涨）。
// rate 是当前播放速率：播放中 ≈1，暂停 =0；暂停时 estimated 停在 elapsed 不再涨。
// duration 为 0 或缺失时不 clamp。
let delta = timestamp.map { max(0, Date().timeIntervalSince($0)) } ?? 0
let estimated = max(0, elapsed + delta * rate)
let position: TimeInterval = duration.map { $0 > 0 ? min(estimated, $0) : estimated } ?? estimated

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

// 1.0.5（ChatGPT 审查 bug 1）：请求超时自动复位——
// 上一次请求超过 fetchTimeout 没回回调，fetching 卡住了就放开，
// 下一次 poll 重新发请求；迟到的旧回调靠请求编号丢弃。
if fetching, let startedAt = fetchStartedAt,
   Date().timeIntervalSince(startedAt) > fetchTimeout {
    MediaRemoteDiagnostics.recordFetchTimeout(requestID: requestID)
    fetching = false
    fetchStartedAt = nil
}

if fetching {
return
}

if let cachedAt,
Date().timeIntervalSince(cachedAt) < cacheLifetime {
return
}

requestID += 1
let id = requestID
fetchStartedAt = Date()
fetching = true

guard let sym = bridge.symbol(MediaRemoteSymbols.getNowPlayingInfo) else {
    fetching = false
    fetchStartedAt = nil
    return
}
let getNowPlayingInfo = unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingInfoFn.self)
getNowPlayingInfo(
DispatchQueue.global(qos: .background)
) { [weak self] info in

Task { @MainActor in
guard let self else { return}

// 旧请求的迟到回调：编号对不上就丢弃，不覆盖新缓存、不清新请求的 fetching。
guard id == self.requestID else { return }

let title = (info as? [String: Any])?["kMRMediaRemoteNowPlayingInfoTitle"] as? String
MediaRemoteDiagnostics.recordInfoCallback(isNil: info == nil, title: title)

self.cachedInfo = info as? [String: Any]
self.cachedAt = Date()
self.fetching = false
self.fetchStartedAt = nil
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
