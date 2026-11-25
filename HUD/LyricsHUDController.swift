import UIKit

// HUD 进程的歌词控制器：根视图是全屏透明容器，歌词卡片是它上面的子视图。
// 卡片 frame 由 HUD delegate 定，默认用 FloatingLyricsController 同款
// frame（x 30、y 180、w 300、h 126）；关闭按钮调 TLHelper.stopHUD。
// 捏合缩放：手势加在卡片上（FloatingLyricsPanel 同款 0.65–1.8 夹值），
// 皇上的 LyricsHUDView.swift 一字不动。
@objcMembers
final class LyricsHUDController: UIViewController {

    var cardFrame = CGRect(x: 30, y: 180, width: 300, height: 126)

    private var hudView: LyricsHUDView?
    private var initialTransform = CGAffineTransform.identity

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let card = LyricsHUDView(frame: cardFrame)
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
