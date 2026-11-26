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

    /// 1.0.6 第 4 项：诊断行的环境标签（安装环境＋iOS 版本），
    /// MediaRemote／托管复核结论都带上，两台机的日志不再混在一起判。
    static var environmentTag: String {
        "安装环境=\(LyricStore.installEnvironmentDescription)，iOS \(iOSVersion.majorVersion).\(iOSVersion.minorVersion)"
    }

    /// 原生悬浮窗是否被定为显示能力（1.0.6：第 2 项的 displayCapability；
    /// 巨魔原生直接定 nativeHUD，宿主／未确认由复核定，普通签名定 inApp）。
    static var nativeHUDProbePassed: Bool { LyricStore.displayCapability == "nativeHUD" }

    /// 能力快照，打进日志（启动后／诊断页刷新时各记一次）。
    static func logSnapshot() {
        LyricLogger.log(
            "诊断1.0.6 能力快照：\(environmentTag)，" +
            "LiveContainer 信号=\(liveContainerSignal ? "有" : "无")，" +
            "PiP 系统支持=\(pipSupported ? "是" : "否")，" +
            "原生悬浮显示能力=\(nativeHUDProbePassed ? "是" : "否")；\(mediaRemoteSummary)"
        )
    }
}
