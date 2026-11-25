import Foundation
import Combine
import WidgetKit

@MainActor
final class PlaybackCoordinator: ObservableObject {

    @Published private(set) var state: PlaybackState?
    @Published private(set) var message = "等待音乐播放"

    private let adapter: any PlaybackAdapter

    private var timer: Timer?
    private var lastTrackKey: String?
    private var lastStatus: PlaybackStatus?

    /// 播放状态检测间隔：播放中 0.25 秒（即播即显）；
    /// 空闲时 1.0 秒（节能：没歌或暂停时一直 0.25 秒问 MediaRemote，费电）。
    private let activePollInterval: TimeInterval = 0.25
    private let idlePollInterval: TimeInterval = 1.0

    private var pollInterval: TimeInterval = 0.25

    /// 连续多少次轮询没读到歌；满 4 次（约 1 秒）才降到空闲档，
    /// 刚切歌/刚开始播的那 1 秒内保持 0.25 秒快档，不漏歌。
    private var idlePolls = 0

    /// 正在进行中的搜词任务，换歌时取消，避免旧歌结果覆盖新歌。
    private var searchTask: Task<Void, Never>?

    init(adapter: any PlaybackAdapter) {
        self.adapter = adapter
    }

    func start() {

        stop()

        message = "正在检测音乐..."
        LyricLogger.log("开始检测音乐")

        // 立即检测一次，不等第一个 tick —— 打开 App/点开始时立刻出画面
        poll()

        scheduleTimer(interval: activePollInterval)
    }

    func stop() {

        timer?.invalidate()
        timer = nil
        searchTask?.cancel()
        searchTask = nil
        idlePolls = 0
        pollInterval = activePollInterval
    }

    private func scheduleTimer(interval: TimeInterval) {

        timer?.invalidate()
        pollInterval = interval

        timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in

            Task { @MainActor in
                self?.poll()
            }
        }
    }

    private func poll() {

        guard let newState = adapter.currentState() else {
            message = "没有检测到可读取的音乐"

            // 空闲节能：连续 4 次读不到歌（约 1 秒），降到 1.0 秒档。
            idlePolls += 1
            if idlePolls >= 4 && pollInterval != idlePollInterval {
                scheduleTimer(interval: idlePollInterval)
            }

            return
        }

        idlePolls = 0

        // 空闲节能：暂停/停止时降到 1.0 秒档；恢复播放立刻回 0.25 秒档。
        if newState.status == .playing {
            if pollInterval != activePollInterval {
                scheduleTimer(interval: activePollInterval)
            }
        } else if pollInterval != idlePollInterval {
            scheduleTimer(interval: idlePollInterval)
        }

        let previous = state
        state = newState

        let key = newState.trackKey

        // ---- 换歌：立刻写入新快照（含已有缓存歌词），再决定是否联网搜 ----
        if key != lastTrackKey {

            lastTrackKey = key
            lastStatus = newState.status

            message = "检测到新歌曲：\(newState.track.title)"
            LyricLogger.log("检测到新歌曲：\(newState.track.title) - \(newState.track.artist)")

            // 取消上一首歌的搜词
            searchTask?.cancel()

            // 关键：同步写一份新歌快照，进度基准 = 当前播放进度。
            // 命中本地缓存则直接带歌词 -> 桌面歌词与播放同时出现。
            publishImmediately(newState)

            searchTask = Task {
                await loadLyrics(for: newState.track)
            }

            return
        }

        // ---- 同一首歌，播放状态变化：即时同步进度基准 ----
        if lastStatus != newState.status {

            lastStatus = newState.status

            switch newState.status {

            case .playing:
                message = "正在播放"

            case .paused:
                message = "播放已暂停"

            case .stopped:
                message = "播放已停止"

            case .interrupted:
                message = "播放被中断"

            case .unknown:
                message = "播放状态未知"
            }

            // 由暂停恢复播放时，用当下进度重置 startedAt，避免进度跳变
            syncPlaybackState(newState, previous: previous)

            LyricLogger.log(message)
        }
    }

    /// 检测到新歌时立即发布快照：进度基准对齐当前 position，
    /// 歌词优先用本地缓存，没有就留空（等联网结果），但歌名/进度不延迟。
    private func publishImmediately(_ newState: PlaybackState) {

        let title = newState.track.title
        let artist = newState.track.artist

        let cached = LyricStore.cachedLyrics(
            title: title,
            artist: artist
        )

        // 保留用户在设置里调过的外观
        let (opacity, fontSize) = currentAppearance()

        let snapshot = LyricSnapshot(
            title: title,
            artist: artist,
            lyrics: cached ?? [],
            startedAt: Date(),
            isPlaying: newState.status == .playing,
            elapsedWhenPaused: newState.position,
            opacity: opacity,
            fontSize: fontSize
        )

        LyricStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        if cached != nil {
            message = "歌词匹配成功（本地）"
            LyricLogger.log("本地歌词命中：\(title)")
        }
    }

    /// 播放/暂停切换：更新快照里的进度基准，保证歌词跟着真实进度走。
    private func syncPlaybackState(
        _ newState: PlaybackState,
        previous: PlaybackState?
    ) {
        guard var snapshot = LyricStore.load() else {
            return
        }

        guard
            snapshot.title == newState.track.title,
            snapshot.artist == newState.track.artist
        else {
            return
        }

        let elapsed: TimeInterval

        if newState.status == .playing {
            // 开始播放：以当前上报进度为新起点
            elapsed = newState.position
        } else {
            // 暂停：冻结在当前进度
            elapsed = newState.position
        }

        snapshot.startedAt = Date()
        snapshot.elapsedWhenPaused = elapsed
        snapshot.isPlaying = newState.status == .playing

        LyricStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func currentAppearance() -> (opacity: Double, fontSize: Double) {
        guard let snapshot = LyricStore.load() else {
            return (0.65, 22)
        }
        return (snapshot.opacity, snapshot.fontSize)
    }

    private func loadLyrics(
        for track: MusicTrack
    ) async {

        message = "正在搜索歌词：\(track.title)"

        do {

            let records = try await LRCLibClient.shared.search(
                track: track
            )

            try Task.checkCancellation()

            guard
                let result = LyricMatcher.bestMatch(
                    records: records,
                    track: track
                ),
                let lrc = result.syncedLyrics
            else {

                message = "没有找到匹配的同步歌词"
                LyricLogger.log("没有找到匹配的同步歌词：\(track.title)")

                return
            }

            let lines = LyricParser.parse(lrc)

            guard !lines.isEmpty else {

                message = "歌词解析失败"
                LyricLogger.log("歌词解析失败：\(track.title)")

                return
            }

            // 防止搜索期间歌曲已经切换
            guard state?.trackKey == trackKey(track) else {
                return
            }

            // 缓存，下次同曲即播即显
            LyricStore.cacheLyrics(
                lines,
                title: track.title,
                artist: track.artist
            )

            // 用「此刻」最新进度做基准，歌词从当前进度开始显示
            if let current = state {
                syncLyrics(lines, at: current)
            }

            message = "歌词匹配成功"
            LyricLogger.log("歌词匹配成功：\(track.title)")

        } catch is CancellationError {

            return

        } catch {

            message = "歌词搜索失败：\(error.localizedDescription)"
            LyricLogger.log(message)
        }
    }

    /// 把搜到的歌词写进当前快照，进度基准取当下上报的 position。
    private func syncLyrics(
        _ lines: [LyricLine],
        at current: PlaybackState
    ) {
        var snapshot = LyricStore.load()

        if snapshot == nil ||
            snapshot?.title != current.track.title ||
            snapshot?.artist != current.track.artist {

            let (opacity, fontSize) = currentAppearance()
            snapshot = LyricSnapshot(
                title: current.track.title,
                artist: current.track.artist,
                lyrics: [],
                startedAt: Date(),
                isPlaying: current.status == .playing,
                elapsedWhenPaused: current.position,
                opacity: opacity,
                fontSize: fontSize
            )
        }

        snapshot?.lyrics = lines
        snapshot?.startedAt = Date()
        snapshot?.elapsedWhenPaused = current.position
        snapshot?.isPlaying = current.status == .playing

        guard let final = snapshot else {
            return
        }

        LyricStore.save(final)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func trackKey(
        _ track: MusicTrack
    ) -> String {

        "\(track.platform.rawValue)|\(track.title)|\(track.artist)"
            .lowercased()
    }
}
