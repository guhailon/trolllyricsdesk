import Foundation

/// MediaRemote 诊断集中记录（1.0.5 第 1 项＋皇上树的 Diagnostics 层）。
///
/// Bridge（dlopen／dlsym）与 Adapter（回调注册／触发）都调这里记日志，
/// 日志行格式固定不变（自检按这些行核）；同时留一份内存里的最新结论，
/// 供诊断页（DiagnosticsView）与能力检测（RuntimeCapabilities）读——
/// 真机上「读不读得到」以这里的记录为准，不以 entitlements 声明为准。
final class MediaRemoteDiagnostics {

    private static var loggedSymbols = Set<String>()

    /// dlopen 结果（nil = 还没试过）。
    static private(set) var dlopenOK: Bool?
    /// 各符号 dlsym 结果（只记第一次结论）。
    static private(set) var symbolResults: [String: Bool] = [:]
    /// 回调注册是否已调用。
    static private(set) var registrationCalled = false
    static private(set) var registrationOK = false
    /// NowPlaying 通知回调触发次数（1.0.6：注册只收队列，系统不回调块，
    /// 所以这个计数正常是 0——0 不是故障，是注册方式的事实；变化通知
    /// 不走这条路，轮询是主数据源）。
    static private(set) var notificationFireCount = 0
    /// GetNowPlayingInfo 调用次数与回调次数（第 4 项：调用／回调／info 内容
    /// 三者分开记——1.0.5 只记回调，调用发没发出去、回调回没回来分不清）。
    static private(set) var requestCount = 0
    /// GetNowPlayingInfo 回调触发次数与最近一次 info 有无。
    static private(set) var infoCallbackCount = 0
    static private(set) var lastInfoWasNil: Bool?
    static private(set) var lastInfoTitle: String?
    /// 播放状态查询（MRMediaRemoteGetNowPlayingApplicationIsPlaying）：
    /// 最近一次结果（nil = 还没查到／符号不可用）。info=nil 时它是
    /// 区分「没放歌」与「放着歌还读不到（P0）」的唯一直接证据。
    static private(set) var lastIsPlaying: Bool?
    static private(set) var isPlayingQueryCount = 0

    static func recordDlopen(success: Bool, path: String, reason: String?) {
        dlopenOK = success
        if success {
            LyricLogger.log("诊断1.0.6 MediaRemote：dlopen 成功（\(path)）")
        } else {
            LyricLogger.log("诊断1.0.6 MediaRemote：dlopen 失败：\(reason ?? "无错误信息")")
        }
    }

    static func recordDlsym(name: String, success: Bool, noHandle: Bool, reason: String?) {
        guard !loggedSymbols.contains(name) else { return }
        loggedSymbols.insert(name)
        symbolResults[name] = success
        if success {
            LyricLogger.log("诊断1.0.6 MediaRemote：dlsym \(name) 成功")
        } else if noHandle {
            LyricLogger.log("诊断1.0.6 MediaRemote：dlsym \(name) 失败：框架未打开（dlopen 已失败）")
        } else {
            LyricLogger.log("诊断1.0.6 MediaRemote：dlsym \(name) 失败：\(reason ?? "无错误信息")")
        }
    }

    static func recordRegistration(success: Bool) {
        registrationCalled = true
        registrationOK = success
        if success {
            LyricLogger.log("诊断1.0.6 MediaRemote：回调注册已调用（等回调触发才算通道通）")
        } else {
            LyricLogger.log("诊断1.0.6 MediaRemote：回调注册失败：MRMediaRemoteRegisterForNowPlayingNotifications 符号缺失")
        }
    }

    static func recordNotificationFire(name: String?) {
        notificationFireCount += 1
        if notificationFireCount == 1 || notificationFireCount % 50 == 0 {
            LyricLogger.log("诊断1.0.6 MediaRemote：NowPlaying 通知回调已触发（第 \(notificationFireCount) 次，name=\(name ?? "?")）")
        }
    }

    static func recordInfoCallback(isNil: Bool, title: String?) {
        infoCallbackCount += 1
        if infoCallbackCount == 1 || lastInfoWasNil != isNil || infoCallbackCount % 50 == 0 {
            if isNil {
                LyricLogger.log("诊断1.0.6 MediaRemote：GetNowPlayingInfo 回调已触发（第 \(infoCallbackCount) 次），info=nil（无播放器／读不到）")
            } else {
                LyricLogger.log("诊断1.0.6 MediaRemote：GetNowPlayingInfo 回调已触发（第 \(infoCallbackCount) 次），info 有内容（歌名=\(title ?? "?")）")
            }
        }
        lastInfoWasNil = isNil
        lastInfoTitle = isNil ? nil : title
        // 1.0.6 第 4 项：标题正常回来时，「解析失败」标记清掉（缺标题才由 Adapter 另记）。
        if !isNil, let title, !title.isEmpty {
            lastInfoMissingTitle = false
        }
    }

    /// 请求超时自动复位（ChatGPT 审查 bug 1）：上一次请求超过 2 秒没回回调，
    /// fetching 放开、下一次 poll 重发。第一次记一行，之后每 10 次记一行，
    /// 接口彻底不通时不至于每 2 秒刷一条日志。
    /// （Engine Fix 包里超时是 Task.sleep 看门狗，不记日志；1.0.5 诊断层在这里补记。
    /// 包的 requestID 是 UUID，日志里不印编号，只记次数。）
    static private(set) var fetchTimeoutCount = 0
    static func recordFetchTimeout() {
        fetchTimeoutCount += 1
        if fetchTimeoutCount == 1 || fetchTimeoutCount % 10 == 0 {
            LyricLogger.log("诊断1.0.6 MediaRemote：GetNowPlayingInfo 请求超时（2 秒无回调，第 \(fetchTimeoutCount) 次），fetching 已复位，下次 poll 重发")
        }
    }

    /// 1.0.6 第 4 项：发出一次 GetNowPlayingInfo 调用即记（调用次数／回调次数分开记）。
    /// 不逐次记日志（poll 频繁调用会刷屏），次数进 summaryLine。
    static func recordRequest() {
        requestCount += 1
    }

    /// 1.0.6 第 4 项：发出一次 isPlaying 查询即记（节流后才调，见 Adapter）。
    static func recordIsPlayingQuery() {
        isPlayingQueryCount += 1
    }

    /// 1.0.6 第 4 项 P0 判别器结果：playing 为 nil 表示符号缺失、查不到。
    /// 首次／变化时记一行；放着歌（YES）且最近 info=nil 时另记一行 P0 明确结论。
    static func recordIsPlaying(_ playing: Bool?) {
        let changed = lastIsPlaying != playing
        lastIsPlaying = playing
        guard let playing else {
            LyricLogger.log("诊断1.0.6 MediaRemote：isPlaying 查询不可用（符号缺失，判不准放没放歌）")
            return
        }
        if changed {
            LyricLogger.log("诊断1.0.6 MediaRemote：isPlaying 查询结果：\(playing ? "播放中" : "未播放")（第 \(isPlayingQueryCount) 次查询）")
        }
        if playing && lastInfoWasNil == true {
            LyricLogger.log("诊断1.0.6 MediaRemote：P0——放着歌还读不到（isPlaying=YES，info=nil；见 23:24 LC 机 QQ 音乐重测）")
        }
    }

    /// 字典非空但缺有效标题的次数（第 4 项「解析失败」的证据；由 Adapter 在
    /// 字典非空缺标题时调；标题正常回来时 recordInfoCallback 把它清掉）。
    static private(set) var infoMissingTitleCount = 0
    static private(set) var lastInfoMissingTitle = false
    static func recordMissingTitle() {
        infoMissingTitleCount += 1
        lastInfoMissingTitle = true
    }

    /// 诊断页用的一句话结论（没测过就写「未测」，不编通过）。
    /// 1.0.6 第 4 项：带环境标签（当前在哪台环境）与调用／回调次数，
    /// 状态由 readStatus 判（ok／P0／可能没放歌／疑似 P0／超时／受限／解析失败）。
    static var summaryLine: String {
        let env = RuntimeCapabilities.environmentTag
        let counts = "调用 \(requestCount) 次／回调 \(infoCallbackCount) 次"
        return "MediaRemote：\(readStatus)（\(env)；\(counts)）"
    }

    /// 1.0.6 第 4 项：状态判读——
    /// ok：最近一次 info 有内容（读得到）；
    /// P0 放着歌还读不到：isPlaying=YES 且 info=nil（23:24 在 LC 机上坐实）；
    /// 可能没放歌：isPlaying=NO 且 info=nil；
    /// 疑似 P0：isPlaying 未知且 info=nil（符号不可用，判不准）；
    /// 超时：发过调用、从未回调且有过超时复位；
    /// 受限：框架打不开／符号缺失；
    /// 解析失败：info 非空但缺有效标题；
    /// 未测／等回调：还没到判的时候。
    static var readStatus: String {
        guard let dlopenOK else { return "未测（App 启动后第一次跟随才会测）" }
        if !dlopenOK { return "受限（框架打不开，读不到任何播放器）" }
        let missing = symbolResults.filter { !$0.value }.map(\.key)
        if !missing.isEmpty { return "受限（符号缺失：\(missing.joined(separator: "、"))）" }
        if lastInfoWasNil == false {
            if lastInfoMissingTitle { return "解析失败（字典非空但缺少有效标题）" }
            return "ok（最近读到「\(lastInfoTitle ?? "?")」）"
        }
        if lastInfoWasNil == true {
            if lastIsPlaying == true { return "P0：放着歌还读不到（isPlaying=YES，info=nil）" }
            if lastIsPlaying == false { return "可能没放歌（isPlaying=NO，info=nil）" }
            return "疑似 P0（isPlaying 未知，info=nil）"
        }
        if requestCount > 0 && infoCallbackCount == 0 {
            if fetchTimeoutCount > 0 { return "超时（调用发出 \(requestCount) 次，从未回调）" }
            return "等回调（调用发出 \(requestCount) 次，回调还没回来）"
        }
        return "未测（回调还没触发过）"
    }
}
