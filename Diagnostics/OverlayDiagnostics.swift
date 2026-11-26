import Foundation

/// 悬浮窗托管复核的 Swift 侧读数（1.0.5 第 3／4 项＋皇上树的 Diagnostics 层）。
///
/// 复核本身在 ObjC 侧（TLDSAppDelegate verifyFloatingVisibility）跑，
/// 结论写进 LyricStore（tlds.runMode／tlds.runModeReason）；
/// 这里只负责把结论读出来、格式化给诊断页看，不重新判定、不改模式。
/// 1.0.6：第 6 项——复核结论不再写「已确认可见」，只写「结构检查通过，
/// 实际屏幕可见性未确认」（binder／窗口／windowScene 只能证明托管结构通过）。
/// trollstore（正面证据已出）与 native-candidate（安装来源未知）是两档，
/// 不要并成一行。
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
        case "native-candidate":
            return ["原生悬浮窗：原生候选（安装来源未知），实际屏幕可见性未确认"]
        case "enhanced-host":
            return ["悬浮窗复核：结构检查通过，实际屏幕可见性未确认",
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
        LyricLogger.log("诊断1.0.6 悬浮窗复核摘要：\(modeDescription)；\(modeReason)")
    }
}
