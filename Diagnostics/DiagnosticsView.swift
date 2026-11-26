import SwiftUI

/// 诊断页（1.0.5＋皇上树的 Diagnostics 层）：把各路诊断结论收在一处，
/// 真机上抄日志时先看这里，再去日志页抄整行。
/// 只读＋显示，不改任何行为；PiP 按钮标明「实验」。
struct DiagnosticsView: View {

    @StateObject private var pip = PiPLyricsRenderer.shared
    @State private var snapshotLines: [String] = []
    @State private var entitlementRows: [EntitlementDiagnostics.CapabilityCheck] = []

    var body: some View {
        List {
            Section(header: Text("运行模式（三档，按实际能力）")) {
                Text(OverlayDiagnostics.modeDescription)
                    .font(.headline)
                Text(OverlayDiagnostics.modeReason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("首选引擎：\(RuntimeEnvironment.preferredEngine.displayName)")
                ForEach(OverlayDiagnostics.summaryLines, id: \.self) { line in
                    Text(line).font(.caption)
                }
            }

            Section(header: Text("MediaRemote 音乐识别")) {
                Text(MediaRemoteDiagnostics.summaryLine)
                    .font(.caption)
            }

            Section(header: Text("能力快照")) {
                ForEach(snapshotLines, id: \.self) { line in
                    Text(line).font(.caption)
                }
                Button("刷新快照") {
                    refresh()
                }
            }

            Section(header: Text("PiP 画中画歌词（实验）")) {
                Text(pip.statusText)
                    .font(.caption)
                Text("先验固定测试文字，再接实时歌词；PiP 能显示也不代表能自动拿到别的播放器的歌。透明背景受限、拖动由系统控制、锁屏不保证。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("开始 PiP 测试（固定文字，实验）") {
                    pip.startTestText()
                }
                Button("接入实时歌词（实验）") {
                    pip.startLiveLyrics()
                }
                Button("停止 PiP") {
                    pip.stop()
                }
            }

            Section(header: Text("权限对照（声明 ≠ 可用）")) {
                ForEach(entitlementRows, id: \.name) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.name).font(.caption).bold()
                        Text("声明：\(row.declared ? "有" : "无")")
                            .font(.caption).foregroundColor(.secondary)
                        Text("实测：\(row.observed)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("日志")) {
                NavigationLink("打开日志页（复制整份日志）") {
                    LogView()
                }
            }
        }
        .navigationTitle("诊断（1.0.5）")
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        RuntimeCapabilities.logSnapshot()
        EntitlementDiagnostics.logReport()
        snapshotLines = [
            "iOS \(RuntimeCapabilities.iOSVersion.majorVersion).\(RuntimeCapabilities.iOSVersion.minorVersion)（iOS 27+ = \(RuntimeCapabilities.isIOS27OrLater ? "是" : "否")）",
            "LiveContainer 信号：\(RuntimeCapabilities.liveContainerSignal ? "有" : "无")",
            "PiP 系统支持：\(RuntimeCapabilities.pipSupported ? "是" : "否")",
            "原生悬浮复核通过：\(RuntimeCapabilities.nativeHUDProbePassed ? "是" : "否")",
            MediaRemoteDiagnostics.summaryLine,
        ]
        entitlementRows = EntitlementDiagnostics.checks()
    }
}
