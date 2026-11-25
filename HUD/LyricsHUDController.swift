import UIKit

// HUD 进程的歌词控制器：根视图是全屏透明容器，歌词卡片是它上面的子视图。
// 卡片 frame 由 HUD delegate 定，默认用 FloatingLyricsController 同款
// frame（x 30、y 180、w 300、h 126）；关闭按钮调 TLHelper.stopHUD。
// 捏合缩放：手势加在卡片上（FloatingLyricsPanel 同款 0.65–1.8 夹值），
// 皇上的 LyricsHUDView.swift 一字不动。
// 透明度调整（1.0.6 补的）：卡片下方跟一个小滑杆，0.4–1.0，默认 0.92；
// 滑杆是容器的子视图（不是卡片的），拖卡片时用 KVO 跟着走，
// 捏合时跟着缩放后的卡片底边走；值存在 App Group，下次开 HUD 还在。
// 触摸穿透不用改：TLHUDWindow 的 hitTest 只拦容器本身，滑杆是容器
// 的子视图，点到滑杆正常归我们，点到别处透传给下面的 App。
@objcMembers
final class LyricsHUDController: UIViewController {

    var cardFrame = CGRect(x: 30, y: 180, width: 300, height: 126)

    private var hudView: LyricsHUDView?
    private var initialTransform = CGAffineTransform.identity

    /// HUD 卡片透明度，存在 App Group（和歌词快照同一个共享区），
    /// 默认 0.92（FloatingLyricsStyle 卡片透明度同款）。
    private let hudOpacityKey = "hudCardOpacity"
    private let hudOpacityDefault: Float = 0.92
    private let hudOpacityMin: Float = 0.4
    private let hudOpacityMax: Float = 1.0

    private var opacityPill: UIView?
    private var opacitySlider: UISlider?
    private var centerObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let card = LyricsHUDView(frame: cardFrame)
        card.alpha = CGFloat(storedOpacity())
        card.onClose = {
            TLHelper.stopHUD()
        }
        let pinch = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinch(_:))
        )
        card.addGestureRecognizer(pinch)
        view.addSubview(card)
        hudView = card

        setupOpacityControl()

        // 卡片被拖动时中心变了，滑杆跟过去。
        centerObservation = card.observe(
            \.center,
            options: [.new]
        ) { [weak self] _, _ in
            self?.layoutOpacityControl()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutOpacityControl()
    }

    private func storedOpacity() -> Float {
        let defaults = UserDefaults(
            suiteName: "group.com.hailong.TrollLyricsDesk"
        )
        let value = defaults?.float(forKey: hudOpacityKey) ?? 0
        guard value > 0 else {
            return hudOpacityDefault
        }
        return min(max(value, hudOpacityMin), hudOpacityMax)
    }

    private func setupOpacityControl() {
        let pill = UIView()
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        pill.layer.cornerRadius = 15
        pill.frame = CGRect(x: 0, y: 0, width: 200, height: 30)

        let slider = UISlider(frame: CGRect(x: 10, y: 0, width: 180, height: 30))
        slider.minimumValue = hudOpacityMin
        slider.maximumValue = hudOpacityMax
        slider.value = storedOpacity()
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.4)
        slider.thumbTintColor = .white
        slider.addTarget(
            self,
            action: #selector(opacityChanged(_:)),
            for: .valueChanged
        )

        pill.addSubview(slider)
        view.addSubview(pill)
        opacityPill = pill
        opacitySlider = slider
    }

    /// 滑杆跟卡片：平时贴在卡片底边下面 9pt；卡片被拖到屏幕底部、
    /// 下面放不下时改贴到卡片顶边上面。横向跟卡片中心，夹在屏幕内。
    private func layoutOpacityControl() {
        guard
            let card = hudView,
            let pill = opacityPill
        else {
            return
        }

        let scale = max(card.transform.a, 0.01)
        let halfHeight = card.bounds.height / 2 * scale
        let gap: CGFloat = 9
        let pillHalfHeight: CGFloat = 15

        var pillCenterY = card.center.y + halfHeight + gap + pillHalfHeight
        if pillCenterY + pillHalfHeight > view.bounds.height {
            pillCenterY = card.center.y - halfHeight - gap - pillHalfHeight
        }

        let pillHalfWidth: CGFloat = 100
        let pillCenterX = min(
            max(card.center.x, pillHalfWidth),
            max(view.bounds.width - pillHalfWidth, pillHalfWidth)
        )

        pill.center = CGPoint(x: pillCenterX, y: pillCenterY)
    }

    @objc private func opacityChanged(_ sender: UISlider) {
        hudView?.alpha = CGFloat(sender.value)
        UserDefaults(
            suiteName: "group.com.hailong.TrollLyricsDesk"
        )?.set(sender.value, forKey: hudOpacityKey)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let card = hudView else { return }

        if gesture.state == .began {
            initialTransform = card.transform
        }

        if gesture.state == .changed {
            let scale = min(
                max(gesture.scale, 0.65),
                1.8
            )

            card.transform = initialTransform.scaledBy(
                x: scale,
                y: scale
            )
            // 卡片变大变小，滑杆跟底边走。
            layoutOpacityControl()
        }
    }

    @objc(updateWithTitle:previous:current:next:)
    func update(title: String, previous: String, current: String, next: String) {
        hudView?.updateLyrics(
            title: title,
            previous: previous,
            current: current,
            next: next
        )
    }
}
