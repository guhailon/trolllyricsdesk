import Foundation

/// 统一渲染协议（1.0.5＋皇上树的 Renderer 层）。
///
/// 三个显示引擎都实现这个协议；切换逻辑在 RuntimeEnvironment（模式 → 引擎）
/// 与这里的 Hub（引擎 → 具体渲染器）两层，不在各处散落 if。
/// 注意：协议只管「显示什么」，不管引擎能不能真显示——
/// 真显示的证据各引擎自己记（原生 HUD 看托管复核，PiP 看 delegate 回调）。
protocol LyricsRenderer: AnyObject {
    /// 引擎名（诊断页／日志用）。
    var engineName: String { get }
    /// 是不是实验引擎（实验的 UI 与文档必须写明「实验」，不得报成已实现）。
    var isExperimental: Bool { get }
    /// 显示固定测试文字（不依赖音乐、不读歌词）。
    func showTestText()
    /// 显示实时歌词（走新底子同步引擎的快照）。
    func showLiveLyrics()
    /// 停掉本引擎的显示。
    func stop()
}

/// 渲染器 Hub：按当前模式选引擎，并持有三台渲染器实例。
final class LyricsRendererHub {

    static let shared = LyricsRendererHub()

    let native = NativeHUDRenderer()
    let pip = PiPLyricsRenderer.shared
    let inApp = InAppLyricsRenderer()

    private init() {}

    /// 当前首选引擎（按 RuntimeEnvironment 的模式 → 引擎映射算）。
    var currentEngine: TLDSDisplayEngine { RuntimeEnvironment.preferredEngine }

    /// 当前首选引擎对应的渲染器。
    var currentRenderer: any LyricsRenderer {
        switch currentEngine {
        case .nativeHUD: return native
        case .pip: return pip
        case .inApp: return inApp
        }
    }

    /// 模式变了（或启动后）调一次：记一行「选了哪个引擎、凭什么」，不自动开 PiP
    /// （PiP 启动要用户在前台点按钮，后台回调里调不可靠，见 PiPLyricsRenderer）。
    func refreshEngine() {
        RuntimeEnvironment.logEngineSelection()
        LyricLogger.log("诊断1.0.6 显示引擎：当前渲染器=\(currentRenderer.engineName)（实验=\(currentRenderer.isExperimental ? "是" : "否")）")
    }
}
