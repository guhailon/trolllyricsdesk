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
    /// NowPlaying 通知回调触发次数。
    static private(set) var notificationFireCount = 0
    /// GetNowPlayingInfo 回调触发次数与最近一次 info 有无。
    static private(set) var infoCallbackCount = 0
    static private(set) var lastInfoWasNil: Bool?
    static private(set) var lastInfoTitle: String?

    static func recordDlopen(success: Bool, path: String, reason: String?) {
        dlopenOK = success
        if success {
            LyricLogger.log("诊断1.0.5 MediaRemote：dlopen 成功（\(path)）")
        } else {
            LyricLogger.log("诊断1.0.5 MediaRemote：dlopen 失败：\(reason ?? "无错误信息")")
        }
    }

    static func recordDlsym(name: String, success: Bool, noHandle: Bool, reason: String?) {
        guard !loggedSymbols.contains(name) else { return }
        loggedSymbols.insert(name)
        symbolResults[name] = success
        if success {
            LyricLogger.log("诊断1.0.5 MediaRemote：dlsym \(name) 成功")
        } else if noHandle {
            LyricLogger.log("诊断1.0.5 MediaRemote：dlsym \(name) 失败：框架未打开（dlopen 已失败）")
        } else {
            LyricLogger.log("诊断1.0.5 MediaRemote：dlsym \(name) 失败：\(reason ?? "无错误信息")")
        }
    }

    static func recordRegistration(success: Bool) {
        registrationCalled = true
        registrationOK = success
        if success {
            LyricLogger.log("诊断1.0.5 MediaRemote：回调注册已调用（等回调触发才算通道通）")
        } else {
            LyricLogger.log("诊断1.0.5 MediaRemote：回调注册失败：MRMediaRemoteRegisterForNowPlayingNotifications 符号缺失")
        }
    }

    static func recordNotificationFire(name: String?) {
        notificationFireCount += 1
        if notificationFireCount == 1 || notificationFireCount % 50 == 0 {
            LyricLogger.log("诊断1.0.5 MediaRemote：NowPlaying 通知回调已触发（第 \(notificationFireCount) 次，name=\(name ?? "?")）")
        }
    }

    static func recordInfoCallback(isNil: Bool, title: String?) {
        infoCallbackCount += 1
        if infoCallbackCount == 1 || lastInfoWasNil != isNil {
            if isNil {
                LyricLogger.log("诊断1.0.5 MediaRemote：GetNowPlayingInfo 回调已触发（第 \(infoCallbackCount) 次），info=nil（无播放器／读不到）")
            } else {
                LyricLogger.log("诊断1.0.5 MediaRemote：GetNowPlayingInfo 回调已触发（第 \(infoCallbackCount) 次），info 有内容（歌名=\(title ?? "?")）")
            }
        }
        lastInfoWasNil = isNil
        if !isNil { lastInfoTitle = title }
    }

    /// 诊断页用的一句话结论（没测过就写「未测」，不编通过）。
    static var summaryLine: String {
        guard let dlopenOK else { return "MediaRemote：未测（App 启动后第一次跟随才会测）" }
        if !dlopenOK { return "MediaRemote：dlopen 失败（框架打不开，读不到任何播放器）" }
        let missing = symbolResults.filter { !$0.value }.map(\.key)
        if !missing.isEmpty { return "MediaRemote：符号缺失：\(missing.joined(separator: "、"))" }
        if infoCallbackCount == 0 {
            return "MediaRemote：dlopen／dlsym 通过，回调还没触发过（等播放器上报）"
        }
        if lastInfoWasNil == true {
            return "MediaRemote：回调已触发 \(infoCallbackCount) 次，最近一次 info=nil（无播放器／读不到）"
        }
        return "MediaRemote：回调已触发 \(infoCallbackCount) 次，最近读到「\(lastInfoTitle ?? "?")」"
    }
}
