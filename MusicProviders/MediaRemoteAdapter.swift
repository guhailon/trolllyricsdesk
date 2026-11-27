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
/// （Engine Fix 包基于底子，没有这段诊断；并入时从 1.0.5 诊断版补回。）
private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFn = @convention(c) (
    DispatchQueue
) -> Void

/// 1.0.6 第 4 项 P0 判别器：MRMediaRemoteGetNowPlayingApplicationIsPlaying——
/// info==nil 时问系统「到底有没有 App 在放歌」，把「没放歌」和「放着歌还读不到」分开。
/// 假定签名 (dispatch_queue_t, completion(Boolean))：completion 亦为 block
/// （与 GetNowPlayingInfo 同族；1.0.5 的假回调教训——回调签名必须按 block 声明，
/// 否则系统根本不调它）。符号缺失／调用失败时回退，不伪造；真机验签名。
/// Boolean 用 UInt8 接（!= 0 为播放中）。
private typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFn = @convention(c) (
    DispatchQueue,
    @convention(block) (UInt8) -> Void
) -> Void

@MainActor
final class MediaRemoteAdapter: PlaybackAdapter {

let platform: MusicPlatform = .manual

private let bridge = MediaRemoteBridge()

private var cachedInfo: [String: Any]?
private var cachedAt: Date?
private var fetching = false
private var requestID = UUID()
private let maxCacheAge: TimeInterval = 3

/// 1.0.5 诊断计数（只为日志节流，不影响逻辑；记录集中在 MediaRemoteDiagnostics）。
private var notificationRegistered = false

/// 1.0.6 第 4 项：isPlaying 查询节流（上次查询时间；info==nil 时 5 秒内不重复问）。
private var lastIsPlayingQueryAt: Date?

init() {
    registerForNowPlayingNotifications()
}

/// 只注册一次：符号找不到就记失败原因；注册了也不代表回调会来，
/// 回调真触发时（下面计数里）才会再记一行。
/// （Engine Fix 包基于底子，没有这段诊断；并入时从 1.0.5 诊断版补回。）
private func registerForNowPlayingNotifications() {
    guard !notificationRegistered else { return }
    notificationRegistered = true
    guard let sym = bridge.symbol(MediaRemoteSymbols.registerForNowPlayingNotifications) else {
        MediaRemoteDiagnostics.recordRegistration(success: false)
        return
    }
    let register = unsafeBitCast(sym, to: MRMediaRemoteRegisterForNowPlayingNotificationsFn.self)
    register(DispatchQueue.main)
    // 注册接口仅接收队列；轮询仍为主数据源，不伪造通知回调。
    MediaRemoteDiagnostics.recordRegistration(success: true)
}

/// 1.0.6 第 4 项 P0 判别器：info==nil 时问系统有没有 App 在放歌（5 秒节流）。
/// 结果记 MediaRemoteDiagnostics.recordIsPlaying(_:)；readStatus 由此区分
/// 「可能没放歌（isPlaying=NO）」和「P0：放着歌还读不到（isPlaying=YES＋info=nil）」。
/// 符号缺失时记一次「isPlaying 查询不可用」，不伪造、不崩。
private func queryIsPlayingIfNeeded() {
    if let last = lastIsPlayingQueryAt, Date().timeIntervalSince(last) < 5 { return }
    lastIsPlayingQueryAt = Date()
    // build 22 决定性实验：只禁 isPlaying 探针——不调 dlsym 到的符号。
    // 探针代码（typealias／dlsym／unsafeBitCast／query 调用）一字不动留着，以后能恢复。
    // build 24：日志里的 build 号走 LyricStore.versionTag 插值，不再写死
    // build 22 字串（build 23 的日志写 build 22 就是写死字串的教训）。
    LyricLogger.log("诊断1.0.6 MediaRemote：\(LyricStore.versionTag)：isPlaying 探针已禁用")
    return
    guard let sym = bridge.symbol(MediaRemoteSymbols.getNowPlayingApplicationIsPlaying) else {
        MediaRemoteDiagnostics.recordIsPlaying(nil)
        return
    }
    MediaRemoteDiagnostics.recordIsPlayingQuery()
    let query = unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFn.self)
    query(DispatchQueue.main) { playing in
        Task { @MainActor in
            MediaRemoteDiagnostics.recordIsPlaying(playing != 0)
        }
    }
}

/// 缓存保鲜 0.3 秒：换歌/开始播放要「即播即显」，2 秒缓存会让歌词慢半拍。
/// MediaRemote 是本机 XPC，读取很快，0.3 秒足够去重且不会拖慢检测。
private let cacheLifetime: TimeInterval = 0.3

func currentState() -> PlaybackState? {

refreshIfNeeded()

guard let info = cachedInfo, let cachedAt,
Date().timeIntervalSince(cachedAt) <= maxCacheAge else {
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
let delta = timestamp.map { max(0, Date().timeIntervalSince($0)) } ?? 0
let estimated = elapsed + delta * rate
let safePosition = estimated.isFinite ? max(0, estimated) : 0
let position = duration.map { $0.isFinite && $0 > 0 ? min(safePosition, $0) : safePosition } ?? safePosition

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
let id = UUID()
requestID = id

guard let sym = bridge.symbol(MediaRemoteSymbols.getNowPlayingInfo) else {
    fetching = false
    return
}
Task { @MainActor [weak self] in
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    guard let self, self.fetching, self.requestID == id else { return }
    // 1.0.5 诊断：第 1 项的超时日志（包里没有，1.0.5 诊断层补记；第 1 次＋每 10 次）。
    MediaRemoteDiagnostics.recordFetchTimeout()
    self.fetching = false
    self.requestID = UUID()
}
let getNowPlayingInfo = unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingInfoFn.self)
// 1.0.6 第 4 项：发出调用即记一次（调用次数／回调次数／info 内容三者分开记）。
MediaRemoteDiagnostics.recordRequest()
getNowPlayingInfo(
DispatchQueue.main
) { [weak self] info in

Task { @MainActor in
guard let self, self.requestID == id, self.fetching else { return }

let title = (info as? [String: Any])?["kMRMediaRemoteNowPlayingInfoTitle"] as? String
MediaRemoteDiagnostics.recordInfoCallback(isNil: info == nil, title: title)
if info == nil {
    // 1.0.6 第 4 项 P0：回调回来了但没数据——问系统到底有没有 App 在放歌。
    // （23:24 坐实：LC 机上 QQ 音乐在播，info 仍 nil。）
    // build 23：@escaping 闭包须显式 self.（编译强制；行为与原来隐式 self 相同）。
    self.queryIsPlayingIfNeeded()
}
if info != nil && title?.isEmpty != false {
    // 1.0.6 第 4 项：字典非空缺标题——「解析失败」的证据（计数进 diagnostics）。
    MediaRemoteDiagnostics.recordMissingTitle()
    if MediaRemoteDiagnostics.infoCallbackCount == 1 || MediaRemoteDiagnostics.infoCallbackCount % 50 == 0 {
        LyricLogger.log("MediaRemote：字典非空但缺少有效标题，检查字段解析")
    }
}

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
