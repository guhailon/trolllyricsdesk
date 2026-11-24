import Foundation

struct LyricParser {

    static func parse(_ lrc: String) -> [LyricLine] {

        var result: [LyricLine] = []

        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return []
        }

        let lines = lrc.components(separatedBy: .newlines)

        for line in lines {

            let range = NSRange(
                line.startIndex..<line.endIndex,
                in: line
            )

            let matches = regex.matches(
                in: line,
                range: range
            )

            for match in matches {

                guard
                    let minuteRange = Range(
                        match.range(at: 1), in: line
                    ),
                    let secondRange = Range(
                        match.range(at: 2), in: line
                    ),
                    let textRange = Range(
                        match.range(at: 4), in: line
                    )
                else {
                    continue
                }

                let minutes = Double(
                    line[minuteRange]
                ) ?? 0

                let seconds = Double(
                    line[secondRange]
                ) ?? 0

                var fraction: Double = 0

                if let fractionRange = Range(
                    match.range(at: 3), in: line
                ) {
                    let raw = String(line[fractionRange])

                    fraction = Double(
                        "0." + raw
                    ) ?? 0
                }

                let time = minutes * 60
                    + seconds
                    + fraction

                let text = String(
                    line[textRange]
                ).trimmingCharacters(
                    in: .whitespaces
                )

                result.append(
                    LyricLine(
                        time: time,
                        text: text
                    )
                )
            }
        }

        return result.sorted {
            $0.time < $1.time
        }
    }
}
