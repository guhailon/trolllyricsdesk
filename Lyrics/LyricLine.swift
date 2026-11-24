import Foundation

struct LyricLine: Codable, Identifiable {
    var id: UUID
    var time: TimeInterval
    var text: String

    init(
        id: UUID = UUID(),
        time: TimeInterval,
        text: String
    ) {
        self.id = id
        self.time = time
        self.text = text
    }
}
