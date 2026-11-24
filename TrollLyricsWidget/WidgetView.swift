import SwiftUI
import WidgetKit

struct TrollLyricsWidgetView: View {

    let entry: TrollLyricsEntry

    var body: some View {

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
}
