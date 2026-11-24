import Foundation

enum LocalLRCImporter {

    static func read(from url: URL) throws -> String {

        let hasAccess = url.startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try String(
            contentsOf: url,
            encoding: .utf8
        )
    }

    static func parse(from url: URL) throws -> [LyricLine] {

        let content = try read(from: url)

        let lyrics = LyricParser.parse(content)

        guard !lyrics.isEmpty else {
            throw ImportError.invalidLyrics
        }

        return lyrics
    }

    enum ImportError: LocalizedError {
        case invalidLyrics

        var errorDescription: String? {
            "没有识别到有效的 LRC 时间标签"
        }
    }
}
