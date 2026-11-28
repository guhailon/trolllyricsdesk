import Foundation
import AVFoundation
import AVKit
import Combine
import UIKit

/// PiP 画中画歌词实验引擎（1.0.5 新增，实验性质）。
///
/// 做法：歌词文字 → PiPFrameRenderer 画成无声视频段 → AVQueuePlayer 播 →
/// AVPictureInPictureController 浮在桌面／其他 App 上方。
/// 步骤分两段，先后验证：① 固定测试文字（`startTestText()`），确认 PiP 能不能
/// 在桌面和其他 App 上方出现；② 实时歌词（`startLiveLyrics()`），歌词行一变
/// 就生成新视频段、排进队列。两段都是实验——UI 与 RUN 里都写明「实验」，
/// 不得标记为已实现；PiP 能显示也不代表能自动拿到别的播放器的歌，
/// 跨应用识别要单独解决（见 MediaRemote 诊断）。
///
/// 真能显示的唯一证据是 delegate 回调
/// `pictureInPictureControllerDidStartPictureInPicture`；
/// `canStartPictureInPicture` 为真、调用了 start，都不算成功。
/// 限制（写进 RUN，不回避）：透明背景受限（视频帧是黑底，不是透明悬浮窗）、
/// 拖动与大小由系统控制、锁屏不保证、后台行为未验证、每行歌词都要现编码一段视频。
final class PiPLyricsRenderer: NSObject, ObservableObject {

    static let shared = PiPLyricsRenderer()

    /// 诊断页／设置页显示的状态行（@Published，UI 直接读）。
    @Published private(set) var statusText = "PiP 实验：未开始"

    /// 当前状态（写进 LyricStore.defaults，日志页／诊断页都能看到）。
    private var status: String {
        get { LyricStore.defaults?.string(forKey: "tlds.pipStatus") ?? "未开始" }
        set {
            LyricStore.defaults?.set(newValue, forKey: "tlds.pipStatus")
            statusText = "PiP 实验：\(newValue)"
        }
    }

    /// 1.0.6 第 9 项：PiP 两段独立状态（固定文字段／实时歌词段各记各的）：
    /// 未开始／进行中／已显示／失败（原因）。写进 LyricStore.defaults，
    /// 诊断页分行显示；原有 combined status 不动。
    private var testStage: String {
        get { LyricStore.defaults?.string(forKey: "tlds.pipTestStage") ?? "未开始" }
        set {
            LyricStore.defaults?.set(newValue, forKey: "tlds.pipTestStage")
            LyricLogger.log("诊断1.0.6 PiP 固定文字段：\(newValue)")
        }
    }

    private var liveStage: String {
        get { LyricStore.defaults?.string(forKey: "tlds.pipLiveStage") ?? "未开始" }
        set {
            LyricStore.defaults?.set(newValue, forKey: "tlds.pipLiveStage")
            LyricLogger.log("诊断1.0.6 PiP 实时歌词段：\(newValue)")
        }
    }

    /// 供 DiagnosticsView 读的两段状态（只加行，不改 UI 布局）。
    static var testStageText: String {
        LyricStore.defaults?.string(forKey: "tlds.pipTestStage") ?? "未开始"
    }

    static var liveStageText: String {
        LyricStore.defaults?.string(forKey: "tlds.pipLiveStage") ?? "未开始"
    }

    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var hostView = UIView()
    private var liveTimer: Timer?
    private var lastLiveLine: String?
    private var generating = false
    private var testLooping = false

    private override init() {
        super.init()
        statusText = "PiP 实验：\(status)"
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 第一段：固定测试文字（先验这段）

    /// 开始 PiP 测试：固定测试文字视频循环播，尝试浮到桌面／其他 App 上方。
    /// 必须在前台、由用户点按钮触发（PiP 启动在后台回调里不可靠）。
    func startTestText() {
        guard RuntimeCapabilities.pipSupported else {
            setStatus("此设备不支持 PiP（isPictureInPictureSupported=false）")
            LyricLogger.log("诊断1.0.6 PiP：启动失败：此设备不支持 PiP")
            return
        }
        testLooping = true
        lastLiveLine = nil
        liveTimer?.invalidate()
        liveTimer = nil
        testStage = "进行中"
        setStatus("测试视频生成中…")
        let url = PiPFrameRenderer.testVideoURL()
        PiPFrameRenderer.renderVideo(
            mainText: "悬浮测试 · 桌面歌词 2.0.5",
            subText: "PiP 实验 · 固定文字",
            to: url
        ) { [weak self] error in
            guard let self else { return }
            if let error {
                self.testStage = "失败：\(error.localizedDescription)"
                self.setStatus("测试视频生成失败：\(error.localizedDescription)")
                return
            }
            self.setStatus("测试视频已生成，开始播放并尝试 PiP…")
            self.play(urls: [url])
            self.startPictureInPicture()
        }
    }

    // MARK: - 第二段：实时歌词（测试文字验过之后再接）

    /// 接入实时歌词：每 0.5 秒读当前歌词行，行一变就生成新视频段、排进队列。
    /// 歌词本身仍走新底子同步引擎（LyricStore 快照），这里只负责「行 → 视频段 → PiP」。
    func startLiveLyrics() {
        guard RuntimeCapabilities.pipSupported else {
            setStatus("此设备不支持 PiP（isPictureInPictureSupported=false）")
            LyricLogger.log("诊断1.0.6 PiP：启动失败：此设备不支持 PiP")
            return
        }
        testLooping = false
        lastLiveLine = nil
        liveStage = "进行中"
        setStatus("实时歌词 PiP（实验）：等当前歌词行…")
        ensurePlayer()
        if pipController == nil {
            startPictureInPicture()
        } else if pipController?.isPictureInPictureActive == false {
            startPictureInPicture()
        }
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tickLiveLyrics()
        }
        tickLiveLyrics()
    }

    private func tickLiveLyrics() {
        guard let snapshot = LyricStore.load() else { return }
        let line = LyricStore.currentLyric(snapshot, at: Date())?.text
            ?? "♪ \(snapshot.title)"
        guard line != lastLiveLine, !generating else { return }
        lastLiveLine = line
        generating = true
        let url = PiPFrameRenderer.segmentURL(forLine: line)
        PiPFrameRenderer.renderVideo(mainText: line, subText: snapshot.title, to: url) { [weak self] error in
            guard let self else { return }
            self.generating = false
            if let error {
                LyricLogger.log("诊断1.0.6 PiP：实时歌词段生成失败：\(error.localizedDescription)")
                return
            }
            self.enqueue(url: url)
        }
    }

    // MARK: - 播放与 PiP 控制

    private func ensurePlayer() {
        if player == nil {
            let queuePlayer = AVQueuePlayer()
            queuePlayer.actionAtItemEnd = .advance
            player = queuePlayer
            let layer = AVPlayerLayer(player: queuePlayer)
            layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
            playerLayer = layer
            hostView.layer.addSublayer(layer)
        }
    }

    private func play(urls: [URL]) {
        ensurePlayer()
        guard let player else { return }
        player.removeAllItems()
        for url in urls {
            player.insert(AVPlayerItem(url: url), after: nil)
        }
        player.play()
    }

    private func enqueue(url: URL) {
        ensurePlayer()
        guard let player else { return }
        if player.items().isEmpty {
            player.insert(AVPlayerItem(url: url), after: nil)
            player.play()
            if pipController == nil || pipController?.isPictureInPictureActive == false {
                startPictureInPicture()
            }
        } else {
            player.insert(AVPlayerItem(url: url), after: player.items().last)
        }
        // 队列只留最近两段，播完的旧段文件清掉，不堆 tmp。
        while player.items().count > 2 {
            if let first = player.items().first {
                player.remove(first)
            } else { break }
        }
    }

    private func startPictureInPicture() {
        guard let playerLayer else {
            setStatus("PiP 启动失败：播放层未建立")
            return
        }
        if pipController == nil {
            guard AVPictureInPictureController.isPictureInPictureSupported() else {
                setStatus("此设备不支持 PiP")
                return
            }
            let controller = AVPictureInPictureController(playerLayer: playerLayer)
            controller?.delegate = self
            pipController = controller
        }
        guard let controller = pipController else {
            setStatus("PiP 控制器创建失败")
            LyricLogger.log("诊断1.0.6 PiP：AVPictureInPictureController 初始化返回空")
            return
        }
        if controller.isPictureInPictureActive {
            setStatus("PiP 已显示（实验）")
            return
        }
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
            LyricLogger.log("诊断1.0.6 PiP：已调用 startPictureInPicture（等 delegate 回调才算成功）")
        } else {
            setStatus("PiP 暂不能启动（isPictureInPicturePossible=false，可能播放器未在播）")
            LyricLogger.log("诊断1.0.6 PiP：启动失败：isPictureInPicturePossible=false")
        }
    }

    func stop() {
        testLooping = false
        liveTimer?.invalidate()
        liveTimer = nil
        pipController?.stopPictureInPicture()
        player?.pause()
        player?.removeAllItems()
        setStatus("已停止")
        LyricLogger.log("诊断1.0.6 PiP：已停止")
    }

    private func setStatus(_ text: String) {
        status = text
        LyricLogger.log("诊断1.0.6 PiP：\(text)")
    }

    @objc private func itemDidPlayToEnd(_ note: Notification) {
        // 测试文字循环：播完再排一次同一段，保持 PiP 不黑屏。
        guard testLooping else { return }
        guard let item = note.object as? AVPlayerItem else { return }
        guard let player, player.items().contains(item) else { return }
        if let asset = item.asset as? AVURLAsset {
            player.insert(AVPlayerItem(url: asset.url), after: player.items().last)
        }
        player.seek(to: .zero)
    }
}

// MARK: - LyricsRenderer 协议（统一渲染层用；实验引擎）
extension PiPLyricsRenderer: LyricsRenderer {

    var engineName: String { "PiP 画中画歌词（实验）" }

    var isExperimental: Bool { true }

    func showTestText() {
        startTestText()
    }

    func showLiveLyrics() {
        startLiveLyrics()
    }
}

extension PiPLyricsRenderer: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        LyricLogger.log("诊断1.0.6 PiP：将开始 PiP（delegate 回调）")
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        // 唯一算数的成功证据：PiP 真显示出来了。按当前段写（第 9 项）：
        // 固定文字循环中 → 固定文字段已显示；实时歌词中 → 实时歌词段已显示。
        if testLooping {
            testStage = "已显示"
        } else {
            liveStage = "已显示"
        }
        setStatus("PiP 已显示（实验）——桌面／其他 App 上方应能看到测试文字或歌词")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        if testLooping {
            testStage = "失败：\(error.localizedDescription)"
        } else {
            liveStage = "失败：\(error.localizedDescription)"
        }
        setStatus("PiP 启动失败：\(error.localizedDescription)")
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        LyricLogger.log("诊断1.0.6 PiP：将停止 PiP（delegate 回调）")
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        setStatus("PiP 已停止（用户关闭或系统收回）")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // PiP 关掉后回到 App 前台即可恢复界面。
        completionHandler(true)
    }
}
