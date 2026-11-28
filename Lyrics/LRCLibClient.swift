import Foundation

struct LRCLyricsRecord: Codable, Identifiable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
    /// 2.0.6：逐字时间戳不在 syncedLyrics 里，在这个 YAML 字段里
    /// （每行 words 数组带 start_ms）。LRCLIB 旧记录可能没有该字段，
    /// 故 optional——解码缺失时为 nil，不影响旧记录。
    let lyricsfile: String?
    /// 2.0.6：LRCLIB 标的有无逐字同步（若服务端返回）；仅作打分参考，
    /// 真正的逐字数据以 lyricsfile 为准。
    let hasWordSync: Bool?
}

enum LRCLibError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notFound
    case rateLimited
    case serverError(Int)
    case noSyncedLyrics

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "搜索地址无效"
        case .invalidResponse:
            return "服务器返回的数据无效"
        case .notFound:
            return "没有找到匹配的歌词"
        case .rateLimited:
            return "请求过于频繁，请稍后再试"
        case .serverError(let code):
            return "服务器错误：\(code)"
        case .noSyncedLyrics:
            return "该歌曲暂时没有同步歌词"
        }
    }
}

final class LRCLibClient {

    static let shared = LRCLibClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem]
    ) throws -> URLRequest {

        var components = URLComponents(
            string: "https://lrclib.net"
        )!

        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw LRCLibError.invalidURL
        }

        var request = URLRequest(url: url)

        request.httpMethod = "GET"

        request.setValue(
            "TrollLyricsDesk/0.2 (iOS 16)",
            forHTTPHeaderField: "User-Agent"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        return request
    }

    func search(
        track: MusicTrack
    ) async throws -> [LRCLyricsRecord] {

        let request = try makeRequest(
            path: "/api/search",
            queryItems: [
                URLQueryItem(
                    name: "track_name",
                    value: track.title
                ),
                URLQueryItem(
                    name: "artist_name",
                    value: track.artist
                )
            ]
        )

        let (data, response) =
            try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LRCLibError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            break
        case 404:
            throw LRCLibError.notFound
        case 429:
            throw LRCLibError.rateLimited
        default:
            throw LRCLibError.serverError(
                http.statusCode
            )
        }

        return try JSONDecoder().decode(
            [LRCLyricsRecord].self,
            from: data
        )
    }

    func fetch(
        id: Int
    ) async throws -> LRCLyricsRecord {

        let request = try makeRequest(
            path: "/api/get/\(id)",
            queryItems: []
        )

        let (data, response) =
            try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LRCLibError.invalidResponse
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 429 {
                throw LRCLibError.rateLimited
            }

            throw LRCLibError.serverError(
                http.statusCode
            )
        }

        return try JSONDecoder().decode(
            LRCLyricsRecord.self,
            from: data
        )
    }

    func fetchSyncedLyrics(
        id: Int
    ) async throws -> String {

        let record = try await fetch(id: id)

        guard
            let lyrics = record.syncedLyrics,
            !lyrics.isEmpty
        else {
            throw LRCLibError.noSyncedLyrics
        }

        return lyrics
    }
}
