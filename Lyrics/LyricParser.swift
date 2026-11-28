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

// MARK: - 2.0.6：LRCLIB lyricsfile（YAML）逐字解析
//
// 审计结论（2.0.4 卡拉OK没效果的根因）：代码只读 syncedLyrics（只有行级
// 时间戳），逐字数据在 lyricsfile 字段里；2.0.4 的逐字模型期望增强 LRC
// 内联 <mm:ss.xx> 标记，在 syncedLyrics 里永远找不到。
// lyricsfile 是 YAML 结构、不是 LRC 文本，绝不能喂给 LyricParser.parse。
// 形状（LRCLIB 返回）：
//   lines:
//   - text: '...'
//     start_ms: 1234
//     words:
//     - text: '...'
//       start_ms: 1234
//       end_ms: 1567
// 手写最小解析，只取 lines[].text / start_ms / words[].text /
// words[].start_ms；不引新依赖。字段缺失或解析失败就静默返回空，
// 调用方退回行级，绝不崩溃、绝不拦门。
struct LyricsFileLine {
    var text: String
    var startMs: Int
    var words: [LyricsFileWord]
}

struct LyricsFileWord {
    var text: String
    var startMs: Int
}

enum LyricsFileParser {

    /// 最小 YAML 解析：只认 lines / words 两层 "- " 列表与 text / start_ms
    /// 两个键，其余键（metadata、end_ms、duration 等）一律忽略。
    /// 容错：缩进、引号、空值、未知键都不抛错，解析不到就返回空数组。
    static func parse(_ yaml: String) -> [LyricsFileLine] {
        var lines: [LyricsFileLine] = []
        var curLine: LyricsFileLine?
        var curWord: LyricsFileWord?
        var inLines = false
        var inWords = false
        var lineDashIndent = 0
        // 2.0.6：plain: | 字面块（整首歌的纯文本歌词）里的行不是键值对，
        // 其中以 "- " 开头的歌词行绝不能被当成新的行／词项；块内行一律跳过，
        // 直到出现缩进不深于 plain: 键的行（块结束）。
        var inPlainBlock = false
        var plainIndent = 0

        func flushWord() {
            if let w = curWord, !w.text.isEmpty {
                curLine?.words.append(w)
            }
            curWord = nil
        }
        func flushLine() {
            flushWord()
            if let l = curLine, !l.text.isEmpty {
                lines.append(l)
            }
            curLine = nil
            inWords = false
        }
        func apply(_ s: String, indent: Int) {
            guard let colon = s.firstIndex(of: ":") else { return }
            let key = s[..<colon].trimmingCharacters(in: .whitespaces)
            let rawValue = s[s.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            switch key {
            case "words":
                // "words:" 开词块；"words: []" 是空词块，不开。
                inWords = rawValue != "[]"
            case "plain":
                // "plain: |"（或 ">"）开字面块：块内行全是歌词正文，
                // 不再按 "- "／"key:" 解析，直到缩进回到本键一级。
                if rawValue == "|" || rawValue == ">" || rawValue.hasPrefix("|") || rawValue.hasPrefix(">") {
                    inPlainBlock = true
                    plainIndent = indent
                }
            case "text":
                let text = unquote(rawValue)
                if inWords {
                    if curWord == nil {
                        curWord = LyricsFileWord(text: "", startMs: 0)
                    }
                    curWord?.text = text
                } else {
                    curLine?.text = text
                }
            case "start_ms":
                let ms = Int(Double(unquote(rawValue)) ?? 0)
                if inWords {
                    if curWord == nil {
                        curWord = LyricsFileWord(text: "", startMs: 0)
                    }
                    curWord?.startMs = ms
                } else {
                    curLine?.startMs = ms
                }
            default:
                break
            }
        }

        for raw in yaml.components(separatedBy: .newlines) {
            let stripped = raw.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty || stripped.hasPrefix("#") { continue }
            let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            if stripped == "lines:" || stripped.hasPrefix("lines:") {
                inLines = true
                continue
            }
            guard inLines else { continue }
            if inPlainBlock {
                if indent > plainIndent { continue }
                inPlainBlock = false
            }
            if stripped == "-" || stripped.hasPrefix("- ") {
                let content = stripped == "-"
                    ? "" : String(stripped.dropFirst(2))
                if !inWords || indent <= lineDashIndent {
                    // 新行（词块外的 "-"，或与行 "-" 同级／更浅的 "-"）。
                    flushLine()
                    lineDashIndent = indent
                    curLine = LyricsFileLine(text: "", startMs: 0, words: [])
                    inWords = false
                } else {
                    // 词块里的 "-"：新词。
                    flushWord()
                    curWord = LyricsFileWord(text: "", startMs: 0)
                }
                if !content.isEmpty { apply(content, indent: indent) }
                continue
            }
            apply(stripped, indent: indent)
        }
        flushLine()
        return lines
    }

    /// 去 YAML 引号：单引号 '' → '；双引号 \" \\ 作最小还原。
    /// 无引号的值原样返回。
    private static func unquote(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        } else if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return s
    }

    /// 把 lyricsfile 的逐字时间戳映射到行级解析结果上：行时间仍用
    /// syncedLyrics 的行级时间戳，只换 words（time = start_ms / 1000）。
    /// 行数一致时按下标映射；不一致时按归一化行文本对齐；
    /// 都对不上就保留原 words（多为 nil，即行级退回）。
    static func mergingWordSync(
        into lines: [LyricLine],
        lyricsFile: String
    ) -> [LyricLine] {
        let fileLines = parse(lyricsFile)
        guard !fileLines.isEmpty else { return lines }
        var out = lines
        func wordsOf(_ fileLine: LyricsFileLine) -> [LyricWord]? {
            let words = fileLine.words
                .filter { !$0.text.isEmpty }
                .map {
                    LyricWord(
                        time: max(0, Double($0.startMs) / 1000.0),
                        text: $0.text
                    )
                }
                .sorted { $0.time < $1.time }
            return words.isEmpty ? nil : words
        }
        if fileLines.count == lines.count {
            for i in out.indices {
                if let words = wordsOf(fileLines[i]) {
                    out[i].words = words
                }
            }
        } else {
            for i in out.indices {
                let norm = LyricMatcher.normalize(out[i].text)
                guard !norm.isEmpty else { continue }
                if let fileLine = fileLines.first(where: {
                    LyricMatcher.normalize($0.text) == norm
                }), let words = wordsOf(fileLine) {
                    out[i].words = words
                }
            }
        }
        return out
    }

    /// syncedLyrics 缺失时，用 lyricsfile 单独建行：
    /// 行时间 = start_ms / 1000，words 同上。
    static func linesFromLyricsFile(_ yaml: String) -> [LyricLine] {
        parse(yaml).map { fileLine in
            let words = fileLine.words
                .filter { !$0.text.isEmpty }
                .map {
                    LyricWord(
                        time: max(0, Double($0.startMs) / 1000.0),
                        text: $0.text
                    )
                }
                .sorted { $0.time < $1.time }
            return LyricLine(
                time: max(0, Double(fileLine.startMs) / 1000.0),
                text: fileLine.text,
                words: words.isEmpty ? nil : words
            )
        }
    }
}
