import SwiftUI

// 日志查看：读 Documents/TrollLyricsDesk.log（LyricLogger 写的），
// 可以分享出去；没有日志就显示暂无日志。
struct LogView: View {

    @State private var logText: String = ""

    var body: some View {
        VStack {
            if logText.isEmpty {
                Text("暂无日志")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(logText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .navigationTitle("日志")
        .toolbar {
            ShareLink(item: logText.isEmpty ? "暂无日志" : logText) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            .disabled(logText.isEmpty)
        }
        .onAppear {
            logText = LyricLogger.read()
        }
    }
}
