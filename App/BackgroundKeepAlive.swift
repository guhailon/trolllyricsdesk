import AVFoundation

// MARK: - 后台保活（静音音频）
// iOS 退到后台会暂停 Timer，检测引擎就不 polling 了，换歌检测不到。
// 用静音音频循环 + UIBackgroundModes=audio 让 App 在后台常驻，
// .mixWithOthers 保证不打断用户正在听的音乐，也不占用 NowPlaying 信息。
//
// 来源：皇上本地版（hidden_files/local-overlay-1.0.3）
// App/TrollLyricsDeskApp.swift 里的 BackgroundKeepAlive，原样移植；
// 本地版是 App 启动就自动开，1.0.6 改成可选开关（默认关，见
// ContentView 的「后台保活」开关）——所以这里补了一个本地版没有的
// stop()：开关关掉时停掉引擎、释放音频会话。
final class BackgroundKeepAlive {

    static let shared = BackgroundKeepAlive()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    var isRunning: Bool { started }

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
            started = false
        }
    }

    /// 1.0.6 补的：开关关掉时停引擎、停播放器、释放音频会话。
    /// 本地版没有 stop()（它启动即常驻）；可选开关必须能关。
    func stop() {
        guard started else { return }
        started = false

        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
