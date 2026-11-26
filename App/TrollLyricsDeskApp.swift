import SwiftUI
import AVFoundation
import UIKit
import Network

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

        if !LyricStore.isLiveContainer { BackgroundKeepAlive.shared.start() }
        DualProcessBridge.shared.start()

        let coordinator = ensurePlayback()
        Task { @MainActor in
            if !LyricStore.isLiveContainer { coordinator.start() }
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

// Read-only, explicitly paired loopback bridge. Never grants guest system privileges.
final class DualProcessBridge {
    static let shared = DualProcessBridge()
    private let queue = DispatchQueue(label: "tlds.bridge")
    private var listener: NWListener?
    private var timer: DispatchSourceTimer?
    private var active: NWConnection?
    private let port = NWEndpoint.Port(rawValue: 38473)!
    static let tokenKey = "tlds.bridge.token"
    static let freshnessKey = "tlds.bridge.lastReceived"
    static var token: String {
        LyricStore.defaults?.string(forKey: tokenKey) ?? ""
    }
    func start() {
        queue.async {
            if LyricStore.isLiveContainer { self.startClient() }
            else { self.startServer() }
        }
    }
    private func startServer() {
        if Self.token.isEmpty {
            LyricStore.defaults?.set(UUID().uuidString, forKey: Self.tokenKey)
        }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        do {
            let server = try NWListener(using: params, on: port)
            listener = server
            server.newConnectionHandler = { [weak self] connection in
                guard let self = self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 3) { connection.cancel() }
                connection.receive(minimumIncompleteLength: 36, maximumLength: 36) { data, _, _, _ in
                    guard ActivationStore.isActivated,
                          let data = data, let token = String(data: data, encoding: .utf8),
                          token == Self.token, !token.isEmpty,
                          let snapshot = LyricStore.load(),
                          let payload = try? JSONEncoder().encode(snapshot), payload.count <= 1_000_000 else {
                        connection.cancel(); return
                    }
                    connection.send(content: payload, contentContext: .finalMessage, isComplete: true,
                                    completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            server.start(queue: queue)
        } catch { LyricLogger.log("双进程桥启动失败：\(error)") }
    }
    private func startClient() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.request() }
        timer.resume()
    }
    private func request() {
        guard active == nil, ActivationStore.isActivated,
              UUID(uuidString: Self.token) != nil else { return }
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        active = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                connection.send(content: Data(Self.token.utf8), completion: .contentProcessed { error in
                    if error != nil { self.finish(connection) }
                    else { self.receive(connection, accumulated: Data()) }
                })
            case .failed, .cancelled: self.finish(connection)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { [weak self, weak connection] in
            if let connection = connection { self?.finish(connection) }
        }
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self = self, self.active === connection else { return }
            var buffer = accumulated
            if let data = data { buffer.append(data) }
            guard buffer.count <= 1_000_000, error == nil else { self.finish(connection); return }
            if complete {
                if let snapshot = try? JSONDecoder().decode(LyricSnapshot.self, from: buffer) {
                    LyricStore.save(snapshot)
                    LyricStore.defaults?.set(Date().timeIntervalSince1970, forKey: Self.freshnessKey)
                }
                self.finish(connection)
            } else { self.receive(connection, accumulated: buffer) }
        }
    }
    private func finish(_ connection: NWConnection) {
        guard active === connection else { return }
        active = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}
