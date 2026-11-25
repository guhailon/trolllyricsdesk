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
    @objc func start() {
        guard !started else { return }
        started = true

        BackgroundKeepAlive.shared.start()

        let coordinator = ensurePlayback()
        Task { @MainActor in
            coordinator.start()
            LyricLogger.log("运行时启动：自动跟随所有播放器")
        }
    }

    /// 构造主界面（ObjC SceneDelegate 放进 UIWindow.rootViewController）。
    @objc func makeRootViewController() -> UIViewController {
        let coordinator = ensurePlayback()
        // 主界面改为播放状态页；原 ContentView 作为「设置」子页面从右上角齿轮进入。
        let root = PlaybackDashboardView()
            .environmentObject(coordinator)
        return UIHostingController(rootView: root)
    }

    /// ObjC AppDelegate / SceneDelegate 写日志（复用 App 内同一个日志文件）。
    @objc func logMessage(_ message: String) {
        LyricLogger.log(message)
    }
}
