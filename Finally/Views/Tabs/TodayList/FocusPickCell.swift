import SwiftUI
import UIKit

/// A Daily Focus pick on the UIKit Today list: the number, the title over its deadline and
/// project, and the priority ring. An open pick stands at least 64 points tall. A finished pick
/// collapses to one 40-point struck-through line with a smaller number, and `setDone` animates
/// that change with the row's height.
final class FocusPickCell: UICollectionViewListCell {
    /// What the cell draws, worked out from a `DailyFocusList.Row`.
    struct Model: Equatable {
        var number: Int
        var title: String
        var meta: NSAttributedString?
        var isNext: Bool
        var isDone: Bool
        var ringColor: UIColor
    }

    /// Tapping the ring completes an open pick and reopens a finished one.
    var onToggle: (() -> Void)?

    private let numberLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let ring = PriorityRingControl()
    private var topPadding: NSLayoutConstraint!
    private var bottomPadding: NSLayoutConstraint!
    private var minHeight: NSLayoutConstraint!
    private(set) var model: Model?

    private static let doneNumberScale: CGFloat = 0.72

    override init(frame: CGRect) {
        super.init(frame: frame)
        numberLabel.font = .rounded(.title1, weight: .heavy)
        numberLabel.adjustsFontForContentSizeCategory = true
        numberLabel.textAlignment = .center
        numberLabel.isAccessibilityElement = false
        titleLabel.font = .preferredFont(forTextStyle: .title3, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        metaLabel.font = .rounded(.footnote)
        metaLabel.adjustsFontForContentSizeCategory = true
        ring.addAction(UIAction { [weak self] _ in self?.onToggle?() }, for: .primaryActionTriggered)

        let text = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        text.axis = .vertical
        text.spacing = 3
        for view in [numberLabel, text, ring] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        // The padding and the minimum height are floors, so the row takes whichever is taller.
        topPadding = text.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10)
        bottomPadding = contentView.bottomAnchor.constraint(greaterThanOrEqualTo: text.bottomAnchor, constant: 10)
        minHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            numberLabel.widthAnchor.constraint(equalToConstant: 26),
            numberLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 14),
            topPadding, bottomPadding, minHeight,
            text.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ring.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 14),
            ring.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -9),
            ring.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: 44),
            ring.heightAnchor.constraint(equalToConstant: 40),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    /// VoiceOver reads the pick as one element, and its ring is an action on that element.
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            let toggle = UIAccessibilityCustomAction(name: model?.isDone == true ? "Reopen" : "Complete") { [weak self] _ in
                self?.onToggle?()
                return true
            }
            return [toggle] + (super.accessibilityCustomActions ?? [])
        }
        set { super.accessibilityCustomActions = newValue }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws `model` at once.
    func show(_ model: Model) {
        self.model = model
        numberLabel.text = "\(model.number)"
        numberLabel.textColor = model.isNext ? UIColor(Palette.high) : UIColor(Palette.muted).withAlphaComponent(model.isDone ? 0.5 : 0.8)
        metaLabel.attributedText = model.meta
        ring.color = model.ringColor
        accessibilityLabel = "Pick \(model.number), \(model.title)"
        accessibilityValue = model.isDone ? "Done" : model.meta?.string
        applyDoneState(model)
    }

    /// Moves between open and done on the pick spring. The caller lays out the collection view
    /// inside the same animation, so the row's height eases with its content.
    func setDone(_ model: Model) {
        self.model = model
        UIView.transition(with: titleLabel, duration: 0.3, options: .transitionCrossDissolve) {
            self.titleLabel.attributedText = Self.title(model)
        }
        numberLabel.text = "\(model.number)"
        numberLabel.textColor = model.isNext ? UIColor(Palette.high) : UIColor(Palette.muted).withAlphaComponent(model.isDone ? 0.5 : 0.8)
        metaLabel.attributedText = model.meta
        accessibilityValue = model.isDone ? "Done" : model.meta?.string
        applyLayout(model)
        ring.isDone = model.isDone
    }

    private func applyDoneState(_ model: Model) {
        titleLabel.attributedText = Self.title(model)
        applyLayout(model)
        ring.isDone = model.isDone
    }

    private func applyLayout(_ model: Model) {
        let showsMeta = !model.isDone && model.meta != nil
        metaLabel.isHidden = !showsMeta
        metaLabel.alpha = showsMeta ? 1 : 0
        titleLabel.numberOfLines = model.isDone ? 1 : 2
        topPadding.constant = model.isDone ? 0 : 10
        bottomPadding.constant = model.isDone ? 0 : 10
        minHeight.constant = model.isDone ? 40 : 64
        numberLabel.transform = model.isDone ? CGAffineTransform(scaleX: Self.doneNumberScale, y: Self.doneNumberScale) : .identity
    }

    private static func title(_ model: Model) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: model.isDone ? UIColor(Palette.muted) : UIColor(Palette.ink),
        ]
        if model.isDone {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = UIColor(Palette.muted)
        }
        return NSAttributedString(string: model.title, attributes: attributes)
    }
}

/// The priority ring as a control: an open task draws a ring in its priority color over a faint
/// fill, and a finished one a green disc with a white checkmark.
final class PriorityRingControl: UIControl {
    var color: UIColor = UIColor(Palette.low) { didSet { update() } }
    var isDone = false { didSet { update() } }
    var doneFill: UIColor = UIColor(Palette.done) { didSet { update() } }
    var doneMark: UIColor = .white { didSet { update() } }
    var diameter: CGFloat = 24 { didSet { update() } }

    private let disc = UIView()
    private let check = UIImageView(image: UIImage(systemName: "checkmark"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [disc, check] as [UIView] {
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        disc.layer.borderWidth = 1.8
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        NSLayoutConstraint.activate([
            disc.centerXAnchor.constraint(equalTo: centerXAnchor),
            disc.centerYAnchor.constraint(equalTo: centerYAnchor),
            disc.widthAnchor.constraint(equalToConstant: 24),
            disc.heightAnchor.constraint(equalTo: disc.widthAnchor),
            check.centerXAnchor.constraint(equalTo: centerXAnchor),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        disc.layer.cornerRadius = 12
        accessibilityTraits = .button
        // The colors resolve for light or dark mode, so a mode change redraws them.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (ring: Self, _) in ring.update() }
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    private func update() {
        let resolved = color.resolvedColor(with: traitCollection)
        let done = doneFill.resolvedColor(with: traitCollection)
        disc.backgroundColor = isDone ? done : resolved.withAlphaComponent(0.1)
        disc.layer.borderColor = (isDone ? done : resolved).cgColor
        // The disc keeps its 24-point frame and scales, so a size change animates.
        let scale = (isDone ? diameter - 4 : diameter) / 24
        disc.transform = CGAffineTransform(scaleX: scale, y: scale)
        check.tintColor = doneMark
        check.alpha = isDone ? 1 : 0
        accessibilityLabel = isDone ? "Reopen" : "Complete"
    }
}

extension UIFont {
    /// The system face in SF Pro Rounded at a text style's size, scaled for Dynamic Type.
    static func rounded(_ style: TextStyle, weight: Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: defaultSize(style), weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: 0))
    }

    static func preferredFont(forTextStyle style: TextStyle, weight: Weight) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: defaultSize(style), weight: weight))
    }

    /// The style's size at the default Dynamic Type setting, which `UIFontMetrics` then scales.
    private static func defaultSize(_ style: TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
    }
}
