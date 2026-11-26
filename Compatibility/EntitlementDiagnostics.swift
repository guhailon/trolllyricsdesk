import Foundation

/// 权限「声明 vs 实测」对照（1.0.5＋皇上树的 Compatibility 层）。
///
/// 声明值是 App entitlements 文件的静态镜像——
/// `TrollLyricsDesk/TrollLyricsDesk.entitlements` 与 6857d3c 一字未动
/// （自检核过；以后改 entitlements 必须同步改这里，否则对照表失真）。
/// 实测值来自真实调用（dlopen／托管复核／PiP 支持检查），
/// 声明 ≠ 可用：LC 宿主本身没有这些私有权限，客人继承不到，
/// IPA 自己声明了也不代表在 LC 里能用。
enum EntitlementDiagnostics {

    struct CapabilityCheck {
        let name: String
        /// IPA 的 entitlements 里声明了没有。
        let declared: Bool
        /// 真实调用验证的结果（没测过就写「未测」，不编通过）。
        let observed: String
    }

    /// 对照表（声明列是静态镜像，实测列是实时读数）。
    static func checks() -> [CapabilityCheck] {
        let mediaRemoteObserved: String
        if let ok = MediaRemoteDiagnostics.dlopenOK {
            mediaRemoteObserved = ok ? "dlopen 成功（见 MediaRemote 诊断行）" : "dlopen 失败（框架打不开）"
        } else {
            mediaRemoteObserved = "未测"
        }
        let frontBoardObserved: String
        switch LyricStore.runMode {
        case "trollstore":
            frontBoardObserved = "巨魔模式：悬浮窗照常（不复核）"
        case "native-candidate":
            frontBoardObserved = "原生候选：实际可见性未确认"
        case "enhanced-host":
            frontBoardObserved = "托管检查通过，实际可见性待确认（增强宿主仍不信任原生 HUD，创建成功≠可见）"
        case "compat":
            frontBoardObserved = "托管检查未通过：\(LyricStore.runModeReason)"
        default:
            frontBoardObserved = "待探测"
        }
        // 1.0.6 第 5 项：平台应用／解除沙盒的实测列改读进程实测
        // （SecTask 任务权限＋沙盒外写探测），不再写静态的「LC 宿主不继承」。
        let platformObserved = "任务权限=\(EffectiveEntitlements.describe(EffectiveEntitlements.taskValue(for: "platform-application")) )（SecTask 实测；声明≠可用）"
        let noSandboxObserved = "任务权限=\(EffectiveEntitlements.describe(EffectiveEntitlements.taskValue(for: "com.apple.private.security.no-sandbox")) )；沙盒外写探测：\(EffectiveEntitlements.writeProbeDetail)"
        return [
            CapabilityCheck(
                name: "MediaRemote 读取（com.apple.mediaremote.*-read-access）",
                declared: true,
                observed: mediaRemoteObserved
            ),
            CapabilityCheck(
                name: "FrontBoard 悬浮场景（com.apple.frontboard.launchapplications）",
                declared: true,
                observed: frontBoardObserved
            ),
            CapabilityCheck(
                name: "BackBoard 客户端（com.apple.backboard.client）",
                declared: true,
                observed: "未单独测（随 FrontBoard 复核走）"
            ),
            CapabilityCheck(
                name: "RunningBoard（com.apple.runningboard.*）",
                declared: true,
                observed: "未单独测（随 FrontBoard 复核走）"
            ),
            CapabilityCheck(
                name: "平台应用（platform-application）",
                declared: true,
                observed: platformObserved
            ),
            CapabilityCheck(
                name: "解除沙盒（com.apple.private.security.no-sandbox）",
                declared: true,
                observed: noSandboxObserved
            ),
            CapabilityCheck(
                name: "PiP（公开 API，无需私有权限）",
                declared: false,
                observed: RuntimeCapabilities.pipSupported
                    ? "系统支持（真能显示与否看 PiP 实验 delegate 回调）"
                    : "系统不支持"
            ),
        ]
    }

    /// 对照表打进日志（诊断页刷新时记一次）。
    static func logReport() {
        LyricLogger.log("诊断1.0.6 权限对照：声明≠可用，实测以调用为准")
        for check in checks() {
            LyricLogger.log("诊断1.0.6 权限对照：\(check.name)：声明=\(check.declared ? "有" : "无")，实测=\(check.observed)")
        }
    }
}
