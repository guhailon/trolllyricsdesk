import Foundation

/// 应用内歌词渲染器（1.0.5 备选引擎：普通签名兼容模式的唯一显示）。
///
/// 只在 App 内显示（主界面应用内歌词区），不支持跨 App、桌面与锁屏——
/// 这是退路，不是悬浮窗，不要报成悬浮窗好了。
/// 显示内容与悬浮窗同源（LyricStore 快照）：测试开关开时显示固定测试文字，
/// 关时显示当前歌词行；没歌时显示占位。
final class InAppLyricsRenderer: LyricsRenderer {

    var engineName: String { "应用内歌词" }
    var isExperimental: Bool { false }

    func showTestText() {
        LyricStore.isTestTextEnabled = true
        LyricLogger.log("诊断1.0.5 强制测试：应用内歌词区显示测试文字（非悬浮窗）")
    }

    func showLiveLyrics() {
        LyricStore.isTestTextEnabled = false
        LyricLogger.log("诊断1.0.5 强制测试：应用内歌词区恢复实时歌词")
    }

    func stop() {
        // 应用内歌词区是主界面的一部分，停不掉也不用停；只关测试开关。
        LyricStore.isTestTextEnabled = false
    }

    /// 主界面应用内歌词区当前应显示的一行（Dashboard 宿主分支直接用）。
    static func currentDisplayText(at date: Date) -> String {
        if LyricStore.isTestTextEnabled {
            return LyricStore.testText() + "（应用内显示，非悬浮窗）"
        }
        guard let snapshot = LyricStore.load() else {
            return "请在设置中搜索或导入歌词"
        }
        return LyricStore.currentLyric(snapshot, at: date)?.text
            ?? "等待歌词 / 请到设置导入"
    }
}
