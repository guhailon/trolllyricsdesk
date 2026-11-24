import Foundation

struct NetEaseAdapter {

    func makeTrack(
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
            platform: .netEase
        )
    }
}
