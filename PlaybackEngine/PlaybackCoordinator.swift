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

    /// 正在进行中的搜词任务，换歌时取消，避免旧歌结果覆盖新歌。
    private var searchTask: Task<Void, Never>?

    /// 锁屏歌词（路子 A）：上一次推给 Live Activity 的完整状态＋Activity id；
    /// 状态没变不推（系统限流：歌词一行 4–5 秒才切一次，远低于每秒一次的上限）。
    /// 完整状态比较去重（BUG-02／BUG-04）：暂停/恢复、换词、同下标换词、
    /// Activity 换实例都会推；一行没变时不推。
    /// 注意：ContentState 是 iOS 16.1 才有的类型，存成属性要带 @available，
    /// 否则 MinOS 15.0 下编不过（d461b62 原文没带，这里补上；行为不变）。
    @available(iOS 16.1, *)
    private var lastLiveState: LyricsLiveAttributes.ContentState?
    private var lastLiveActivityID: String?

    init(adapter: any PlaybackAdapter) {
        self.adapter = adapter
    }

    func start() {

        stop()

        message = "正在检测音乐..."
        LyricLogger.log("开始检测音乐")

        // 立即检测一次，不等第一个 tick —— 打开 App/点开始时立刻出画面
        poll()

        // 0.25 秒轮询：播放一开始就能在 1/4 秒内捕获，做到「即播即显」
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in

            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {

        timer?.invalidate()
        timer = nil
        searchTask?.cancel()
        searchTask = nil
    }

    /// 检测引擎是否在跑（timer 在位）。锁屏开关用 ensureRunning() 幂等启动，
    /// 不要直接调 start()（它会先 stop()，可能取消正在进行的搜词任务）。
    var isRunning: Bool { timer != nil }

    func ensureRunning() {
        if !isRunning {
            start()
        }
    }

    private func poll() {

        guard let newState = adapter.currentState() else {
            message = "没有检测到可读取的音乐"
            return
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

            // 换歌立刻推一次新歌（标题／♪ 占位），不等下一轮 poll。
            publishLiveLyrics()

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

        // ---- 锁屏歌词（路子 A）：变行才推给 Live Activity ----
        publishLiveLyrics()
    }

    /// 锁屏歌词（路子 A）：按 0.25 秒轮询算当前行，完整状态变了才推 Live Activity。
    /// 算法与 Widget 的 currentLyric 同款（LyricStore.currentElapsed＋lastIndex）。
    /// 没词时同一首歌只推一次「♪ {title}」占位；还没唱到第一句时推 ♪ 标题＋
    /// 第一句当 next，不留上一首歌的词。读不到歌时 poll() 提前 return，不会走到这里。
    private func publishLiveLyrics() {
        if #available(iOS 16.1, *) {
            // BUG-01 第一层：没开锁屏歌词时不记已推状态；重开后第一轮就推。
            guard LyricsLiveActivityController.shared.isActive else {
                lastLiveState = nil
                lastLiveActivityID = nil
                return
            }

            guard let snapshot = LyricStore.load() else {
                return
            }

            let activityID = LyricsLiveActivityController.shared.activityID

            // BUG-01 第二层：Activity 换实例（重开／8 小时到期重建）时，
            // 去重状态清零，下一轮强制重推，不等切词。
            if activityID != lastLiveActivityID {
                lastLiveState = nil
            }

            let previous: String
            let current: String
            let next: String
            var staleDate: Date?

            if snapshot.lyrics.isEmpty {
                // 没词：新歌还没搜到词，先推 ♪ 标题占位。
                previous = ""
                current = "♪ \(snapshot.title)"
                next = ""
                staleDate = nil
            } else {
                let elapsed = LyricStore.currentElapsed(snapshot, at: Date())
                if let index = snapshot.lyrics.lastIndex(where: { $0.time <= elapsed }) {
                    previous = index > 0 ? snapshot.lyrics[index - 1].text : ""
                    current = snapshot.lyrics[index].text
                    next = index + 1 < snapshot.lyrics.count
                        ? snapshot.lyrics[index + 1].text
                        : ""

                    // BUG-05：下一行歌词的时间＋5 秒；没下一行／暂停时不设。
                    // 暂停恢复时状态变了会重推重算；同一句内拖进度不改变
                    // 下一行绝对时间，沿用旧 staleDate 即可。
                    if snapshot.isPlaying, index + 1 < snapshot.lyrics.count {
                        let nextIn = snapshot.lyrics[index + 1].time - elapsed
                        staleDate = nextIn > 0 ? Date().addingTimeInterval(nextIn + 5) : nil
                    } else {
                        staleDate = nil
                    }
                } else {
                    // BUG-03：还没唱到第一句（前奏），不留上一首歌的词：
                    // 当前行放 ♪ 标题，第一句放 next。
                    previous = ""
                    current = "♪ \(snapshot.title)"
                    next = snapshot.lyrics.first?.text ?? ""
                    staleDate = nil
                }
            }

            let state = LyricsLiveAttributes.ContentState(
                title: clipped(snapshot.title),
                artist: clipped(snapshot.artist),
                previous: clipped(previous),
                current: clipped(current),
                next: clipped(next),
                isPlaying: snapshot.isPlaying,
                lyricColorHex: LyricsLiveActivityController.lyricColorHex()
            )

            // BUG-02／BUG-04：完整状态比较去重——暂停/恢复、换词、同下标换词、
            // Activity 换实例都会推；一行没变时不推。
            if state == lastLiveState && activityID == lastLiveActivityID {
                return
            }
            lastLiveState = state
            lastLiveActivityID = activityID

            Task {
                await LyricsLiveActivityController.shared.update(
                    state: state,
                    staleDate: staleDate
                )
            }
        }
    }

    /// 歌词超长限长：Activity 数据有系统大小限制，单字段最多 120 字。
    private func clipped(_ text: String) -> String {
        text.count > 120 ? String(text.prefix(120)) : text
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
