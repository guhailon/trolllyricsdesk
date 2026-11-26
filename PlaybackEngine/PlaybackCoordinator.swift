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
    /// 注意：ContentState 是 iOS 16.1 才有的类型，不能存成协调器的存储属性——
    /// 不带 @available 时 MinOS 15.0 下编不过，带了 @available Swift 也不允许
    /// 给存储属性标 potentially unavailable（1.0.1 第一版编失败，run 45737184426：
    /// stored properties cannot be marked potentially unavailable with '@available'）。
    /// 所以只存一个普通 Equatable 键结构，去重语义不变。
    private struct LiveLyricKey: Equatable {
        var title: String
        var artist: String
        var previous: String
        var current: String
        var next: String
        var isPlaying: Bool
        var lyricColorHex: Int
    }
    private var lastLiveState: LiveLyricKey?
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
            // 标记「当前无播放器」：悬浮窗据此清掉上一次的歌词，避免停留在旧内容。
            LyricStore.defaults?.set(true, forKey: LyricStore.noMusicKey)
            setMessage("没有检测到可读取的音乐")
            // state 也要清空：主界面卡片与悬浮窗看同一个结论
            if state != nil { state = nil }
            return
        }

        // 检测到播放器：解除无音乐标记（悬浮窗恢复显示歌词）
        if LyricStore.defaults?.bool(forKey: LyricStore.noMusicKey) == true {
            LyricStore.defaults?.set(false, forKey: LyricStore.noMusicKey)
        }

        let previous = state
        // 只在「界面可见内容」变化时才更新 state。
        // position 是浮点、observedAt 每次都不同，直接赋值会每 0.25s 触发
        // @Published → SwiftUI 整页重建，弹出菜单会跟着一闪一闪。
        if !isDisplayEquivalent(previous, newState) {
            state = newState
        }

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

        // ---- 同一首歌持续播放：实时同步歌词字段与进度 ----
        // 换歌分支上面已 return，走到这里一定是同一首歌。
        if newState.status == .playing {
            syncLiveLyricsAndProgress(newState)
        }

        // ---- 锁屏歌词（路子 A）：变行才推给 Live Activity ----
        publishLiveLyrics()
    }

    /// 锁屏歌词（路子 A）：按 0.25 秒轮询算当前行，完整状态变了才推 Live Activity。
    /// 算法与 Widget 的 currentLyric 同款（LyricStore.currentElapsed＋lastIndex）。
    /// 没词时同一首歌只推一次「♪ {title}」占位；还没唱到第一句时推 ♪ 标题＋
    /// 第一句当 next，不留上一首歌的词。读不到歌时 poll() 提前 return，不会走到这里。
    private func publishLiveLyrics() {
        // LiveContainer 宿主模式不推锁屏（宿主不支持 Live Activities）。
        guard !LyricStore.isLiveContainer else { return }
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
            // 去重用普通键结构比（ContentState 本身不能存成属性，见上面注释）。
            let key = LiveLyricKey(
                title: state.title,
                artist: state.artist,
                previous: state.previous,
                current: state.current,
                next: state.next,
                isPlaying: state.isPlaying,
                lyricColorHex: state.lyricColorHex
            )
            if key == lastLiveState && activityID == lastLiveActivityID {
                return
            }
            lastLiveState = key
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

    /// 同一首歌持续播放时，把播放器实时上报的歌词字段与进度同步进快照。
    ///
    /// 两类播放器都靠这里做到实时：
    /// - 字段型（逐句歌词塞进 title/artist，且两句之间会互换字段）：快照里的
    ///   title/artist 必须每句刷新，悬浮窗 / 卡片 / Widget 才能显示当前句。
    ///   trackKey 为防误判换歌已改成稳定标识，字段变化不再走换歌分支，
    ///   若这里不写回快照，歌词就会停在旧句（唱几个字才显示 / 卡住）。
    /// - 同步歌词型：歌词按快照进度从 lyrics 里取行，进度基准若偏小就会
    ///   「唱几个字才显示当前句」，这里用上报的真实进度持续校准，消除滞后。
    private func syncLiveLyricsAndProgress(_ newState: PlaybackState) {
        guard var snapshot = LyricStore.load() else { return }
        guard newState.status == .playing, snapshot.isPlaying else { return }

        // 同首歌才同步：用稳定标识比较，容忍字段型播放器两句之间互换 title / artist。
        let snapshotKey = LyricStore.stableSongIdentity(
            title: snapshot.title, artist: snapshot.artist
        )
        let liveKey = LyricStore.stableSongIdentity(
            title: newState.track.title, artist: newState.track.artist
        )
        guard snapshotKey == liveKey else { return }

        let fieldsChanged =
            snapshot.title != newState.track.title ||
            snapshot.artist != newState.track.artist

        let now = Date()
        let elapsed = LyricStore.currentElapsed(snapshot, at: now)

        // 关键（第二次修复）：持续播放时**以本地平滑时钟为准**，上报值只用来
        // 纠正真正的大失步（拖动进度条 / 播放器 seek / 后台恢复）。
        //
        // 上一版把阈值收紧到 0.25s，反而造成「有的歌慢半拍」：
        // MediaRemote 的 ElapsedTime / Timestamp 粒度粗（部分播放器只到整秒），
        // 反推出的 progress 带亚秒级抖动。阈值 0.25s 时，一有抖动就把基准
        // 硬重置到抖动的上报值，等于把本来平滑的本地时钟反复往回拉，
        // 歌词就稳定滞后几个字。收紧阈值 = 更频繁重置 = 更明显滞后。
        //
        // 现在阈值放宽到 2s：亚秒抖动一律忽略，本地时钟自己走；
        // 只有偏差超过 2s（确定是 seek / 失步）才重置基准。
        // 单首歌 LRC 时间轴的整体偏差交给「逐歌时间偏移」校正，互不干扰。
        let reportedNow = newState.position
            + max(0, now.timeIntervalSince(newState.observedAt))
        let drift = reportedNow - elapsed
        let needsProgressSync = abs(drift) > 2.0

        guard fieldsChanged || needsProgressSync else { return }

        snapshot.title = newState.track.title
        snapshot.artist = newState.track.artist
        if needsProgressSync {
            // 补偿后对齐到「此刻」的真实进度，并把基准时刻设为此刻，
            // 保证后续 currentElapsed 从正确起点继续走。
            snapshot.elapsedWhenPaused = max(0, reportedNow)
            snapshot.startedAt = now
        }
        snapshot.isPlaying = true

        LyricStore.save(snapshot)
        if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }
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
        if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }

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
        if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// 界面上真正显示的内容：歌名、歌手、状态、整秒进度。
    /// 这些不变就不更新 @Published state，避免无谓的视图重建（菜单闪烁）。
    private func isDisplayEquivalent(_ a: PlaybackState?, _ b: PlaybackState) -> Bool {
        guard let a = a else { return false }
        return a.track.title == b.track.title
            && a.track.artist == b.track.artist
            && a.status == b.status
            && Int(a.position) == Int(b.position)
            && a.trackKey == b.trackKey
    }

    /// message 只在文字真正变化时才更新，同样为了避免多余的视图重建。
    private func setMessage(_ newValue: String) {
        guard message != newValue else { return }
        message = newValue
    }

    private func currentAppearance() -> (opacity: Double, fontSize: Double) {
        guard let snapshot = LyricStore.load() else {
            return (1.0, 23)
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

        // 进度基准取「此刻」最新上报值，而不是可能滞后最多 1 秒的 state：
        // 搜词完成时才把歌词写进去，若用旧 state 的 position，歌词一开始就慢半拍，
        // 表现为唱了几个字才显示当前句。
        let live = adapter.currentState()
        let basePosition = live?.position ?? current.position
        let baseStatus = live?.status ?? current.status

        snapshot?.lyrics = lines
        snapshot?.startedAt = Date()
        snapshot?.elapsedWhenPaused = basePosition
        snapshot?.isPlaying = baseStatus == .playing

        guard let final = snapshot else {
            return
        }

        LyricStore.save(final)
        if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// 换歌判定的 key。某些播放器会在 title / artist 之间来回交换
    /// 「歌手 — 歌名」标识与逐句歌词，直接用两字段拼接会被误判成不停换歌，
    /// 每次都重置进度基准并重新搜词，歌词就会跳动。这里只用固定的标识串部分：
    /// 有 "A — B" 分隔符时取该字段（交换后仍是同一个串），否则退回原拼接。
    private func trackKey(
        _ track: MusicTrack
    ) -> String {

        let identity = LyricStore.stableSongIdentity(
            title: track.title,
            artist: track.artist
        )
        return "\(track.platform.rawValue)|\(identity)"
            .lowercased()
    }
}
