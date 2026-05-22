import UIKit

/// `ExampleGlassNavigation` — host-owned navigation chrome for the Liquid Glass chat.
///
/// The FlyChat library is navigation-agnostic and renders no nav bar, so the host supplies
/// transparent navigation chrome that lets the chat content show through, a centered bold
/// title, and a floating glass circular back button.
@MainActor
enum ExampleGlassNavigation {

    /// Configures a pushed chat controller with a transparent bar, a centered bold title, and a
    /// floating glass back button.
    ///
    /// The transparent `UINavigationItem` appearance removes the opaque fill and bottom hairline
    /// on iOS 17/18 and lets the system Liquid Glass scroll-edge effect render on iOS 26 — so the
    /// chat content shows through. The override is scoped to this controller, leaving the entry
    /// screen's own bar untouched.
    ///
    /// On iOS 26 the system already renders the back button as a floating Liquid Glass circle, so
    /// the native button is kept and drives the pop. On iOS 17/18 the system back button is a
    /// flat chevron, so it is replaced with a custom circular `UIBlurEffect`-backed button that
    /// reads as glass. Both paths preserve the standard pop-to-previous behavior.
    /// - Parameters:
    ///   - controller: The pushed chat controller to decorate.
    ///   - title: The partner name shown as the centered heading.
    ///   - onBack: The action invoked by the iOS 17/18 fallback back button.
    static func applyChatChrome(
        to controller: UIViewController,
        title: String,
        onBack: @escaping () -> Void
    ) {
        let item = controller.navigationItem
        item.title = title
        item.largeTitleDisplayMode = .never

        if #unavailable(iOS 26) {
            let backButton = GlassBackButton(action: UIAction { _ in onBack() })
            let barItem = UIBarButtonItem(customView: backButton)
            barItem.accessibilityLabel = "Back"
            item.hidesBackButton = true
            item.leftBarButtonItem = barItem
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .headline)
        ]
        item.standardAppearance = appearance
        item.compactAppearance = appearance
        item.scrollEdgeAppearance = appearance
        item.compactScrollEdgeAppearance = appearance
    }
}

// MARK: - GlassBackButton

/// A circular `UIBlurEffect`-backed back button for iOS 17/18, where the system does not
/// supply Liquid Glass bar items. Honors Reduce Transparency by falling back to an opaque fill.
private final class GlassBackButton: UIControl {
    private let diameter: CGFloat = 38

    init(action: UIAction) {
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        addAction(action, for: .touchUpInside)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize { CGSize(width: diameter, height: diameter) }

    private func configure() {
        layer.cornerRadius = diameter / 2
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let background = backgroundView()
        background.isUserInteractionEnabled = false
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.backward"))
        chevron.contentMode = .center
        chevron.tintColor = .label
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            font: .preferredFont(forTextStyle: .body), scale: .medium
        )
        chevron.isUserInteractionEnabled = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.centerXAnchor.constraint(equalTo: centerXAnchor),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])

        accessibilityLabel = "Back"
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    private func backgroundView() -> UIView {
        guard !UIAccessibility.isReduceTransparencyEnabled else {
            let solid = UIView()
            solid.backgroundColor = .secondarySystemBackground
            return solid
        }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        return blur
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1.0 }
    }
}
