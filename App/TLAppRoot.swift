import SwiftUI
import UIKit

// Swift 侧的 App 入口工厂：main.mm 是唯一程序入口（C），普通模式的
// TLAppDelegate 通过它拿到 SwiftUI 的根视图控制器。
@objc final class TLAppRoot: NSObject {

    @objc static func makeRootViewController() -> UIViewController {
        UIHostingController(rootView: ContentView())
    }

    // 当前活跃 window scene 的 key window 的根视图（没有 key window 时
    // 退回该 scene 的第一个窗口），给 App 内悬浮歌词预览用。
    @objc static func keyWindowRootView() -> UIView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        return window?.rootViewController?.view
    }
}
