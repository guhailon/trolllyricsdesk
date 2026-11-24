import Foundation

enum PlaybackStatus: String, Codable {
    case playing
    case paused
    case stopped
    case interrupted
    case unknown
}

struct PlaybackState: Equatable {
    let track: MusicTrack
    let status: PlaybackStatus
    let position: TimeInterval
    let duration: TimeInterval?
    let observedAt: Date

    var trackKey: String {
        "\(track.platform.rawValue)|\(track.title)|\(track.artist)"
            .lowercased()
    }
}
