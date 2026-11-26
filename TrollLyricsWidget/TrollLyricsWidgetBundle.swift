import WidgetKit
import SwiftUI

@main
struct TrollLyricsWidgetBundle: WidgetBundle {

    var body: some Widget {
        TrollLyricsWidget()

        // 锁屏歌词必须注册到 WidgetBundle，系统才找得到它的渲染配置；
        // 没注册，控制器开了 Activity 锁屏也显示不出来。
        if #available(iOS 16.1, *) {
            LyricsLiveActivity()
        }
    }
}
