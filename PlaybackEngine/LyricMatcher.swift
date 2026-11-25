import Foundation

struct LyricMatcher {

    static func bestMatch(
        records: [LRCLyricsRecord],
        track: MusicTrack
    ) -> LRCLyricsRecord? {

        let candidates = records.filter {
            guard let lyrics = $0.syncedLyrics else {
                return false
            }

            return !lyrics.isEmpty
                && $0.instrumental != true
        }

        let eligible = candidates.filter { score($0, track: track) >= 80 }
        return eligible.max { lhs, rhs in

            score(lhs, track: track)
                < score(rhs, track: track)
        }
    }

    private static func normalize(
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

        guard !targetTitle.isEmpty, !resultTitle.isEmpty else { return 0 }
        guard targetTitle == resultTitle else { return 0 }
        guard !targetArtist.isEmpty, !resultArtist.isEmpty,
              targetArtist == resultArtist || targetArtist.contains(resultArtist) || resultArtist.contains(targetArtist) else { return 0 }
        if let duration = track.duration, duration > 0, record.duration > 0, abs(duration - record.duration) > 15 { return 0 }
        var value = 0.0

        if targetTitle == resultTitle {
            value += 60
        } else if resultTitle.contains(targetTitle)
            || targetTitle.contains(resultTitle) {
            value += 30
        }

        if !targetArtist.isEmpty && targetArtist == resultArtist {
            value += 40
        } else if !targetArtist.isEmpty && !resultArtist.isEmpty && (resultArtist.contains(targetArtist)
            || targetArtist.contains(resultArtist)) {
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
