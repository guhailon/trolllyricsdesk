import Foundation

struct LyricWord: Codable, Equatable {
    var time: TimeInterval
    var text: String
}

struct LyricLine: Codable, Identifiable {
    var id: UUID
    var time: TimeInterval
    var text: String
    var words: [LyricWord]?

    init(
        id: UUID = UUID(),
        time: TimeInterval,
        text: String,
        words: [LyricWord]? = nil
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.words = words
    }
}

extension LyricLine {
    func activeWord(at elapsed: TimeInterval) -> LyricWord? {
        words?.last { $0.time <= elapsed }
    }
}
