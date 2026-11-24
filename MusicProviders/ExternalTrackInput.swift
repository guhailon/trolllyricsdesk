import Foundation

enum ExternalTrackInput {

    static func makeTrack(
        platform: MusicPlatform,
        title: String,
        artist: String,
        album: String = "",
        duration: Double? = nil
    ) -> MusicTrack {

        MusicTrack(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            platform: platform
        )
    }
}
