import Foundation

struct LyricSnapshot: Codable {

    var title: String
    var artist: String

    var lyrics: [LyricLine]

    var startedAt: Date
    var isPlaying: Bool

    var elapsedWhenPaused: TimeInterval

    var opacity: Double
    var fontSize: Double
}

enum LyricStore {

    static let groupID =
        "group.com.hailong.TrollLyricsDesk"

    static let dataKey = "lyric.snapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    static func save(_ snapshot: LyricSnapshot) {

        guard let data = try? JSONEncoder().encode(
            snapshot
        ) else {
            return
        }

        defaults?.set(data, forKey: dataKey)
    }

    static func load() -> LyricSnapshot? {

        guard
            let data = defaults?.data(forKey: dataKey),
            let snapshot = try? JSONDecoder().decode(
                LyricSnapshot.self,
                from: data
            )
        else {
            return nil
        }

        return snapshot
    }

    static func currentElapsed(
        _ snapshot: LyricSnapshot,
        at date: Date
    ) -> TimeInterval {

        if snapshot.isPlaying {
            return max(
                0,
                snapshot.elapsedWhenPaused
                    + max(0, date.timeIntervalSince(snapshot.startedAt))
            )
        }

        return snapshot.elapsedWhenPaused
    }

    static func currentLyric(
        _ snapshot: LyricSnapshot,
        at date: Date
    ) -> LyricLine? {

        let elapsed = currentElapsed(
            snapshot,
            at: date
        )

        return snapshot.lyrics.last {
            $0.time <= elapsed
        }
    }

    // MARK: - 歌词本地缓存
    // 搜到过的歌词按「歌名|歌手」存进 App Group，下次再播同一首歌
    // 直接从缓存读，做到「播放即显示」，不必等网络搜索。

    private static func cacheKey(title: String, artist: String) -> String {
        "lyric.cache|\(title.lowercased())|\(artist.lowercased())"
    }

    struct CachedLyric: Codable {
        let lines: [LyricLine]
        let savedAt: Date
    }

    static func cachedLyrics(
        title: String,
        artist: String
    ) -> [LyricLine]? {
        guard
            let data = defaults?.data(
                forKey: cacheKey(title: title, artist: artist)
            ),
            let cached = try? JSONDecoder().decode(
                CachedLyric.self,
                from: data
            ),
            !cached.lines.isEmpty
        else {
            return nil
        }
        return cached.lines
    }

    static func cacheLyrics(
        _ lines: [LyricLine],
        title: String,
        artist: String
    ) {
        let cached = CachedLyric(lines: lines, savedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else {
            return
        }
        defaults?.set(
            data,
            forKey: cacheKey(title: title, artist: artist)
        )
    }
}
