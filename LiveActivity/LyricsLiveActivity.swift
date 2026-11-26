import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - 锁屏歌词（路子 A：灵动岛 Live Activities）
// iOS 16.1+ 才有 ActivityKit；整个文件包在 @available 里，MinOS 保持 15.0。
// 零新增 entitlements；不走推送，只用本地更新（pushType: nil）。
// 锁屏横幅与灵动岛展开态共用同一个「三行歌词」子视图，不要写两份。

@available(iOS 16.1, *)
struct LyricsLiveAttributes: ActivityAttributes {

    // 全部显示内容都在 state 里（换歌不重开 Activity，只更新 state）；
    // attributes 本身不带固定内容。
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var previous: String
        var current: String
        var next: String
        var isPlaying: Bool
        /// 歌词颜色 0xRRGGBB，复用取色器键 floatingLyric.textColorHex，默认白。
        /// 锁屏横幅是系统渲染的，颜色可能被压暗——真机不对就退回白色。
        var lyricColorHex: Int
    }
}

/// 上一句／当前句／下一句三行（标题行＋上／当前／下）。
@available(iOS 16.1, *)
struct LyricsLiveLinesView: View {

    let state: LyricsLiveAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 歌手为空不留多余分隔符；暂停时标题行标「已暂停」。
            Text((state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)")
                + (state.isPlaying ? "" : " · 已暂停"))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if !state.previous.isEmpty {
                Text(state.previous)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Text(state.current)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(Color(hex: state.lyricColorHex))
                .lineLimit(2)

            if !state.next.isEmpty {
                Text(state.next)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// 锁屏横幅：共用三行歌词子视图。
@available(iOS 16.1, *)
struct LyricsLiveLockScreenView: View {

    let state: LyricsLiveAttributes.ContentState

    var body: some View {
        LyricsLiveLinesView(state: state)
            .padding()
    }
}

@available(iOS 16.1, *)
struct LyricsLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsLiveAttributes.self) { context in
            // 锁屏横幅（iPhone 11 和 15 Pro 都有）。
            LyricsLiveLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态（长按岛）：歌名＋歌手一行，上／当前／下三行。
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.center) {
                    if !context.state.previous.isEmpty {
                        Text(context.state.previous)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isPlaying
                            ? context.state.current
                            : "\(context.state.current) · 已暂停")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: context.state.lyricColorHex))
                            .lineLimit(2)
                        if !context.state.next.isEmpty {
                            Text(context.state.next)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                // 收起态：岛里只放当前行，超长截断（缩小＋尾部省略）。
                Text(context.state.current)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
            } minimal: {
                // 最小态：只留音符图标（多个 Activity 并存时系统自动缩成这个）。
                Image(systemName: "music.note")
            }
        }
    }
}

// MARK: - 0xRRGGBB → Color（与 PlaybackDashboardView 的取色器同款换算）
@available(iOS 16.1, *)
private extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
