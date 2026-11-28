import Foundation

struct LyricParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):([0-5]\d)(?:\.(\d{1,3}))?\]"#)
        let wordPattern = try! NSRegularExpression(pattern: #"<(\d{1,3}):([0-5]\d)(?:\.(\d{1,3}))?>"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"(?im)^\s*\[offset:\s*([+-]?\d+)\s*\]"#)
        let full = NSRange(lrc.startIndex..<lrc.endIndex, in: lrc)
        let offset = offsetPattern.matches(in: lrc, range: full).last.flatMap { Range($0.range(at: 1), in: lrc) }.flatMap { Double(lrc[$0]) } ?? 0
        var result: [LyricLine] = []
        for line in lrc.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = timestamp.matches(in: line, range: range)
            guard let last = matches.last, let end = Range(last.range, in: line)?.upperBound else { continue }
            let raw = String(line[end...]).trimmingCharacters(in: .whitespaces)
            let wordRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            let tags = wordPattern.matches(in: raw, range: wordRange)
            let text = wordPattern.stringByReplacingMatches(in: raw, range: wordRange, withTemplate: "")
            var words: [LyricWord] = []
            for (index, tag) in tags.enumerated() {
                guard let m = Range(tag.range(at: 1), in: raw), let sec = Range(tag.range(at: 2), in: raw),
                      let minute = Double(raw[m]), let second = Double(raw[sec]),
                      let start = Range(tag.range, in: raw)?.upperBound else { continue }
                let finish = index + 1 < tags.count ? (Range(tags[index + 1].range, in: raw)?.lowerBound ?? raw.endIndex) : raw.endIndex
                let fraction = Range(tag.range(at: 3), in: raw).flatMap { Double("0." + raw[$0]) } ?? 0
                let wordTime = max(0, minute * 60 + second + fraction - offset / 1000)
                if start < finish { words.append(LyricWord(time: wordTime, text: String(raw[start..<finish]))) }
            }
            for match in matches {
                guard let m = Range(match.range(at: 1), in: line), let s = Range(match.range(at: 2), in: line), let minutes = Double(line[m]), let seconds = Double(line[s]) else { continue }
                let fraction = Range(match.range(at: 3), in: line).flatMap { Double("0." + line[$0]) } ?? 0
                let time = max(0, minutes * 60 + seconds + fraction - offset / 1000)
                result.append(LyricLine(time: time, text: text, words: matches.count == 1 && !words.isEmpty ? words.sorted { $0.time < $1.time } : nil))
            }
        }
        return result.enumerated().sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }.map { $0.element }
    }
}
