import Foundation

/// 显示引擎三档（1.0.5＋皇上树的 Compatibility 层）。
///
/// 切换优先级（阈值写死在这里，改优先级只改这里）：
/// - 巨魔原生（trollstore）→ 原生 HUD（唯一档，行为一字不动）；
/// - 增强宿主（enhanced-host）→ PiP 实验（首选），应用内备选。
///   透明全域悬浮在此模式为「权限受限」：即使 FBScene 托管结构过了，
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
        case .nativeHUD: return "HUD 守护进程悬浮歌词"
        case .pip: return "PiP 画中画歌词（实验）"
        case .inApp: return "应用内歌词"
        }
    }
}

/// 1.0.6 第 1／2 项：三项判定分离。
///
/// 安装环境（装在哪）／实际权限（进程真正能用的能力）／显示能力
/// （原生悬浮／PiP／应用内）各自独立判定、各自记日志、各自存值。
/// 托管复核只定显示能力，禁止它直接改安装环境类型——1.0.5 的病根
/// 就是复核把 trollstore 改成 enhanced-host。
///
/// 安装环境只凭正面证据定一次（启动时），之后永不改写：
/// - livecontainer：LiveContainer 信号已出（路径／类名／plist 之一）。
/// - trollstore：TrollStore 正面证据（任务权限 platform-application 与
///   no-sandbox 均为 true，或沙盒外写探测成功）。「没检测到 LC 信号」
///   不是证据——1.0.5 的 `if (!isHosted) → trollstore` 就是要改掉的那行。
/// - signature：无 TrollStore 正面证据，且已证实被沙盒拦住（写探测被拒，
///   或任务权限两项都明确为 false）。LC 客人信号全漏时也会落在这里——
///   行为正确（只走应用内歌词），标签待皇上确认设备后再收敛。
/// - unknown：无 LC 信号、无 TrollStore 正面证据、权限探测也不可用。
///   此时尝试创建悬浮窗、等复核定显示能力；安装环境仍记 unknown，不改。
enum InstallEnvironment: String {
    case trollstore = "trollstore"
    case livecontainer = "livecontainer"
    case signature = "signature"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .trollstore: return "TrollStore（巨魔）"
        case .livecontainer: return "LiveContainer 宿主"
        case .signature: return "普通签名（沙盒内）"
        case .unknown: return "未确认（权限探测不可用）"
        }
    }
}

/// 显示能力（悬浮窗／PiP／应用内三选一，由复核或安装环境定）。
enum DisplayCapability: String {
    case nativeHUD = "nativeHUD"
    case pip = "pip"
    case inApp = "inApp"

    var displayName: String {
        switch self {
        case .nativeHUD: return "HUD 守护进程悬浮歌词"
        case .pip: return "PiP 画中画歌词（实验）"
        case .inApp: return "应用内歌词"
        }
    }
}

enum RuntimeEnvironment {
    static var canUseNativeHUD: Bool {
        !LyricStore.isLiveContainer && LyricStore.installEnvironment == "trollstore"
    }

    /// 安装环境判定（启动时调一次；只读证据，不写模式）。
    static func detectInstallEnvironment() -> (env: InstallEnvironment, reason: String) {
        if LyricStore.isLiveContainer {
            return (.livecontainer, "LiveContainer 信号已出（\(LyricStore.liveContainerSignalDetail)）")
        }
        let evidence = EffectiveEntitlements.trollStoreEvidence()
        if evidence.proven {
            return (.trollstore, "TrollStore 正面证据：\(evidence.detail)")
        }
        if EffectiveEntitlements.sandboxedProven {
            return (.signature, "无 TrollStore 正面证据；\(evidence.detail)")
        }
        return (.unknown, "无 LiveContainer 信号；\(evidence.detail)")
    }

    /// 模式 → 首选引擎（纯映射，不探测；探测在复核／PiP delegate 里）。
    /// native-candidate（安装来源未知，托管结构通过）也走原生 HUD——
    /// 这是并入 ChatGPT 1.0.6 的映射（皇上 23:18 批并）；trollstore（正面证据
    /// 已出）与 native-candidate 是两档模式，但首选引擎相同。
    static func preferredEngine(forRunMode mode: String) -> TLDSDisplayEngine {
        switch mode {
        case "trollstore":
            return canUseNativeHUD ? .nativeHUD : .inApp
        case "native-candidate":
            return .inApp
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
            "诊断1.0.6 显示引擎：\(engine.displayName)（模式 \(LyricStore.runModeDescription)；\(LyricStore.runModeReason)）"
        )
    }
}
