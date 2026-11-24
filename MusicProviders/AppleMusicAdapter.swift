import Foundation
import MediaPlayer

@MainActor
final class AppleMusicAdapter: PlaybackAdapter {

    let platform: MusicPlatform = .appleMusic

    private let player =
        MPMusicPlayerController.systemMusicPlayer

    func currentState() -> PlaybackState? {

        guard let item = player.nowPlayingItem else {
            return nil
        }

        let title = item.value(
            forProperty: MPMediaItemPropertyTitle
        ) as? String ?? "未知歌曲"

        let artist = item.value(
            forProperty: MPMediaItemPropertyArtist
        ) as? String ?? "未知歌手"

        let album = item.value(
            forProperty: MPMediaItemPropertyAlbumTitle
        ) as? String ?? ""

        let duration = item.value(
            forProperty: MPMediaItemPropertyPlaybackDuration
        ) as? Double

        let position = max(
            0,
            player.currentPlaybackTime
        )

        let status: PlaybackStatus

        switch player.playbackState {

        case .playing:
            status = .playing

        case .paused:
            status = .paused

        case .stopped:
            status = .stopped

        case .interrupted:
            status = .interrupted

        default:
            status = .unknown
        }

        let track = MusicTrack(
            id: item.playbackStoreID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            platform: .appleMusic
        )

        return PlaybackState(
            track: track,
            status: status,
            position: position,
            duration: duration,
            observedAt: Date()
        )
    }
}

import MediaPlayer

func requestMusicPermission(
    completion: @escaping (Bool) -> Void
) {
    MPMediaLibrary.requestAuthorization { status in

        DispatchQueue.main.async {
            completion(status == .authorized)
        }
    }
}
