import Foundation

/// 显示引擎三档（1.0.5＋皇上树的 Compatibility 层）。
///
/// 切换优先级（阈值写死在这里，改优先级只改这里）：
/// - 巨魔原生（trollstore）→ 原生 HUD（唯一档，行为一字不动）；
/// - 增强宿主（enhanced-host）→ PiP 实验（首选），应用内备选。
///   透明全域悬浮在此模式为「权限受限」：即使 FBScene 复核过了，
///   1.0.4 的教训是创建日志成功≠真显示出来，所以增强宿主不信任原生 HUD，
///   只信任 PiP 的 delegate 回调（真显示出来才算）；
/// - 普通签名兼容（compat）／待探测（probing）→ 应用内（原生与 PiP 皆不可用时）。
/// 模式判定本身在 ObjC 侧（TLDSAppDelegate 托管复核），这里只做「模式 → 引擎」映射。
enum TLDSDisplayEngine: String {
    case nativeHUD = "nativeHUD"
    case pip = "pip"
    case inApp = "inApp"

    var displayName: String {
        switch self {
        case .nativeHUD: return "原生 HUD 悬浮歌词"
        case .pip: return "PiP 画中画歌词（实验）"
        case .inApp: return "应用内歌词"
        }
    }
}

enum RuntimeEnvironment {

    /// 模式 → 首选引擎（纯映射，不探测；探测在复核／PiP delegate 里）。
    static func preferredEngine(forRunMode mode: String) -> TLDSDisplayEngine {
        switch mode {
        case "trollstore":
            return .nativeHUD
        case "enhanced-host":
            return .pip
        default:
            return .inApp
        }
    }

    /// 当前首选引擎（按 LyricStore.runMode 现值算）。
    static var preferredEngine: TLDSDisplayEngine {
        preferredEngine(forRunMode: LyricStore.runMode)
    }

    /// 引擎切换日志：进了哪档、选了哪个引擎、凭什么（模式＋复核依据）。
    static func logEngineSelection() {
        let engine = preferredEngine
        LyricLogger.log(
            "诊断1.0.5 显示引擎：\(engine.displayName)（模式 \(LyricStore.runModeDescription)；\(LyricStore.runModeReason)）"
        )
    }
}
