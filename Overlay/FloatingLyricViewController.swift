import UIKit
import WidgetKit

/// 悬浮歌词窗的内容控制器。
///
/// 这个控制器被装进一个绑定到 FrontBoard 全局前台场景的 UIWindow 里，
/// 因此 App 退回桌面 / 切到其他 App 后仍然显示——这就是"歌词悬浮在桌面"。
///
/// 数据直接读 App Group 的 LyricSnapshot（与主 App、Widget 同源），
/// 用 Timer 按播放进度算出当前行，做到逐句跟随。
/// 界面只显示一行歌词（歌名/歌手/状态已移除，避免与歌词重复）。
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
        guard let raw = prefs?.object(forKey: cardOpacityKey) else { return 0.55 }
        return CGFloat((raw as? Double) ?? 0.55)
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

    // UI —— 只有歌词行 + 操作提示
    private let cardView = UIView()
    private let currentLabel = UILabel()    // 当前歌词行（唯一一行，自适应完整显示）
    private let hintLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildUI()
        restorePosition()
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

    // MARK: - UI
    private func buildUI() {
        cardView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        cardView.layer.cornerRadius = 16
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        // 只显示一行歌词：不限制行数，长歌词自动换行 + 字号自适应，保证完整显示
        currentLabel.font = .systemFont(ofSize: 22, weight: .bold)
        currentLabel.textColor = .white
        currentLabel.numberOfLines = 0
        currentLabel.lineBreakMode = .byWordWrapping
        currentLabel.textAlignment = .center
        currentLabel.shadowColor = .black.withAlphaComponent(0.8)
        currentLabel.shadowOffset = CGSize(width: 0, height: 1)
        currentLabel.text = "♪"

        hintLabel.font = .systemFont(ofSize: 9, weight: .regular)
        hintLabel.textColor = .white.withAlphaComponent(0.4)
        hintLabel.textAlignment = .center
        hintLabel.text = "长按拖动 · 双击隐藏"

        // 歌词行：垂直 stack，只放歌词，顶部对齐
        let stack = UIStackView(arrangedSubviews: [currentLabel])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        // 操作提示：从 stack 中移出，固定到卡片最底部
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.widthAnchor.constraint(equalTo: view.widthAnchor),
            cardView.heightAnchor.constraint(equalTo: view.heightAnchor),

            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            // 歌词底部不越过提示文字顶部，留 6pt 间距
            stack.bottomAnchor.constraint(lessThanOrEqualTo: hintLabel.topAnchor, constant: -6),

            hintLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            hintLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            hintLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8),
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

        guard let data = prefs?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(LyricSnapshot.self, from: data)
        else {
            apply(text: "♪", fontSize: 22, opacity: 0.65)
            return
        }

        let elapsed = LyricStore.currentElapsed(snapshot, at: Date())

        // 当前行：最后一个 time <= elapsed（只显示这一行）
        let current = snapshot.lyrics.last { $0.time <= elapsed }

        // 没匹配到同步歌词时，至少把歌名显示出来，避免空白
        apply(
            text: current?.text ?? "♪ \(snapshot.title)",
            fontSize: CGFloat(snapshot.fontSize),
            opacity: CGFloat(snapshot.opacity)
        )
    }

    /// 仅更新唯一的一行歌词；按文本长度自适应字号，保证在窗口宽度内完整显示。
    private func apply(text: String, fontSize: CGFloat, opacity: CGFloat) {
        if text != lastLineText {
            lastLineText = text
            currentLabel.text = text
        }
        let availableWidth = max(200, view.bounds.width - 28)
        let fitted = fittedFontSize(for: text, width: availableWidth, base: fontSize)
        currentLabel.font = .systemFont(ofSize: fitted, weight: .bold)

        // 背景透明度由「悬浮窗透明度」滑块独立控制（0 = 全透明，只剩歌词）
        let bg = max(0, min(1, cardBackgroundOpacity))
        cardView.backgroundColor = UIColor.black.withAlphaComponent(bg)
        hintLabel.alpha = bg
        // 歌词本身仍用原有「歌词透明度」设置，颜色由主界面取色器控制
        currentLabel.alpha = max(0.2, min(1.0, opacity))
        currentLabel.textColor = lyricTextColor
    }

    /// 逐步缩小字号，直到歌词在给定宽度内不超过 3 行（完整显示且可读）。
    private func fittedFontSize(for text: String, width: CGFloat, base: CGFloat) -> CGFloat {
        var size = max(13, min(base, 34))
        let minSize: CGFloat = 13
        while size > minSize {
            let font = UIFont.systemFont(ofSize: size, weight: .bold)
            let needed = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height
            if needed <= font.lineHeight * 3.1 {
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
        let sx = prefs?.double(forKey: posXKey) ?? 0.5
        let sy = prefs?.double(forKey: posYKey) ?? 0.22
        var center = CGPoint(
            x: CGFloat(sx) * UIScreen.main.bounds.width,
            y: CGFloat(sy) * UIScreen.main.bounds.height
        )
        let halfW = window.bounds.width / 2
        let halfH = window.bounds.height / 2
        center.x = max(halfW, min(UIScreen.main.bounds.width - halfW, center.x))
        center.y = max(halfH + 20, min(UIScreen.main.bounds.height - halfH - 20, center.y))
        window.center = center
    }
}
