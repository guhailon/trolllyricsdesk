import Foundation

// 极简日志：写到 App 的 Documents/TrollLyricsDesk.log，
// 以后可以在设置页查看/分享（SettingsView 是 Lee 的文件，等他发）。
// 失败只记日志、显示暂无歌词，不崩。
enum LyricLogger {
    static let fileName = "TrollLyricsDesk.log"
    private static let maxBytes = 200 * 1024

    static var logURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let url = logURL else {
            return
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let fh = try FileHandle(forWritingTo: url)
                defer { try? fh.close() }
                try fh.seekToEnd()
                fh.write(line.data(using: .utf8) ?? Data())
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
            trimIfNeeded(url: url)
        } catch {
            // 日志写失败也不影响主流程，静默。
        }
    }

    private static func trimIfNeeded(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.intValue > maxBytes else {
            return
        }
        // 超 200KB 就只留后一半。
        guard let data = try? Data(contentsOf: url) else {
            return
        }
        let kept = data.suffix(maxBytes / 2)
        try? kept.write(to: url)
    }

    static func read() -> String {
        guard let url = logURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }

    /// 清空所有日志：删除日志文件，下次写入时会重新创建。
    static func clear() {
        guard let url = logURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}
