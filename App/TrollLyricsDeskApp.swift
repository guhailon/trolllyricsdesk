import SwiftUI
import AVFoundation
import UIKit

// MARK: - 后台保活
// iOS 退到后台会暂停 Timer，检测引擎就不 polling 了，换歌检测不到。
// 用静音音频循环 + UIBackgroundModes=audio 让 App 在后台常驻，
// .mixWithOthers 保证不打断用户正在听的音乐，也不占用 NowPlaying 信息。
final class BackgroundKeepAlive {

    static let shared = BackgroundKeepAlive()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: 44100,
                channels: 1
            ) else { return }

            engine.attach(player)
            engine.connect(
                player,
                to: engine.mainMixerNode,
                format: format
            )

            let frames = AVAudioFrameCount(format.sampleRate)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frames
            ) else { return }
            buffer.frameLength = frames
            if let channel = buffer.floatChannelData {
                for i in 0..<Int(frames) {
                    channel[0][i] = 0
                }
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)

            try engine.start()
            player.play()
        } catch {
            // 保活失败不影响主流程；前台检测照常。
        }
    }
}

// MARK: - App 运行时（供 Objective-C AppDelegate 调用）
// 工程已从纯 SwiftUI 生命周期改为 UIKit 生命周期（main.m + TLDSAppDelegate），
// 这样才能用 FrontBoard 私有 API 创建"退到桌面仍然显示"的全局悬浮歌词场景。
// 本类持有唯一的播放检测引擎，并向 ObjC 暴露启动与主界面构造入口。
@objc(TLDSRuntime)
@objcMembers
final class TrollLyricsRuntime: NSObject {

    @objc static let shared = TrollLyricsRuntime()

    // PlaybackCoordinator 是 @MainActor，只能在主线程构造。
    // ObjC 的 didFinishLaunching / willConnect 都在主线程，用 assumeIsolated
    // 明确告诉编译器这一点（Swift 5 语言模式下的并发检查）。
    private var playbackBox: PlaybackCoordinator?

    private var started = false

    // 1.0.5 诊断（第 5 项）：start() 被调用次数（重复调用只记日志，不重建）。
    private var startCallCount = 0

    private override init() {
        super.init()
    }

    @nonobjc private func ensurePlayback() -> PlaybackCoordinator {
        MainActor.assumeIsolated {
            if let box = playbackBox {
                return box
            }
            let coordinator = PlaybackCoordinator(adapter: MediaRemoteAdapter())
            playbackBox = coordinator
            return coordinator
        }
    }

    /// App 启动即自动跟随所有播放器（ObjC AppDelegate 调用）。
    @objc func isHosted() -> Bool { LyricStore.isLiveContainer }

    /// 1.0.5（ChatGPT 审查 bug 2）：ObjC 侧统一存储入口——
    /// 就是 LyricStore.defaults（巨魔 App Group／宿主 .standard），
    /// ObjC 代码不要自己 initWithSuiteName。
    /// suite 拿不到时回 .standard（与 @AppStorage store=nil 的兜底一致）。
    @objc static func sharedDefaults() -> UserDefaults {
        LyricStore.defaults ?? .standard
    }

    /// 1.0.5 三档模式：ObjC 侧（TLDSAppDelegate 托管复核）写判定结果，
    /// 走 LyricStore.defaults（巨魔 App Group／宿主 .standard，与快照同存储）。
    /// 每次写都记一行日志，日志页能看到「进了哪档、凭什么」。
    @objc func setRunMode(_ mode: String, reason: String) {
        LyricStore.runMode = mode
        LyricStore.runModeReason = reason
        LyricLogger.log("诊断1.0.6 运行模式：写入 \(mode)（\(reason)）")
    }

    /// 1.0.6 第 1／2 项：安装环境写入口——启动时定一次，之后永不改写。
    /// 托管复核禁止调这个方法（复核只调 setDisplayCapability／setRunMode）。
    @objc func setInstallEnvironment(_ env: String, reason: String) {
        LyricStore.installEnvironment = env
        LyricStore.installEnvironmentReason = reason
        LyricLogger.log("诊断1.0.6 安装环境：\(InstallEnvironment(rawValue: env)?.displayName ?? env)（\(reason)）")
    }

    /// 1.0.6 第 2 项：显示能力写入口——复核结论或安装环境定档时调。
    @objc func setDisplayCapability(_ capability: String, reason: String) {
        LyricStore.displayCapability = capability
        LyricStore.displayCapabilityReason = reason
        LyricLogger.log("诊断1.0.6 显示能力：\(DisplayCapability(rawValue: capability)?.displayName ?? capability)（\(reason)）")
    }

    /// 1.0.6 第 1 项：安装环境判定（启动时 ObjC 侧调一次）。
    /// 先记实测权限表，再按正面证据定档并写库、记日志，返回安装环境原值。
    @objc func detectInstallEnvironment() -> String {
        EffectiveEntitlements.logReport()
        let result = RuntimeEnvironment.detectInstallEnvironment()
        setInstallEnvironment(result.env.rawValue, reason: result.reason)
        return result.env.rawValue
    }

    /// 1.0.6：读当前安装环境（诊断页／ObjC 侧复核分支用）。
    @objc func installEnvironmentString() -> String { LyricStore.installEnvironment }

    /// 1.0.6 第 4 项：诊断行的环境标签——安装环境＋iOS 版本，
    /// 每个 MediaRemote／托管复核结论都带上，两台机的日志不再混在一起判。
    @objc func environmentTag() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "安装环境=\(LyricStore.installEnvironmentDescription)，iOS \(version.majorVersion).\(version.minorVersion)"
    }

    /// 1.0.5：读当前模式（设置页显示用；没写过时默认 probing）。
    @objc func runModeString() -> String { LyricStore.runMode }

    @objc func start() {
        // 1.0.5（第 5 项）：重复调用记「已启动，跳过」，不建第二个检测引擎。
        startCallCount += 1
        if started {
            LyricLogger.log("诊断1.0.6 重复初始化：TLDSRuntime.start 第 \(startCallCount) 次调用，已启动，跳过")
            return
        }
        started = true

        if !LyricStore.isLiveContainer { BackgroundKeepAlive.shared.start() }

        let coordinator = ensurePlayback()
        Task { @MainActor in
            coordinator.start()
            LyricLogger.log("运行时启动：自动跟随所有播放器")
        }
    }

    /// 构造主界面（ObjC SceneDelegate 放进 UIWindow.rootViewController）。
    @objc func makeRootViewController() -> UIViewController {
        let coordinator = ensurePlayback()
        // 1.0.3：未激活先全屏显示激活页，不进主界面；激活成功后
        // @AppStorage 实时切到主界面，不用重启。
        // 主界面改为播放状态页；原 ContentView 作为「设置」子页面从右上角齿轮进入。
        let root = ActivationGateView {
            PlaybackDashboardView()
        }
        .environmentObject(coordinator)
        return UIHostingController(rootView: root)
    }

    /// ObjC AppDelegate / SceneDelegate 写日志（复用 App 内同一个日志文件）。
    @objc func logMessage(_ message: String) {
        LyricLogger.log(message)
    }
}
