import UIKit

// HUD 进程的歌词控制器：根视图是全屏透明容器，歌词卡片是它上面的子视图。
// 卡片 frame 由 HUD delegate 定，默认用 FloatingLyricsController 同款
// frame（x 30、y 180、w 300、h 126）；关闭按钮调 TLHelper.stopHUD。
@objcMembers
final class LyricsHUDController: UIViewController {

    var cardFrame = CGRect(x: 30, y: 180, width: 300, height: 126)

    private var hudView: LyricsHUDView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let card = LyricsHUDView(frame: cardFrame)
        card.onClose = {
            TLHelper.stopHUD()
        }
        view.addSubview(card)
        hudView = card
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
