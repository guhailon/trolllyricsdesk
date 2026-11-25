import Foundation

struct TrackIdentifier: Hashable {

    let title: String
    let artist: String
    let album: String

    init(
        title: String?,
        artist: String?,
        album: String?
    ) {
        self.title = Self.normalize(title)
        self.artist = Self.normalize(artist)
        self.album = Self.normalize(album)
    }

    private static func normalize(_ value: String?) -> String {
        guard let value else { return "" }
        return value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    var isValid: Bool {
        !title.isEmpty
    }
}
