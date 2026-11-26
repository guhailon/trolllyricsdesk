import Foundation

/// 悬浮窗托管复核的 Swift 侧读数（1.0.5 第 3／4 项＋皇上树的 Diagnostics 层）。
///
/// 复核本身在 ObjC 侧（TLDSAppDelegate verifyFloatingVisibility）跑，
/// 结论写进 LyricStore（tlds.runMode／tlds.runModeReason）；
/// 这里只负责把结论读出来、格式化给诊断页看，不重新判定、不改模式。
/// 「已确认可见」只认复核结论，不认创建日志。
enum OverlayDiagnostics {

    /// 当前模式中文名（设置页／诊断页共用）。
    static var modeDescription: String { LyricStore.runModeDescription }

    /// 判定依据（复核逐项结论或待探测原因；没写过就是空）。
    static var modeReason: String { LyricStore.runModeReason }

    /// 诊断页显示的复核摘要行。
    static var summaryLines: [String] {
        switch LyricStore.runMode {
        case "trollstore":
            return ["原生悬浮窗：巨魔原生模式，不复核（悬浮窗照常）"]
        case "enhanced-host":
            return ["悬浮窗复核：已确认可见（场景／binder／窗口／windowScene／视图挂载全过）",
                    "依据：\(modeReason)"]
        case "compat":
            return ["悬浮窗复核：未确认可见，已降级普通签名兼容模式",
                    "原因：\(modeReason)"]
        default:
            return ["悬浮窗复核：待探测（启动后 2 秒复核，场景未连上时再等 3 秒）",
                    "依据：\(modeReason)"]
        }
    }

    static func logSummary() {
        LyricLogger.log("诊断1.0.5 悬浮窗复核摘要：\(modeDescription)；\(modeReason)")
    }
}
