import Foundation
import AVKit
import UIKit

/// 实际运行能力检测（1.0.5＋皇上树的 Compatibility 层）。
///
/// 只认实际调用结果，不认 Entitlements 声明：
/// - LiveContainer 信号（路径／类名／plist）只是第一步信号；
/// - MediaRemote 能不能读，看 MediaRemoteDiagnostics 的真实回调记录；
/// - 原生悬浮窗能不能显示，看 ObjC 侧托管复核的结论（runMode）；
/// - PiP 支不支持，看 AVPictureInPictureController.isPictureInPictureSupported()
///   的公开 API 真调用（支不支持 ≠ 真能显示出来，显示与否看 PiP 实验的 delegate 回调）。
enum RuntimeCapabilities {

    static var iOSVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    static var isIOS27OrLater: Bool { iOSVersion.majorVersion >= 27 }

    /// 第一步信号：LiveContainer 宿主信号（路径／类名／plist）。
    static var liveContainerSignal: Bool { LyricStore.isLiveContainer }

    /// PiP 系统支不支持（公开 API 真调用，不是猜）。
    static var pipSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// MediaRemote 实测一句话结论。
    static var mediaRemoteSummary: String { MediaRemoteDiagnostics.summaryLine }

    /// 原生悬浮窗复核是否通过（只有复核判了增强宿主才算通过；
    /// 巨魔模式不复核，这里返回 false，不代表巨魔的悬浮窗不行）。
    static var nativeHUDProbePassed: Bool { LyricStore.runMode == "enhanced-host" }

    /// 能力快照，打进日志（启动后／诊断页刷新时各记一次）。
    static func logSnapshot() {
        LyricLogger.log(
            "诊断1.0.5 能力快照：iOS \(iOSVersion.majorVersion).\(iOSVersion.minorVersion)，" +
            "LiveContainer 信号=\(liveContainerSignal ? "有" : "无")，" +
            "PiP 系统支持=\(pipSupported ? "是" : "否")，" +
            "原生悬浮复核通过=\(nativeHUDProbePassed ? "是" : "否")；\(mediaRemoteSummary)"
        )
    }
}
