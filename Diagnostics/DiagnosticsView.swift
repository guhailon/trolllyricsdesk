import SwiftUI
import MediaPlayer

/// 诊断页（1.0.5＋皇上树的 Diagnostics 层）：把各路诊断结论收在一处，
/// 真机上抄日志时先看这里，再去日志页抄整行。
/// 只读＋显示，不改任何行为；PiP 按钮标明「实验」。
struct DiagnosticsView: View {

    @StateObject private var pip = PiPLyricsRenderer.shared
    @State private var musicPermission = "未检查"
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
                // 1.0.6 第 2 项：三项判定分行显示（安装环境／显示能力各有各的结论与理由，
                // 不再只看一个模式名；托管复核只定显示能力，不改安装环境）。
                Text("安装环境：\(LyricStore.installEnvironmentDescription)（\(LyricStore.installEnvironmentReason)）")
                    .font(.caption)
                Text("显示能力：\(LyricStore.displayCapabilityDescription)（\(LyricStore.displayCapabilityReason)）")
                    .font(.caption)
                ForEach(OverlayDiagnostics.summaryLines, id: \.self) { line in
                    Text(line).font(.caption)
                }
            }

            Section(header: Text("MediaRemote 音乐识别")) {
                Text("Apple Music 备选授权：\(musicPermission)")
                Button("授权 Apple Music 备选数据源") {
                    requestMusicPermission { allowed in
                        musicPermission = allowed ? "已授权" : "未授权"
                        LyricLogger.log("Build 34 Apple Music fallback authorization: \(allowed)")
                    }
                }
                Text("仅支持系统音乐库，不读取 QQ／网易云的跨应用数据。")
                    .font(.caption)
                Text(MediaRemoteDiagnostics.summaryLine)
                    .font(.caption)
                // 1.0.6 第 4 项：调用次数／回调次数／isPlaying 查询次数分开记，
                // 回调只触发一次、info=nil 时看这里判 P0 还是没放歌。
                Text("调用 \(MediaRemoteDiagnostics.requestCount) 次／回调 \(MediaRemoteDiagnostics.infoCallbackCount) 次／isPlaying 查询 \(MediaRemoteDiagnostics.isPlayingQueryCount) 次")
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
                // 1.0.6 第 9 项：固定文字段／实时歌词段各记各的状态，分行显示。
                Text("固定文字段：\(PiPLyricsRenderer.testStageText)")
                    .font(.caption)
                Text("实时歌词段：\(PiPLyricsRenderer.liveStageText)")
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
        .navigationTitle("诊断（2.0.5）")
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        musicPermission = MPMediaLibrary.authorizationStatus() == .authorized ? "已授权" : "未授权"
        LyricLogger.log("Build 34 diagnostic refresh: \(LyricStore.versionTag), uptime=\(Int(ProcessInfo.processInfo.systemUptime))s")
        RuntimeCapabilities.logSnapshot()
        EntitlementDiagnostics.logReport()
        snapshotLines = [
            "iOS \(RuntimeCapabilities.iOSVersion.majorVersion).\(RuntimeCapabilities.iOSVersion.minorVersion)（iOS 27+ = \(RuntimeCapabilities.isIOS27OrLater ? "是" : "否")）",
            "LiveContainer 信号：\(RuntimeCapabilities.liveContainerSignal ? "有" : "无")",
            "PiP 系统支持：\(RuntimeCapabilities.pipSupported ? "是" : "否")",
            "HUD 守护进程显示能力：\(RuntimeCapabilities.nativeHUDProbePassed ? "通过" : "未通过")",
            MediaRemoteDiagnostics.summaryLine,
        ]
        entitlementRows = EntitlementDiagnostics.checks()
    }
}
