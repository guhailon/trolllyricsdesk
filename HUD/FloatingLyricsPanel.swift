import UIKit

final class FloatingLyricsPanel: UIView {

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )

    private let backgroundImageView = UIImageView()

    private let titleLabel = UILabel()
    private let previousLabel = UILabel()
    private let currentLabel = UILabel()
    private let nextLabel = UILabel()

    private let closeButton = UIButton(type: .system)

    private var initialCenter: CGPoint = .zero
    private var initialTransform: CGAffineTransform = .identity

    var onClose: (() -> Void)?

    var style = FloatingLyricsStyle() {
        didSet {
            applyStyle()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGestures()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupGestures()
        applyStyle()
    }

    private func setupUI() {

        clipsToBounds = true
        layer.cornerRadius = 22

        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true

        addSubview(backgroundImageView)
        addSubview(blurView)

        [titleLabel, previousLabel,
         currentLabel, nextLabel].forEach {
            label in

            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 2
            addSubview(label)
        }

        titleLabel.font = .systemFont(
            ofSize: 11,
            weight: .medium
        )

        previousLabel.font = .systemFont(
            ofSize: 13
        )

        currentLabel.font = .boldSystemFont(
            ofSize: 20
        )

        nextLabel.font = .systemFont(
            ofSize: 13
        )

        closeButton.setImage(
            UIImage(systemName: "xmark.circle.fill"),
            for: .normal
        )

        closeButton.tintColor = .white
        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )

        addSubview(closeButton)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        backgroundImageView.frame = bounds
        blurView.frame = bounds

        titleLabel.frame = CGRect(
            x: 16, y: 8,
            width: bounds.width - 56,
            height: 20
        )

        closeButton.frame = CGRect(
            x: bounds.width - 34,
            y: 6,
            width: 26,
            height: 26
        )

        previousLabel.frame = CGRect(
            x: 12, y: 34,
            width: bounds.width - 24,
            height: 20
        )

        currentLabel.frame = CGRect(
            x: 12, y: 55,
            width: bounds.width - 24,
            height: 40
        )

        nextLabel.frame = CGRect(
            x: 12, y: 96,
            width: bounds.width - 24,
            height: 20
        )
    }

    private func setupGestures() {

        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePan(_:))
        )

        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinch(_:))
        )

        addGestureRecognizer(pinch)
    }

    @objc private func handlePan(
        _ gesture: UIPanGestureRecognizer
    ) {

        guard let parent = superview else {
            return
        }

        let translation = gesture.translation(
            in: parent
        )

        if gesture.state == .began {
            initialCenter = center
        }

        if gesture.state == .changed {
            center = CGPoint(
                x: initialCenter.x + translation.x,
                y: initialCenter.y + translation.y
            )
        }
    }

    @objc private func handlePinch(
        _ gesture: UIPinchGestureRecognizer
    ) {

        if gesture.state == .began {
            initialTransform = transform
        }

        if gesture.state == .changed {

            let scale = min(
                max(gesture.scale, 0.65),
                1.8
            )

            transform = initialTransform.scaledBy(
                x: scale,
                y: scale
            )
        }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    private func applyStyle() {

        alpha = style.opacity

        layer.cornerRadius = style.cornerRadius

        currentLabel.font = .boldSystemFont(
            ofSize: style.fontSize
        )

        currentLabel.textColor = style.highlightColor

        if !style.blurEnabled {
            blurView.isHidden = true
            backgroundColor = style.backgroundColor
        } else {
            blurView.isHidden = false
        }
    }

    func setAnimeBackground(_ image: UIImage?) {
        backgroundImageView.image = image
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
}
