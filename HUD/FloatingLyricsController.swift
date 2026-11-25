import UIKit

final class FloatingLyricsController {

    static let shared = FloatingLyricsController()

    private var panel: FloatingLyricsPanel?

    private init() {}

    func show(in hostView: UIView) {

        guard panel == nil else {
            return
        }

        let frame = CGRect(
            x: 30,
            y: 180,
            width: 300,
            height: 126
        )

        let view = FloatingLyricsPanel(frame: frame)

        view.onClose = { [weak self] in
            self?.hide()
        }

        view.updateLyrics(
            title: "TrollLyricsDesk",
            previous: "上一句歌词",
            current: "当前正在播放的歌词",
            next: "下一句歌词"
        )

        hostView.addSubview(view)

        panel = view
    }

    func hide() {
        panel?.removeFromSuperview()
        panel = nil
    }

    func update(
        title: String,
        previous: String,
        current: String,
        next: String
    ) {

        panel?.updateLyrics(
            title: title,
            previous: previous,
            current: current,
            next: next
        )
    }

    func setBackground(_ image: UIImage?) {
        panel?.setAnimeBackground(image)
    }
}
