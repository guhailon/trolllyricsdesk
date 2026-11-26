import Foundation

/// 原生 HUD 渲染器（1.0.5 保留的巨魔引擎，包一层协议，不改行为）。
///
/// 悬浮窗本体仍由 Overlay（TLDSAppDelegate／TLDSSceneDelegate／
/// FloatingLyricViewController）拥有与驱动；这里只是协议层面的控制面：
/// 开关强制测试文字、切回实时歌词。巨魔模式下行为与 1.0.0 底子一字不动。
final class NativeHUDRenderer: LyricsRenderer {

    var engineName: String { "原生 HUD 悬浮歌词" }
    var isExperimental: Bool { false }

    func showTestText() {
        LyricStore.isTestTextEnabled = true
        LyricLogger.log("诊断1.0.5 强制测试：原生 HUD 显示测试文字")
    }

    func showLiveLyrics() {
        LyricStore.isTestTextEnabled = false
        LyricLogger.log("诊断1.0.5 强制测试：原生 HUD 恢复实时歌词")
    }

    func stop() {
        LyricStore.isTestTextEnabled = false
    }
}
