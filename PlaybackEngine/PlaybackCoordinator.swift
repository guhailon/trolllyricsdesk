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
    private var lastHUDLyricIndex: Int?

    /// 正在进行中的搜词任务，换歌时取消，避免旧歌结果覆盖新歌。
    /// （皇上本地版，1.0.6 移植。）
    private var searchTask: Task<Void, Never>?

    /// 播放状态检测间隔：播放中 0.25 秒（皇上本地版，即播即显）；
    /// 空闲时 1.0 秒（1.0.6 自加的节能：本地版是固定 0.25 秒，
    /// 没有节能写法——没歌或暂停时一直 0.25 秒问 MediaRemote，
    /// 费电；这里按「暂停/无播放时降频」的原则降到 1.0 秒）。
    private let activePollInterval: TimeInterval = 0.25
    private let idlePollInterval: TimeInterval = 1.0

    private var pollInterval: TimeInterval = 0.25

    /// 连续多少次轮询没读到歌；满 4 次（约 1 秒）才降到空闲档，
    /// 刚切歌/刚开始播的那 1 秒内保持 0.25 秒快档，不漏歌。
    private var idlePolls = 0

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

        // 1.0.7 修复：1.0.6 移植空闲节能时丢了这行，state 永远是 nil，
        // 新歌联网搜到的词进不了快照（loadLyrics 的 guard 永远过不去）。
        state = newState

        let key = newState.trackKey

        // ---- 换歌：立刻写入新快照（含已有缓存歌词），再决定是否联网搜 ----
        if key != lastTrackKey {

            lastTrackKey = key
            lastStatus = newState.status
            lastHUDLyricIndex = nil

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

            // 缓存里有词就立刻发 HUD，不等下一个 tick。
            publishHUDLyrics()

            return
        }

        // ---- 同一首歌，播放状态变化：即时同步进度基准 ----
        if lastStatus != newState.status {

            lastStatus = newState.status

            switch newState.status {

            case .playing:
                message = "正在播放"
                savePlayback(newState)

            case .paused:
                message = "播放已暂停"
                savePlayback(newState)

            case .stopped:
                message = "播放已停止"
                savePlayback(newState)

            case .interrupted:
                message = "播放被中断"
                savePlayback(newState)

            case .unknown:
                message = "播放状态未知"
            }

            LyricLogger.log(message)
        }

        publishHUDLyrics()
    }

    // 悬浮歌词同步：每秒轮询时按快照 + 当前进度算出上一句/当前句/下一句，
    // 当前行下标变了才发给 HUD 进程。挑行算法和 Widget 一样：
    // 最后一句 time <= elapsed 的行是当前行（LyricStore.currentLyric 同款）。
    private func publishHUDLyrics() {

        guard
            let snapshot = LyricStore.load(),
            !snapshot.lyrics.isEmpty
        else {
            lastHUDLyricIndex = nil
            return
        }

        let elapsed = LyricStore.currentElapsed(
            snapshot,
            at: Date()
        )

        guard
            let index = snapshot.lyrics.lastIndex(
                where: { $0.time <= elapsed }
            )
        else {
            return
        }

        guard index != lastHUDLyricIndex else {
            return
        }
        lastHUDLyricIndex = index

        LyricsHUDBridge.update(
            title: snapshot.title,
            previous: index > 0
                ? snapshot.lyrics[index - 1].text
                : "",
            current: snapshot.lyrics[index].text,
            next: index + 1 < snapshot.lyrics.count
                ? snapshot.lyrics[index + 1].text
                : ""
        )
    }

    /// 检测到新歌时立即发布快照：进度基准对齐当前 position，
    /// 歌词优先用本地缓存，没有就留空（等联网结果），但歌名/进度不延迟。
    /// （皇上本地版，1.0.6 移植。）
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

    private func savePlayback(
        _ state: PlaybackState
    ) {

        guard var snapshot = LyricStore.load() else {
            return
        }

        guard
            snapshot.title == state.track.title,
            snapshot.artist == state.track.artist
        else {
            return
        }

        snapshot.startedAt = Date()

        snapshot.elapsedWhenPaused = state.position

        snapshot.isPlaying =
            state.status == .playing

        LyricStore.save(snapshot)

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 用户在设置里调过的外观（透明度/字体），写快照时保留，
    /// 别像以前那样每次搜到词就写死 0.65/22。
    /// （皇上本地版 currentAppearance，1.0.6 移植。）
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

            // 换歌已取消：后面的结果不要再写进新歌的快照。
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

            // 换歌取消的旧搜词：静默返回，不报错、不改 message。
            return

        } catch {

            message = "歌词搜索失败：\(error.localizedDescription)"
            LyricLogger.log(message)
        }
    }

    /// 把搜到的歌词写进当前快照，进度基准取当下上报的 position。
    /// （皇上本地版，1.0.6 移植；替代原来写死透明度 0.65/字体 22 的整包重建。）
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
