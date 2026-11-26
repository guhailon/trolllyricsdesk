import WidgetKit
import SwiftUI

@main
struct TrollLyricsWidgetBundle: WidgetBundle {

    var body: some Widget {
        TrollLyricsWidget()

        // 1.0.5：锁屏歌词（Live Activity）已取消（皇上 2026-11-26 21:46 令，
        // 真机从未证实可用），Bundle 里不再注册 LyricsLiveActivity。
        // 想加回来可从 newbase e0c154a 恢复。
    }
}
