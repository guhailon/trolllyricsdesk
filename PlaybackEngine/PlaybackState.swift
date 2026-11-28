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

    private let observedUptime = ProcessInfo.processInfo.systemUptime

    func estimatedPosition(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        let delta = status == .playing ? max(0, uptime - observedUptime) : 0
        let value = position + delta
        guard value.isFinite else { return 0 }
        if let duration, duration.isFinite, duration > 0 { return min(duration, max(0, value)) }
        return max(0, value)
    }

    var trackKey: String {
        "\(track.platform.rawValue)|\(track.title)|\(track.artist)"
            .lowercased()
    }
}
