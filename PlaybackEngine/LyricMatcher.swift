import Foundation

struct LyricMatcher {

    static func bestMatch(
        records: [LRCLyricsRecord],
        track: MusicTrack
    ) -> LRCLyricsRecord? {

        // 2.0.6：有 syncedLyrics 或 lyricsfile 任一即可候选——
        // 只有 lyricsfile（无 syncedLyrics）的记录也有逐字数据，
        // 以前直接被 filter 掉。
        let candidates = records.filter {
            let hasSynced = !($0.syncedLyrics?.isEmpty ?? true)
            let hasFile = !($0.lyricsfile?.isEmpty ?? true)
            return (hasSynced || hasFile)
                && $0.instrumental != true
        }

        return candidates.max { lhs, rhs in

            score(lhs, track: track)
                < score(rhs, track: track)
        }
    }

    /// 2.0.6：去 private——歌卡的逐字门（PlaybackDashboardView）复用
    /// 同一份归一化，不再各写各的窄 normalize（只去空格会把「你好」
    /// 和「你 好」判成两行，逐字门白白关掉）。
    /// 注意：LyricsFileParser 不引这里——Widget target 也编
    /// LyricParser.swift 却不编本文件，它自带一份同规则归一化
    /// （run 46135798827 教训）。
    static func normalize(
        _ value: String
    ) -> String {

        value.lowercased()
            .filter {
                $0.isLetter || $0.isNumber
            }
    }

    // MARK: - 2.0.7：歌词搜索回退（翻唱歌手搜不到）

    /// 去掉歌名里的括号限定词：「晴天（杰伦）」→「晴天」，
    /// 「Hello (Remix)」→「Hello」。中英文括号都处理，多组都删；
    /// 括号不成对、或删完为空时返回原串，不动。
    static func stripBracketQualifier(
        _ title: String
    ) -> String {

        let opens = title.filter { $0 == "(" || $0 == "（" }.count
        let closes = title.filter { $0 == ")" || $0 == "）" }.count
        guard opens > 0, opens == closes else { return title }

        var out = ""
        var depth = 0
        for ch in title {
            if ch == "(" || ch == "（" {
                depth += 1
                continue
            }
            if ch == ")" || ch == "）" {
                depth = max(0, depth - 1)
                continue
            }
            if depth == 0 { out.append(ch) }
        }

        let stripped = out
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? title : stripped
    }

    /// LRCLIB 搜索回退阶梯（由严到松，去重）：
    ///   1. 歌名＋歌手
    ///   2. 去括号歌名＋歌手
    ///   3. 去括号歌名（不带歌手）
    ///   4. 原歌名（不带歌手）
    /// 实测：track=晴天＋artist=哇欣→[]（库里《晴天》只有周杰伦版，
    /// artist_name 会把翻唱版本滤空）；只拿歌名搜→20 条。
    /// 括号限定词同样让 track_name 匹配不到（「晴天（杰伦）」→[]）。
    /// 某一组返回空才试下一组；第一组有结果就停，不多发请求。
    static func searchAttempts(
        track: String,
        artist: String
    ) -> [(track: String, artist: String?)] {

        let stripped = stripBracketQualifier(track)
        let trimmedArtist = artist.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let withArtist: String? = trimmedArtist.isEmpty ? nil : trimmedArtist

        var attempts: [(track: String, artist: String?)] = []
        func add(_ t: String, _ a: String?) {
            let key = t.lowercased() + "|" + (a ?? "").lowercased()
            guard !attempts.contains(where: {
                $0.track.lowercased() + "|" + ($0.artist ?? "").lowercased() == key
            }) else { return }
            attempts.append((t, a))
        }
        add(track, withArtist)
        add(stripped, withArtist)
        add(stripped, nil)
        add(track, nil)
        return attempts
    }

    /// 歌名歌手互换防抖：相邻两次 poll 两字段正好互换，是同一首歌
    /// 在交换字段，不是换歌。实测汽水音乐「哇欣／晴天（杰伦）」
    /// 相邻两秒来回跳；只认「正好互换」，稳定换边后仍会走一次
    /// 换歌分支（只一次），不硬编。
    static func isSwappedPair(
        _ a: (title: String, artist: String),
        _ b: (title: String, artist: String)
    ) -> Bool {

        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let (at, aa, bt, ba) = (norm(a.title), norm(a.artist), norm(b.title), norm(b.artist))
        guard !at.isEmpty, !aa.isEmpty else { return false }
        return at == ba && aa == bt
    }

    private static func score(
        _ record: LRCLyricsRecord,
        track: MusicTrack
    ) -> Double {

        let targetTitle = normalize(track.title)
        let targetArtist = normalize(track.artist)

        let resultTitle = normalize(record.trackName)
        let resultArtist = normalize(record.artistName)

        var value = 0.0

        // 2.0.6：优先选有逐字数据的候选——同一首歌多个版本时，
        // 没逐字的记录即使歌名／歌手分高也不能赢，否则卡拉OK
        // 拿到的是永远没 words 的行。lyricsfile 在位是真凭据；
        // 只有 hasWordSync 标志、没文件时只给小分。
        if !(record.lyricsfile?.isEmpty ?? true) {
            value += 50
        } else if record.hasWordSync == true {
            value += 10
        }

        if targetTitle == resultTitle {
            value += 60
        } else if resultTitle.contains(targetTitle)
            || targetTitle.contains(resultTitle) {
            value += 30
        }

        if targetArtist == resultArtist {
            value += 40
        } else if resultArtist.contains(targetArtist)
            || targetArtist.contains(resultArtist) {
            value += 20
        }

        if let duration = track.duration {

            let difference = abs(
                duration - record.duration
            )

            if difference <= 2 {
                value += 20
            } else if difference <= 5 {
                value += 10
            }
        }

        return value
    }
}
