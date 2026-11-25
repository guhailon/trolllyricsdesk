import Foundation

@objcMembers
final class LyricsHUDBridge: NSObject {

    static func update(
        title: String,
        previous: String,
        current: String,
        next: String
    ) {
        let payload: [String: String] = [
            "title": title,
            "previous": previous,
            "current": current,
            "next": next
        ]

        TLLyricsIPC.publishLyrics(payload)
    }
}
