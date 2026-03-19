import CoreGraphics
import SwiftUI

/// A platform-agnostic RGBA color token used for chat bubble and text colors.
///
/// `FCLChatColorToken` stores clamped (0...1) RGBA components and provides a
/// computed SwiftUI `Color` via the ``color`` property. It is `Sendable` and
/// `Hashable`, making it safe to pass across concurrency boundaries and suitable
/// as a dictionary key or set element.
public struct FCLChatColorToken: Sendable, Hashable {
    /// The red component of the color, clamped to `0...1`.
    public let red: Double
    /// The green component of the color, clamped to `0...1`.
    public let green: Double
    /// The blue component of the color, clamped to `0...1`.
    public let blue: Double
    /// The alpha (opacity) component of the color, clamped to `0...1`.
    public let alpha: Double

    /// Creates a color token with the given RGBA components.
    ///
    /// Each component is clamped to the `0...1` range.
    ///
    /// - Parameters:
    ///   - red: The red component (0...1).
    ///   - green: The green component (0...1).
    ///   - blue: The blue component (0...1).
    ///   - alpha: The alpha (opacity) component (0...1). Defaults to `1` (fully opaque).
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    /// A SwiftUI `Color` constructed from this token's RGBA components.
    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// Represents a font weight for chat message text, mapping to SwiftUI `Font.Weight`.
///
/// Use this enum to configure message font weight in a `Sendable`-safe manner
/// without depending directly on SwiftUI types in configuration APIs.
public enum FCLChatFontWeight: String, Sendable, Hashable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    /// The corresponding SwiftUI `Font.Weight` value.
    var swiftUIFontWeight: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

/// Configuration for the font used in chat message text bubbles.
///
/// Supports both system fonts (via ``size`` and ``weight``) and custom fonts
/// (via ``familyName``). The minimum font size is clamped to 9pt.
public struct FCLChatMessageFontConfiguration: Sendable, Hashable {
    /// An optional custom font family name (e.g., `"Avenir Next"`).
    /// When `nil` or empty, a system font is used instead.
    public let familyName: String?
    /// The font size in points. Clamped to a minimum of 9pt.
    public let size: CGFloat
    /// The font weight applied when using a system font. Ignored when ``familyName`` is set.
    public let weight: FCLChatFontWeight

    /// Creates a message font configuration.
    ///
    /// - Parameters:
    ///   - familyName: An optional custom font family name. Pass `nil` to use the system font.
    ///   - size: The font size in points. Values below 9 are clamped to 9. Defaults to `17`.
    ///   - weight: The font weight for system fonts. Defaults to `.regular`.
    public init(
        familyName: String? = nil,
        size: CGFloat = 17,
        weight: FCLChatFontWeight = .regular
    ) {
        self.familyName = familyName
        self.size = max(size, 9)
        self.weight = weight
    }

    /// A SwiftUI `Font` built from this configuration.
    ///
    /// Returns a custom font when ``familyName`` is provided, otherwise a weighted system font.
    public var font: Font {
        if let familyName, familyName.isEmpty == false {
            return .custom(familyName, size: size)
        }
        return .system(size: size, weight: weight.swiftUIFontWeight)
    }
}
