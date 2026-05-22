import FlyChat
import UIKit

/// `ExampleEntryViewController` — the launch screen offering the two demonstration styles.
/// Each card builds a themed ``ExampleChatDelegate`` and pushes the bridge-produced chat list.
final class ExampleEntryViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "FlyChat Examples"
        view.backgroundColor = .systemBackground

        let stack = UIStackView(arrangedSubviews: ExampleStyle.allCases.map(makeCard))
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Cards

    private func makeCard(for style: ExampleStyle) -> UIView {
        let card = StyleCardControl(style: style)
        card.addTarget(self, action: #selector(cardTapped(_:)), for: .touchUpInside)
        card.heightAnchor.constraint(equalToConstant: 132).isActive = true
        return card
    }

    @objc private func cardTapped(_ sender: StyleCardControl) {
        open(sender.style)
    }

    // MARK: - Routing

    private func open(_ style: ExampleStyle) {
        let delegate = ExamplePresets.delegate(for: style)
        let listVC = FCLUIKitBridge.makeChatListViewController(
            chats: ExampleSampleData.chats,
            title: style.listTitle,
            onChatTap: { [weak self] summary in
                self?.openChat(summary, delegate: delegate)
            },
            delegate: delegate
        )
        navigationController?.pushViewController(listVC, animated: true)
    }

    private func openChat(_ summary: FCLChatSummary, delegate: ExampleChatDelegate) {
        guard let navigationController else { return }
        let chatVC = ExampleChatScene.makeChatViewController(
            for: summary,
            delegate: delegate,
            onBack: { [weak navigationController] in
                navigationController?.popViewController(animated: true)
            }
        )
        navigationController.pushViewController(chatVC, animated: true)
    }
}

// MARK: - StyleCardControl

private final class StyleCardControl: UIControl {
    let style: ExampleStyle

    init(style: ExampleStyle) {
        self.style = style
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure() {
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let background: UIView
        if style.prefersGlassCard {
            background = Self.glassBackgroundView()
        } else {
            let solid = UIView()
            solid.backgroundColor = style.accent
            background = solid
        }
        background.isUserInteractionEnabled = false
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let title = UILabel()
        title.text = style.title
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = style.prefersGlassCard ? .label : .white

        let subtitle = UILabel()
        subtitle.text = style.subtitle
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.numberOfLines = 0
        subtitle.textColor = style.prefersGlassCard ? .secondaryLabel : UIColor.white.withAlphaComponent(0.9)

        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 6
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        accessibilityLabel = "\(style.title). \(style.subtitle)"
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.85 : 1.0 }
    }

    private static func glassBackgroundView() -> UIView {
        guard !UIAccessibility.isReduceTransparencyEnabled else {
            let solid = UIView()
            solid.backgroundColor = .secondarySystemBackground
            return solid
        }

        if #available(iOS 26, *) {
            let effect = UIGlassEffect(style: .regular)
            return UIVisualEffectView(effect: effect)
        } else {
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
    }
}
