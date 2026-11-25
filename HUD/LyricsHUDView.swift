import UIKit

final class LyricsHUDView: UIView {

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemThinMaterialDark)
    )

    private let animeImageView = UIImageView()

    private let titleLabel = UILabel()
    private let previousLabel = UILabel()
    private let currentLabel = UILabel()
    private let nextLabel = UILabel()

    private let closeButton = UIButton(type: .system)

    private var dragOrigin: CGPoint = .zero

    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        clipsToBounds = true
        layer.cornerRadius = 20

        blurView.frame = bounds
        blurView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]
        addSubview(blurView)

        animeImageView.frame = bounds
        animeImageView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]
        animeImageView.contentMode = .scaleAspectFill
        animeImageView.alpha = 0.32
        addSubview(animeImageView)

        titleLabel.text = "TrollLyricsDesk"
        titleLabel.font = .systemFont(
            ofSize: 11,
            weight: .medium
        )
        titleLabel.textColor = .white

        previousLabel.font = .systemFont(ofSize: 13)
        previousLabel.textColor = .white.withAlphaComponent(0.55)

        currentLabel.font = .boldSystemFont(ofSize: 20)
        currentLabel.textColor = .white
        currentLabel.numberOfLines = 2

        nextLabel.font = .systemFont(ofSize: 13)
        nextLabel.textColor = .white.withAlphaComponent(0.55)

        closeButton.setTitle("×", for: .normal)
        closeButton.tintColor = .white
        closeButton.titleLabel?.font = .systemFont(
            ofSize: 23,
            weight: .light
        )
        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            previousLabel,
            currentLabel,
            nextLabel
        ])

        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 16
            ),
            stack.trailingAnchor.constraint(
                equalTo: closeButton.leadingAnchor,
                constant: -8
            ),
            stack.centerYAnchor.constraint(
                equalTo: centerYAnchor
            ),

            closeButton.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 5
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -8
            ),
            closeButton.widthAnchor.constraint(
                equalToConstant: 30
            ),
            closeButton.heightAnchor.constraint(
                equalToConstant: 30
            )
        ])
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePan(_:))
        )

        addGestureRecognizer(pan)
    }

    @objc private func handlePan(
        _ gesture: UIPanGestureRecognizer
    ) {
        guard let parent = superview else { return }

        let translation = gesture.translation(in: parent)

        switch gesture.state {
        case .began:
            dragOrigin = center

        case .changed:
            var newCenter = CGPoint(
                x: dragOrigin.x + translation.x,
                y: dragOrigin.y + translation.y
            )

            let halfWidth = bounds.width / 2
            let halfHeight = bounds.height / 2

            newCenter.x = min(
                max(newCenter.x, halfWidth),
                parent.bounds.width - halfWidth
            )

            newCenter.y = min(
                max(newCenter.y, halfHeight),
                parent.bounds.height - halfHeight
            )

            center = newCenter

        default:
            break
        }
    }

    func updateLyrics(
        title: String,
        previous: String,
        current: String,
        next: String
    ) {
        titleLabel.text = title
        previousLabel.text = previous
        currentLabel.text = current
        nextLabel.text = next
    }

    func setAnimeBackground(_ image: UIImage?) {
        animeImageView.image = image
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
