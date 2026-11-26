import WidgetKit
import SwiftUI

struct TrollLyricsEntry: TimelineEntry {

    let date: Date
    let snapshot: LyricSnapshot?
}

struct TrollLyricsProvider: TimelineProvider {

    func placeholder(
        in context: Context
    ) -> TrollLyricsEntry {

        TrollLyricsEntry(
            date: Date(),
            snapshot: nil
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (TrollLyricsEntry) -> Void
    ) {

        completion(
            TrollLyricsEntry(
                date: Date(),
                snapshot: LyricStore.load()
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<TrollLyricsEntry>) -> Void
    ) {

        let now = Date()

        guard let snapshot = LyricStore.load() else {

            let entry = TrollLyricsEntry(
                date: now,
                snapshot: nil
            )

            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(now.addingTimeInterval(60))
                )
            )

            return
        }

        // 当前时间先显示一次
        var entries: [TrollLyricsEntry] = [
            TrollLyricsEntry(
                date: now,
                snapshot: snapshot
            )
        ]

        // 预先安排后续歌词。
        // 关键：快照可能从歌曲中途开始（elapsedWhenPaused > 0），
        // 这里必须扣掉起始进度，否则整条时间轴会整体后移、歌词错位。
        let elapsedAtStart = LyricStore.currentElapsed(
            snapshot,
            at: snapshot.startedAt
        )

        // 叠加用户的歌词时间偏移：与悬浮窗 / 主界面 currentLyric 保持一致，
        // 否则 Widget 的切换时刻会和歌词内容对不上（内容提前了、entry 没提前）。
        let offset = LyricStore.timeOffset(snapshot)

        let futureEntries = snapshot.lyrics
            .map { line in
                (
                    time: line.time,
                    date: snapshot.startedAt.addingTimeInterval(
                        line.time - elapsedAtStart - offset
                    )
                )
            }
            .filter { $0.date > now }

        for item in futureEntries {

            entries.append(
                TrollLyricsEntry(
                    date: item.date,
                    snapshot: snapshot
                )
            )
        }

        entries.sort {
            $0.date < $1.date
        }

        let finalDate = entries.last?.date
            ?? now.addingTimeInterval(60)

        completion(
            Timeline(
                entries: entries,
                policy: .after(
                    finalDate.addingTimeInterval(30)
                )
            )
        )
    }
}

struct TrollLyricsWidget: Widget {

    let kind = "TrollLyricsWidget"

    var body: some WidgetConfiguration {

        StaticConfiguration(
            kind: kind,
            provider: TrollLyricsProvider()
        ) { entry in

            TrollLyricsWidgetView(entry: entry)
        }
        .configurationDisplayName("Troll Lyrics")
        .description("透明动漫风格实时歌词组件")
        // 1.0.5：锁屏小组件已取消（皇上 2026-11-26 21:46 令），
        // supportedFamilies 只留主屏幕两种，不再加 accessoryRectangular。
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
