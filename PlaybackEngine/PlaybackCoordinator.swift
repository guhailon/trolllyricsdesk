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

    init(adapter: any PlaybackAdapter) {
        self.adapter = adapter
    }

    func start() {

        stop()

        message = "正在检测音乐..."
        LyricLogger.log("开始检测音乐")

        poll()

        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
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
    }

    private func poll() {

        guard let newState = adapter.currentState() else {

            message = "没有检测到可读取的音乐"

            return
        }

        state = newState

        let key = newState.trackKey

        // 检测歌曲变化
        if key != lastTrackKey {

            lastTrackKey = key
            lastStatus = newState.status

            message = "检测到新歌曲：\(newState.track.title)"
            LyricLogger.log("检测到新歌曲：\(newState.track.title) - \(newState.track.artist)")

            Task {
                await loadLyrics(for: newState.track)
            }

            return
        }

        // 检测播放状态变化
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

    private func loadLyrics(
        for track: MusicTrack
    ) async {

        message = "正在搜索歌词：\(track.title)"

        do {

            let records = try await LRCLibClient.shared.search(
                track: track
            )

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

            let current = state

            let snapshot = LyricSnapshot(
                title: track.title,
                artist: track.artist,
                lyrics: lines,
                startedAt: Date(),
                isPlaying: current?.status == .playing,
                elapsedWhenPaused: current?.position ?? 0,
                opacity: 0.65,
                fontSize: 22
            )

            LyricStore.save(snapshot)

            WidgetCenter.shared.reloadAllTimelines()

            message = "歌词匹配成功"
            LyricLogger.log("歌词匹配成功：\(track.title)")

        } catch {

            message = "歌词搜索失败：\(error.localizedDescription)"
            LyricLogger.log(message)
        }
    }

    private func trackKey(
        _ track: MusicTrack
    ) -> String {

        "\(track.platform.rawValue)|\(track.title)|\(track.artist)"
            .lowercased()
    }
}
