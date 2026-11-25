import Foundation

// 注意：PlaybackStatus 不在这里重复定义，沿用现有的
// PlaybackEngine/PlaybackState.swift 里的那一个（5 个 case：
// playing/paused/stopped/interrupted/unknown，String + Codable）。
// 现有代码（AppleMusicAdapter、PlaybackCoordinator）已经在用 .interrupted，
// 这里如果再定义一个 4 case 的同名 enum，编译会报重复定义。

struct PlaybackSnapshot: Equatable {

    let track: TrackIdentifier?
    let status: PlaybackStatus
    let playbackTime: Double
    let duration: Double
    let applicationID: String?

    static let empty = PlaybackSnapshot(
        track: nil,
        status: .unknown,
        playbackTime: 0,
        duration: 0,
        applicationID: nil
    )
}

final class PlaybackStateEngine {

    private(set) var current = PlaybackSnapshot.empty

    var onTrackChanged: ((TrackIdentifier?) -> Void)?
    var onPlaybackChanged: ((PlaybackStatus) -> Void)?
    var onSnapshotChanged: ((PlaybackSnapshot) -> Void)?

    func update(_ snapshot: PlaybackSnapshot) {

        let old = current

        current = snapshot

        if old.track != snapshot.track {
            onTrackChanged?(snapshot.track)
        }

        if old.status != snapshot.status {
            onPlaybackChanged?(snapshot.status)
        }

        if old != snapshot {
            onSnapshotChanged?(snapshot)
        }
    }

    func reset() {
        update(.empty)
    }

    var isPlaying: Bool {
        current.status == .playing
    }

    var currentTrack: TrackIdentifier? {
        current.track
    }
}
