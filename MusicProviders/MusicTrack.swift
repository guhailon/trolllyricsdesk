import Foundation

enum MusicPlatform: String, Codable, CaseIterable, Identifiable {
    case appleMusic = "Apple Music"
    case netEase = "网易云音乐"
    case qqMusic = "QQ音乐"
    case manual = "手动输入"

    var id: String { rawValue }

    static func fromBundleIdentifier(_ identifier: String?) -> MusicPlatform {
        switch identifier?.lowercased() {
        case "com.apple.music": return .appleMusic
        case "com.netease.cloudmusic": return .netEase
        case "com.tencent.qqmusic": return .qqMusic
        default: return .manual
        }
    }
}

struct MusicTrack: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double?
    var platform: MusicPlatform

    init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        album: String = "",
        duration: Double? = nil,
        platform: MusicPlatform
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.platform = platform
    }
}
