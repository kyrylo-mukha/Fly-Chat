import UIKit

/// `ExampleStyle` — the two demonstration configurations offered on the entry screen.
enum ExampleStyle: CaseIterable {
    case liquidGlass
    case solid

    var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .solid: "Solid Backgrounds"
        }
    }

    var subtitle: String {
        switch self {
        case .liquidGlass: "Translucent glass chrome — iOS 26 native, iOS 17/18 fallback."
        case .solid: "Opaque, solid element backgrounds — the non-glass style."
        }
    }

    var listTitle: String {
        switch self {
        case .liquidGlass: "Glass Chats"
        case .solid: "Solid Chats"
        }
    }

    var accent: UIColor {
        switch self {
        case .liquidGlass: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        case .solid: UIColor(red: 0.13, green: 0.55, blue: 0.45, alpha: 1.0)
        }
    }

    var prefersGlassCard: Bool { self == .liquidGlass }
}
