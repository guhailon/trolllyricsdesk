import SwiftUI
import WidgetKit

struct TrollLyricsWidgetView: View {

    @Environment(\.widgetFamily)
    private var family

    let entry: TrollLyricsEntry

    var body: some View {
        Group {
            // 1.0.3：未激活时显示占位，不显示歌词；激活后恢复正常内容。
            if !ActivationStore.isActivated {
                notActivatedView
            } else if #available(iOS 16.0, *),
                      family == .accessoryRectangular {
                lockScreenView
            } else {
                mainScreenView
            }
        }
    }

    /// 未激活占位（1.0.3）：主屏幕／锁屏两种 family 都走这里。
    private var notActivatedView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.5))

            Text("请先在 App 内激活")
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(12)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
    }

    /// 主屏幕小组件（原有布局，一字未动，只是从 body 里抽出来）。
    private var mainScreenView: some View {

        ZStack {

            RoundedRectangle(cornerRadius: 18)
                .fill(
                    Color.black.opacity(
                        entry.snapshot?.opacity ?? 0.5
                    )
                )

            if let snapshot = entry.snapshot {

                VStack(
                    alignment: .center,
                    spacing: 8
                ) {

                    Text(snapshot.title)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(
                        LyricStore.currentLyric(
                            snapshot,
                            at: entry.date
                        )?.text ?? "等待歌词..."
                    )
                    .font(
                        .system(
                            size: snapshot.fontSize,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                    Spacer(minLength: 0)

                    Text(snapshot.artist)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(12)

            } else {

                VStack(spacing: 8) {

                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundColor(.white)

                    Text("Troll Lyrics")
                        .foregroundColor(.white)

                    Text("打开 App 加载歌词")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
    }

    /// 锁屏小组件（路子 B：accessoryRectangular，iOS 16.0+）。
    /// 歌名小字＋当前句＋下一句；系统着色，不自定义颜色。
    @available(iOS 16.0, *)
    private var lockScreenView: some View {
        Group {
            if let snapshot = entry.snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    Text("桌面歌词 · \(snapshot.title)")
                        .font(.caption2)
                        .lineLimit(1)

                    Text(
                        LyricStore.currentLyric(
                            snapshot,
                            at: entry.date
                        )?.text ?? "等待歌词..."
                    )
                    .font(.headline)
                    .lineLimit(1)

                    Text(nextLyricText(snapshot: snapshot, at: entry.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Troll Lyrics")
            }
        }
    }

    /// 当前行的下一行（锁屏小组件用）；没下一行／还没唱到第一句时返回歌手名。
    private func nextLyricText(snapshot: LyricSnapshot, at date: Date) -> String {
        let elapsed = LyricStore.currentElapsed(snapshot, at: date)
        guard let index = snapshot.lyrics.lastIndex(where: { $0.time <= elapsed }) else {
            return snapshot.artist
        }
        if index + 1 < snapshot.lyrics.count {
            return snapshot.lyrics[index + 1].text
        }
        return snapshot.artist
    }
}
