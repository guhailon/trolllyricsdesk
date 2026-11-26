import SwiftUI
import UIKit

// MARK: - iOS 15 兼容层：替代 iOS 16 的 ShareLink
// 系统 ShareLink 是 iOS 16+ API，iOS 15 上会闪退。
// 用 UIKit 的 UIActivityViewController（iOS 5+）实现相同分享能力。

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

// 日志查看：全屏显示，右上角功能菜单（分享 / 清理日志）。
// 读 Documents/TrollLyricsDesk.log（LyricLogger 写的），
// 每行拆成时间 + 内容两行显示；没有日志就显示空状态。
struct LogView: View, Equatable {
    /// 日志页没有外部输入，视图实例永远等价。父视图（关于页）因播放状态刷新
    /// 而重建时，SwiftUI 会跳过本页 body 求值，右上角菜单弹出层不再一闪一闪。
    static func == (lhs: LogView, rhs: LogView) -> Bool { true }

    @State private var entries: [LogEntry] = []
    @State private var copiedFeedback = false
    @State private var showShare = false
    @State private var showClearConfirm = false
    /// 自绘菜单开关：不用 SwiftUI Menu（UIContextMenuInteraction 的模糊层
    /// 在底层刷新时会反复重新采样，表现为一闪一闪）。
    @State private var showActionMenu = false

    /// 关闭当前页（本页由「关于」页 push 进来）。
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            // 深色背景铺满整屏，与原日志页视觉一致。
            Color(red: 0.11, green: 0.11, blue: 0.12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: 自定义顶部栏（替代系统导航栏）
                HStack(spacing: 12) {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("关于")
                        }
                        .foregroundColor(.blue)
                    }

                    Spacer()

                    Text("日志")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    // MARK: 右上角功能菜单（自绘弹窗，不使用系统 Menu）
                    Button {
                        showActionMenu.toggle()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.35))

                // MARK: 日志内容区（占满剩余屏幕）
                Group {
                    if entries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.6))
                            Text("暂无日志")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("开始检测音乐后，这里会记录跟随和歌词匹配的情况。")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
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
                                                .foregroundColor(.white.opacity(0.55))
                                            Text(entry.message)
                                                .font(.body)
                                                .foregroundColor(.white)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        Divider()
                                            .background(Color.white.opacity(0.12))
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
            }

            // MARK: 自绘菜单弹窗（替代系统 Menu）
            // 系统 Menu 背后的 UIContextMenuInteraction 会用模糊层截取底层视图，
            // 底层日志列表一刷新就重新采样，肉眼看就是「一闪一闪」。
            // 这里用普通视图绘制，不依赖系统弹窗机制，不会重新采样。
            if showActionMenu {
                ZStack(alignment: .topTrailing) {
                    // 半透明遮罩：点空白处关闭
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { showActionMenu = false }

                    VStack(alignment: .center, spacing: 0) {
                        Button {
                            showActionMenu = false
                            showShare = true
                        } label: {
                            Label("分享日志", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .disabled(entries.isEmpty)
                        .foregroundColor(entries.isEmpty ? .gray : .white)

                        Divider()
                            .background(Color.white.opacity(0.16))

                        Button {
                            showActionMenu = false
                            copyLog()
                        } label: {
                            Label(copiedFeedback ? "已复制" : "复制日志", systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .disabled(entries.isEmpty)
                        .foregroundColor(entries.isEmpty ? .gray : .white)

                        Divider()
                            .background(Color.white.opacity(0.16))

                        Button {
                            showActionMenu = false
                            showClearConfirm = true
                        } label: {
                            Label("清理日志", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .disabled(entries.isEmpty)
                        .foregroundColor(entries.isEmpty ? .gray : .red)
                    }
                    .frame(width: 200)
                    .background(Color(red: 0.20, green: 0.20, blue: 0.21))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                    .padding(.trailing, 12)
                    .padding(.top, 52)
                }
                .zIndex(10)
            }
        }
        // 隐藏系统导航栏，由上面的自定义栏接管，实现整屏显示。
        .navigationBarHidden(true)
        .sheet(isPresented: $showShare) {
            ActivityShareSheet(items: [shareText])
        }
        .alert("清理日志", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                clearLogs()
            }
        } message: {
            Text("确定要清空全部日志记录吗？此操作不可恢复。")
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        entries = LogEntry.parse(LyricLogger.read())
    }

    // 复制：整份日志原文写进剪贴板，按钮短暂变“已复制”后恢复。
    private func copyLog() {
        UIPasteboard.general.string = LyricLogger.read()
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedFeedback = false
        }
    }

    private func clearLogs() {
        LyricLogger.clear()
        reload()
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
