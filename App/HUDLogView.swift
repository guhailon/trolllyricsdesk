import SwiftUI

// HUD 守护进程日志查看（2.0.0）。
// 沿用 HUD-Test MainViewController.refreshLog 的写法：读
// /var/mobile/Library/Caches/com.ycwl.Lyrics.hud.log（TLDHUDLogFilePath），
// 只显示末 120 行，带「刷新」按钮。主 App 与 root daemon 共用这一个
// 日志文件（0666，见 HUD/TLDHUDLog.mm），所以这里能看到 daemon 的行。
struct HUDLogView: View {

    @State private var logText = "（尚无日志）"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("守护进程日志")
                    .font(.headline)
                Spacer()
                Button("刷新") {
                    refreshLog()
                }
            }
            .padding()

            ScrollView {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("HUD 日志")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshLog()
        }
    }

    private func refreshLog() {
        let path = TLDHUDLogFilePath()
        guard let log = try? String(contentsOfFile: path, encoding: .utf8),
              !log.isEmpty
        else {
            logText = "（尚无日志）"
            return
        }
        // 只显示末 120 行（HUD-Test 同款）。
        let lines = log.components(separatedBy: "\n")
        let tail = lines.count > 120
            ? Array(lines[(lines.count - 120)...])
            : lines
        logText = tail.joined(separator: "\n")
    }
}
