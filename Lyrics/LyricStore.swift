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

    /// 当前是否检测不到任何播放器。由 poll() 写入，悬浮窗读取后决定
    /// 是显示歌词还是提示——避免无音乐时悬浮窗停留在上一次的歌词快照。
    static let noMusicKey = "lyric.noMusic"

    /// 悬浮窗开关变化通知：双击隐藏 / 主界面拨开关时互相同步。
    /// 两侧用的是不同的 UserDefaults 实例，写值不会自动刷新对方，需显式通知。
    static let floatingEnabledChanged = Notification.Name("TLDSFloatingEnabledChanged")

    /// 歌词时间偏移（秒，存 App Group，主 App / 悬浮窗 / Widget 共用）。
    /// 正值 = 歌词提前显示，负值 = 延后显示。
    ///
    /// 第二次修复：改为「逐歌」记忆。LRCLIB 的歌词由不同用户上传，
    /// 每首歌的时间轴偏差各不相同（有的偏早、有的偏晚），全局一个值
    /// 无法同时满足——调好 A 歌就会弄坏 B 歌，正是「有的歌不同步」。
    /// 这里按稳定歌曲标识分别存，每首歌调一次，之后自动套用。
    private static let offsetKeyPrefix = "lyric.timeOffset|"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    /// 某首歌的时间偏移 key（用稳定歌曲标识，字段型播放器换字段也不变）。
    private static func offsetKey(title: String, artist: String) -> String {
        offsetKeyPrefix + stableSongIdentity(title: title, artist: artist)
            .lowercased()
    }

    /// 读取指定歌曲的时间偏移。没调过返回 0（保持旧行为）。
    static func timeOffset(title: String, artist: String) -> TimeInterval {
        let key = offsetKey(title: title, artist: artist)
        guard let raw = defaults?.object(forKey: key) else { return 0 }
        return (raw as? Double) ?? (raw as? NSNumber)?.doubleValue ?? 0
    }

    /// 从快照读取当前歌曲的偏移。悬浮窗 / Widget / 主界面统一走这里。
    static func timeOffset(_ snapshot: LyricSnapshot) -> TimeInterval {
        timeOffset(title: snapshot.title, artist: snapshot.artist)
    }

    /// 保存某首歌的时间偏移。
    static func setTimeOffset(
        _ value: TimeInterval,
        title: String,
        artist: String
    ) {
        defaults?.set(value, forKey: offsetKey(title: title, artist: artist))
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

        // 叠加这首歌自己的校正偏移：正值让歌词提前出现，抵消 LRC 时间轴偏晚。
        // 逐歌存储，调一首不影响其他歌。
        let elapsed = currentElapsed(
            snapshot,
            at: date
        ) + timeOffset(snapshot)

        return snapshot.lyrics.last {
            $0.time <= elapsed
        }
    }

    /// 识别「歌词被塞进 artist 字段」的播放器。
    /// 实测上报格式是 "歌名 — 歌手"（如 "为什么 — 庄妮" / "谁的生活不是鸡零狗碎 — 李认针"），
    /// 歌手名在尾段；artist 放的是逐句变化的歌词。判定必须只看尾段歌手名：
    /// 只要 artist 不等于尾段歌手，就认定它是歌词，歌词始终显示在上面。
    /// 旧逻辑只比对前段且要求 "前段 != artist"，当某句歌词恰好等于歌名
    /// （如歌词 "为什么"、title "为什么 — 庄妮"）时会突然判成正常播放器，
    /// 把歌词翻到下面——这正是「本来正常，突然乱识别」的原因。
    /// 正常播放器（artist 就是尾段歌手本人）返回 false。
    static func artistCarriesLyric(title: String, artist: String) -> Bool {
        let separators = [" — ", " – ", " - ", "—", "–"]
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtist.isEmpty else { return false }

        for sep in separators {
            guard let range = title.range(of: sep) else { continue }
            let head = String(title[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(title[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !head.isEmpty, !tail.isEmpty else { continue }

            // 「歌名 — 歌手」：尾段是歌手名，artist 与它不同就是歌词。
            // 条件只看尾段，和歌词库是否命中、歌词长短都无关，因此稳定。
            if tail.count <= 8, trimmedArtist != tail {
                return true
            }
            // 兼容「歌手 — 歌名」：首段是歌手且 artist 就是歌手本人 → 正常播放器。
            if head.count <= 8, tail.count > 8, trimmedArtist == head {
                return false
            }
        }
        return false
    }

    // MARK: - 歌词位置识别（title / artist 字段会互换）

    /// 歌词所在字段。
    enum LyricLocation {
        case artist  /// 歌词在 artist 字段
        case title   /// 歌词在 title 字段
        case unknown /// 判定不了，调用方维持「title 在上」的原布局
    }

    /// 拆出 "A — B" 型「歌曲标识串」的两段；不是这种格式返回 nil。
    private static func songIdentityParts(
        _ text: String
    ) -> (head: String, tail: String)? {
        let separators = [" — ", " – ", " - ", "—", "–"]
        for sep in separators {
            guard let range = text.range(of: sep) else { continue }
            let head = String(text[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty, !tail.isEmpty {
                return (head, tail)
            }
        }
        return nil
    }

    /// 标识串里是否有一段等于 part——用于排除「artist 其实就是歌手名」的正常播放器。
    private static func identity(_ text: String, hasPart part: String) -> Bool {
        guard let parts = songIdentityParts(text) else { return false }
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "")
        }
        let p = norm(part)
        return norm(parts.head) == p || norm(parts.tail) == p
    }

    /// 稳定判断歌词在 title 还是 artist 字段。
    ///
    /// 实测某些播放器会在两个字段间来回交换：
    ///   某帧 title = "歌手 — 歌名"、artist = 当前歌词；
    ///   下一帧 title = 当前歌词、artist = "歌手 — 歌名"。
    /// 只判断「artist 是不是歌词」会在交换后翻转，导致歌词一会在上一会在下。
    /// 稳定的信号是「谁是歌曲标识串」：标识串整首歌不变且带 " — " 分隔符，
    /// 歌词逐句变化且通常不带分隔符，所以先认出标识串，另一字段就是歌词。
    static func lyricLocation(
        title: String,
        artist: String,
        lyricTexts: Set<String> = []
    ) -> LyricLocation {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !a.isEmpty else { return .unknown }

        func norm(_ s: String) -> String {
            s.replacingOccurrences(of: " ", with: "")
        }

        let titleIsIdentity = songIdentityParts(t) != nil
        let artistIsIdentity = songIdentityParts(a) != nil

        if titleIsIdentity && !artistIsIdentity {
            // title 是标识串 → artist 是歌词；artist 正好是标识串里的歌手名则不算。
            return identity(t, hasPart: a) ? .unknown : .artist
        }
        if artistIsIdentity && !titleIsIdentity {
            return identity(a, hasPart: t) ? .unknown : .title
        }

        // 两边都不像标识串：用歌词库命中判断。
        let inTitle = lyricTexts.contains(norm(t))
        let inArtist = lyricTexts.contains(norm(a))
        if inArtist && !inTitle { return .artist }
        if inTitle && !inArtist { return .title }

        // 兜底：artist 是 8 字以上纯中文短句，按歌词处理。
        let looksLikeLyric = norm(a).count >= 8 &&
            norm(a).unicodeScalars.allSatisfy {
                $0.value >= 0x4E00 && $0.value <= 0x9FFF
            }
        return looksLikeLyric ? .artist : .unknown
    }

    /// 取用于「换歌判定 / 歌词缓存」的稳定歌曲标识。
    /// title / artist 里带 " — " 分隔符的那一段是整首歌固定的「歌手 — 歌名」，
    /// 另一段是逐句变化的歌词；交换两字段后取到的仍是同一个串，因此稳定。
    /// 两边都没有分隔符（正常播放器）时退回 title，保持原行为。
    static func stableSongIdentity(title: String, artist: String) -> String {
        if songIdentityParts(title) != nil { return title }
        if songIdentityParts(artist) != nil { return artist }
        return title
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
