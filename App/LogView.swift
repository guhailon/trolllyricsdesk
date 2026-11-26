import SwiftUI
import UIKit

// MARK: - iOS 15 兼容层：替代 iOS 16 的 ShareLink
// 系统 ShareLink 是 iOS 16+ API，iOS 15 上会闪退。
// 用 UIKit 的 UIActivityViewController（iOS 5+）实现相同分享能力，
// 并保留 LogView 原有的 ShareLink 调用形式。

struct ShareLink<Label: View>: View {
    let item: String
    let label: Label
    @State private var showShare = false

    init(
        item: String,
        @ViewBuilder label: () -> Label
    ) {
        self.item = item
        self.label = label()
    }

    var body: some View {
        Button {
            showShare = true
        } label: {
            label
        }
        .sheet(isPresented: $showShare) {
            ActivityShareSheet(items: [item])
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}

// 日志查看：读 Documents/TrollLyricsDesk.log（LyricLogger 写的），
// 每行拆成时间 + 内容两行显示，可以分享出去；没有日志就显示空状态。
struct LogView: View {

    @State private var entries: [LogEntry] = []
    @State private var copiedFeedback = false
    @State private var showClearConfirm = false

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无日志")
                        .font(.headline)
                    Text("开始检测音乐后，这里会记录跟随和歌词匹配的情况。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.time)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(entry.message)
                                        .font(.body)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .onAppear {
                        if let last = entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("日志")
        .toolbar {
            Button {
                copyLog()
            } label: {
                Label(copiedFeedback ? "已复制" : "复制",
                      systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
            }
            .disabled(entries.isEmpty)

            Button {
                showClearConfirm = true
            } label: {
                Label("清除", systemImage: "trash")
            }
            .disabled(entries.isEmpty)

            ShareLink(item: shareText) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            .disabled(entries.isEmpty)
        }
        .alert("确定要清除全部日志吗？", isPresented: $showClearConfirm) {
            Button("清除", role: .destructive) {
                clearLog()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("清除后日志无法恢复。")
        }
        .onAppear {
            entries = LogEntry.parse(LyricLogger.read())
        }
    }

    // 复制：整份日志原文写进剪贴板，按钮短暂变“已复制”后恢复。
    private func copyLog() {
        UIPasteboard.general.string = LyricLogger.read()
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedFeedback = false
        }
    }

    // 清除：删日志文件，页面刷新成空状态。
    private func clearLog() {
        LyricLogger.clear()
        entries = []
    }

    private var shareText: String {
        entries.isEmpty ? "暂无日志" : LyricLogger.read()
    }
}

// 一条日志：时间 + 内容。日志行格式：[2026-11-25T06:10:17Z] 内容
struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let message: String

    static func parse(_ text: String) -> [LogEntry] {
        text.split(separator: "\n").map { line in
            let line = String(line)
            guard line.hasPrefix("["),
                  let close = line.firstIndex(of: "]") else {
                return LogEntry(time: "", message: line)
            }
            let rawTime = String(line[line.index(after: line.startIndex)..<close])
            let message = String(line[line.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
            return LogEntry(time: shortTime(rawTime), message: message)
        }
    }

    // 2026-11-25T06:10:17Z -> 14:10:17（本地时间）
    private static func shortTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "HH:mm:ss"
        return out.string(from: date)
    }
}
