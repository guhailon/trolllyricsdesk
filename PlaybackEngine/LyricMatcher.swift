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

    /// 2.0.6：去 private——歌卡的逐字门（PlaybackDashboardView）与
    /// lyricsfile 行对齐（LyricsFileParser）复用同一份归一化，
    /// 不再各写各的窄 normalize（只去空格会把「你好」和「你 好」
    /// 判成两行，逐字门白白关掉）。
    static func normalize(
        _ value: String
    ) -> String {

        value.lowercased()
            .filter {
                $0.isLetter || $0.isNumber
            }
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
