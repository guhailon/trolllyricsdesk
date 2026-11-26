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

    static var isLiveContainer: Bool {
        Bundle.main.object(forInfoDictionaryKey: "TLDSLiveContainer") as? Bool == true
    }

    static var defaults: UserDefaults? {
        isLiveContainer ? .standard : UserDefaults(suiteName: groupID)
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
                    + date.timeIntervalSince(
                        snapshot.startedAt
                    )
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

// MARK: - 授权激活（1.0.3）
// 整个 App 第一次打开就要码：激活标记存在 App Group 里，App 与 Widget 共用。
// 码表只在服务端（Cloudflare Pages Functions），App 里没有任何码值，
// 这里只有接口地址和标记键。验证走 POST /api/verify，服务端比对不分大小写，
// App 端同样先 trim 再大写。
// 本文件同时在 App 与 Widget 两个 target 里（两边都要读激活标记），
// 所以只放 Foundation 层面的键与读写，不放任何 SwiftUI／网络代码。
enum ActivationStore {

    static let verifyURLString =
        "https://guhailong-repo.pages.dev/api/verify"

    static let activatedKey = "tld.activated"
    static let activationTypeKey = "tld.activationType"

    static var isActivated: Bool {
        LyricStore.defaults?.bool(forKey: activatedKey) ?? false
    }

    static var activationType: String? {
        LyricStore.defaults?.string(forKey: activationTypeKey)
    }

    static func markActivated(type: String) {
        LyricStore.defaults?.set(true, forKey: activatedKey)
        LyricStore.defaults?.set(type, forKey: activationTypeKey)
    }
}
