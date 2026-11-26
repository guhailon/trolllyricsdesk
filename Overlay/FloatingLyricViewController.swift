import UIKit
import WidgetKit

/// 悬浮歌词窗的内容控制器。
///
/// 这个控制器被装进一个绑定到 FrontBoard 全局前台场景的 UIWindow 里，
/// 因此 App 退回桌面 / 切到其他 App 后仍然显示——这就是"歌词悬浮在桌面"。
///
/// 数据直接读 App Group 的 LyricSnapshot（与主 App、Widget 同源），
/// 用 Timer 按播放进度算出当前行，做到逐句跟随。
/// 界面只显示当前一句歌词（歌名/歌手/状态已移除，避免与歌词重复），
/// 窗口高度按歌词实际换行行数自适应：1 行只占 1 行高，2 行占 2 行高，以此类推。
@objc(FloatingLyricViewController)
@objcMembers
final class FloatingLyricViewController: UIViewController {

    // 与主 App / Widget 完全一致的共享存储
    private let prefs = UserDefaults(suiteName: LyricStore.groupID)
    private let snapshotKey = LyricStore.dataKey

    // 显示开关：双击隐藏后写入 false，主界面开关可重新打开
    private let enabledKey = "floatingLyric.enabled"

    // 位置持久化：用户拖动后的中心点（屏幕坐标，归一化 0~1）
    private let posXKey = "floatingLyric.posX"
    private let posYKey = "floatingLyric.posY"

    // 悬浮窗背景透明度：0 = 背景完全透明，只显示歌词
    private let cardOpacityKey = "floatingLyric.cardOpacity"
    private var cardBackgroundOpacity: CGFloat {
        guard let raw = prefs?.object(forKey: cardOpacityKey) else { return 0.23 }
        return CGFloat((raw as? Double) ?? 0.23)
    }

    // 卡片上下留白：与 buildUI() 中 stack 的 top / bottom 约束一致
    private let verticalInset: CGFloat = 12

    // 极端长歌词时的高度上限：最多半个屏幕、且不超过 360pt，避免遮住整个界面
    private var maxWindowHeight: CGFloat {
        min(UIScreen.main.bounds.height * 0.5, 360)
    }

    // 歌词文字颜色：主界面取色器写入 App Group 的 0xRRGGBB，默认白色
    private let textColorKey = "floatingLyric.textColorHex"
    private var lyricTextColor: UIColor {
        guard let raw = prefs?.object(forKey: textColorKey) else { return .white }
        let hex = (raw as? NSNumber)?.intValue ?? 0xFFFFFF
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private var refreshTimer: Timer?
    private var lastLineText: String?

    // UI —— 只有歌词行
    private let cardView = UIView()
    private let currentLabel = UILabel()    // 当前歌词行（唯一一行，自适应完整显示）

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildUI()
        // 位置恢复不能在 viewDidLoad 做：此时 view.window 还是 nil，
        // restorePosition() 会直接 return，导致窗口停在 SceneDelegate 初始的顶部位置。
        // 改到 viewDidMoveToWindow() 里，window 就绪后再恢复。
        applyVisibility()
        startRefresh()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRotate),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    deinit {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // window 就绪后再恢复位置：viewDidLoad 时 view.window 还是 nil，
    // 在那里调用会被 guard 拦掉，窗口就停在 SceneDelegate 设的顶部初始位置。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restorePosition()
    }

    // MARK: - UI
    private func buildUI() {
        cardView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        cardView.layer.cornerRadius = 16
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        // 当前歌词：不限制行数，长歌词自动换行；窗口高度按实际行数自适应
        currentLabel.font = .systemFont(ofSize: 22, weight: .bold)
        currentLabel.textColor = .white
        currentLabel.numberOfLines = 0
        currentLabel.lineBreakMode = .byWordWrapping
        currentLabel.textAlignment = .center
        currentLabel.shadowColor = .black.withAlphaComponent(0.8)
        currentLabel.shadowOffset = CGSize(width: 0, height: 1)
        currentLabel.text = "♪"

        // 歌词行：垂直 stack，只放歌词，顶部对齐
        let stack = UIStackView(arrangedSubviews: [currentLabel])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.widthAnchor.constraint(equalTo: view.widthAnchor),
            cardView.heightAnchor.constraint(equalTo: view.heightAnchor),

            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12),
        ])

        // 拖动（长按后移动）
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        cardView.addGestureRecognizer(pan)

        // 双击临时隐藏（写入开关 false，主界面可重新打开）
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        tap.numberOfTapsRequired = 2
        cardView.addGestureRecognizer(tap)
    }

    // MARK: - 显示 / 隐藏
    private var floatingEnabled: Bool {
        // Swift 值类型语义：UserDefaults.bool 未设置时返回 false，
        // 因此用 object(forKey:) 判断是否存在，不存在时默认开启。
        guard let raw = prefs?.object(forKey: enabledKey) else {
            return true
        }
        return raw as? Bool ?? true
    }

    private func applyVisibility() {
        view.isHidden = !floatingEnabled
    }

    @objc private func handleDoubleTap() {
        // 双击隐藏：关掉开关，主界面里能重新打开
        prefs?.set(false, forKey: enabledKey)
        view.isHidden = true
        // 通知主界面同步开关：@AppStorage 监听的是它自己那个 UserDefaults 实例，
        // 这里写入的是另一个实例，不显式通知的话开关不会跟着变。
        NotificationCenter.default.post(name: LyricStore.floatingEnabledChanged, object: nil)
    }

    // MARK: - 刷新歌词
    private func startRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    @objc private func refresh() {
        // 主界面改开关后，悬浮窗在 0.25s 内自动恢复显示
        applyVisibility()

        // 检测不到播放器时，不要停留在上一次的歌词快照：显示提示文字。
        // 该标志由 PlaybackCoordinator.poll() 与主界面 state 同步写入。
        if prefs?.bool(forKey: LyricStore.noMusicKey) == true {
            apply(text: "♪ 未检测到播放器播放音乐", fontSize: 23, opacity: 1.0)
            return
        }

        guard let data = prefs?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(LyricSnapshot.self, from: data)
        else {
            apply(text: "♪", fontSize: 23, opacity: 1.0)
            return
        }

        // 与主界面播放卡片用同一套稳定识别：某些播放器会在 title / artist 之间
        // 来回交换「歌手 — 歌名」标识与逐句歌词，只盯某个字段会翻转。
        // LyricStore.lyricLocation 认出固定的标识串，另一字段就是歌词。
        let normalize: (String) -> String = { text in
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "")
        }
        let lyricTexts = Set(snapshot.lyrics.map { normalize($0.text) })
        let title = snapshot.title
        let secondary = snapshot.artist
        let location = LyricStore.lyricLocation(
            title: title,
            artist: secondary,
            lyricTexts: lyricTexts
        )

        // 当前行：最后一个 time <= (进度 + 用户校正偏移)。
        // 用 LyricStore.currentLyric 统一取行，保证悬浮窗 / Widget / 主界面
        // 三处都吃到同一个「歌词时间偏移」设置，不会互相不一致。
        let current = LyricStore.currentLyric(snapshot, at: Date())

        // 歌词所在字段优先显示它；否则沿用原逻辑（同步歌词行，
        // 没匹配到才显示歌名），保证本来正常的播放器显示不变。
        let text: String
        switch location {
        case .artist:
            text = secondary
        case .title:
            text = title
        case .unknown:
            text = current?.text ?? "♪ \(title)"
        }

        apply(
            text: text,
            fontSize: CGFloat(snapshot.fontSize),
            opacity: CGFloat(snapshot.opacity)
        )
    }

    /// 仅更新当前歌词；按文本需要的行数自适应窗口高度，长到极端时才缩小字号。
    private func apply(text: String, fontSize: CGFloat, opacity: CGFloat) {
        if text != lastLineText {
            lastLineText = text
            currentLabel.text = text
        }
        let availableWidth = max(200, view.bounds.width - 2 * verticalInset - 4)
        let fitted = fittedFontSize(
            for: text,
            width: availableWidth,
            base: fontSize,
            maxTextHeight: maxWindowHeight - 2 * verticalInset
        )
        currentLabel.font = .systemFont(ofSize: fitted, weight: .bold)

        // 背景透明度由「悬浮窗透明度」滑块独立控制（0 = 全透明，只剩歌词）
        let bg = max(0, min(1, cardBackgroundOpacity))
        cardView.backgroundColor = UIColor.black.withAlphaComponent(bg)
        // 歌词本身仍用原有「歌词透明度」设置，颜色由主界面取色器控制
        currentLabel.alpha = max(0.2, min(1.0, opacity))
        currentLabel.textColor = lyricTextColor

        resizeWindowForText(text, font: currentLabel.font, width: availableWidth)
    }

    /// 窗口高度 = 歌词实际换行占用高度 + 上下留白。
    /// 一行歌词就只有一行高，两行就是两行高，以此类推；高度变化时窗口中心不动，
    /// 不会把用户拖好的位置顶走，并重新限制在屏幕内。
    private func resizeWindowForText(_ text: String, font: UIFont, width: CGFloat) {
        guard let window = view.window else { return }
        let needed = textHeight(for: text, font: font, width: width)
        let target = min(maxWindowHeight, max(48, ceil(needed) + 2 * verticalInset))
        let current = window.frame.size.height
        guard abs(current - target) > 0.5 else { return }

        let center = window.center
        var frame = window.frame
        frame.size.height = target
        window.frame = frame

        var fixedCenter = center
        let halfW = frame.size.width / 2
        let halfH = frame.size.height / 2
        let screen = UIScreen.main.bounds
        fixedCenter.x = max(halfW, min(screen.width - halfW, fixedCenter.x))
        fixedCenter.y = max(halfH + 20, min(screen.height - halfH - 20, fixedCenter.y))
        window.center = fixedCenter
    }

    /// 给定字体与宽度下，文字实际需要的高度（含系统行距）。
    private func textHeight(for text: String, font: UIFont, width: CGFloat) -> CGFloat {
        (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
    }

    /// 常规歌词保持用户设定的字号（最多 34pt）；只有高度超过安全上限才逐步缩小字号。
    private func fittedFontSize(
        for text: String,
        width: CGFloat,
        base: CGFloat,
        maxTextHeight: CGFloat
    ) -> CGFloat {
        var size = max(13, min(base, 34))
        let minSize: CGFloat = 13
        while size > minSize {
            let font = UIFont.systemFont(ofSize: size, weight: .bold)
            if textHeight(for: text, font: font, width: width) <= maxTextHeight {
                break
            }
            size -= 1
        }
        return size
    }

    // MARK: - 交互
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let window = view.window else { return }
        let translation = gesture.translation(in: window)
        var center = window.center
        center.x += translation.x
        center.y += translation.y

        // 限制在屏幕内（保留窗口自身尺寸）
        let halfW = window.bounds.width / 2
        let halfH = window.bounds.height / 2
        center.x = max(halfW, min(UIScreen.main.bounds.width - halfW, center.x))
        center.y = max(halfH + 20, min(UIScreen.main.bounds.height - halfH - 20, center.y))

        window.center = center
        gesture.setTranslation(.zero, in: window)

        if gesture.state == .ended || gesture.state == .cancelled {
            savePosition(center: center)
        }
    }

    @objc private func handleRotate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.restorePosition()
        }
    }

    private func savePosition(center: CGPoint) {
        let sx = center.x / UIScreen.main.bounds.width
        let sy = center.y / UIScreen.main.bounds.height
        prefs?.set(sx, forKey: posXKey)
        prefs?.set(sy, forKey: posYKey)
    }

    private func restorePosition() {
        guard let window = view.window else { return }
        // 注意：UserDefaults.double(forKey:) 在 key 不存在时返回 0 而不是 nil，
        // 用 ?? 给默认值会失效（sy 变成 0 → 窗口跑到顶部）。必须用 object(forKey:) 判断。
        let sx: CGFloat = {
            guard let raw = prefs?.object(forKey: posXKey) as? NSNumber else { return 0.5 }
            return CGFloat(raw.doubleValue)
        }()
        // 默认显示在屏幕下方（与截图位置一致）；用户手动拖动过则沿用保存值
        let sy: CGFloat = {
            guard let raw = prefs?.object(forKey: posYKey) as? NSNumber else { return 0.8 }
            return CGFloat(raw.doubleValue)
        }()
        var center = CGPoint(
            x: sx * UIScreen.main.bounds.width,
            y: sy * UIScreen.main.bounds.height
        )
        let halfW = window.bounds.width / 2
        let halfH = window.bounds.height / 2
        center.x = max(halfW, min(UIScreen.main.bounds.width - halfW, center.x))
        center.y = max(halfH + 20, min(UIScreen.main.bounds.height - halfH - 20, center.y))
        window.center = center
    }
}
