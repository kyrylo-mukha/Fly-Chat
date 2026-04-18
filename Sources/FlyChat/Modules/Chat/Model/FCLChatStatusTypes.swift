import SwiftUI

// MARK: - FCLChatStatusIcons

/// A set of three images used as the default glyphs for each delivery status state.
///
/// Provide an instance via `FCLAppearanceDelegate.statusIcons` to override the built-in
/// SF Symbol / path defaults. Each slot is optional: a `nil` value means the library
/// falls back to its built-in glyph for that state.
///
/// Custom images are rendered with `.renderingMode(.template)` so they inherit the color
/// token from `FCLAppearanceDelegate.statusColors`. If you supply a symbol configured
/// with `.original` rendering mode, SwiftUI will honour that and the tint will not be forced.
public struct FCLChatStatusIcons: Sendable {
    /// Glyph shown when the message status is `.created`.
    ///
    /// Default: `nil` (library uses the `clock` SF Symbol).
    public let created: Image?

    /// Glyph shown when the message status is `.sent`.
    ///
    /// Default: `nil` (library uses the `checkmark` SF Symbol).
    public let sent: Image?

    /// Glyph shown when the message status is `.read`.
    ///
    /// Default: `nil` (library draws a custom double-checkmark path).
    public let read: Image?

    /// Creates a status icon set.
    ///
    /// Pass `nil` for any slot to keep the library's built-in glyph for that state.
    public init(
        created: Image? = nil,
        sent: Image? = nil,
        read: Image? = nil
    ) {
        self.created = created
        self.sent = sent
        self.read = read
    }
}

// MARK: - FCLChatStatusColors

/// Color tokens applied to each delivery status glyph.
///
/// Provide an instance via `FCLAppearanceDelegate.statusColors` to override the defaults.
/// The `read` state defaults to a vivid accent color; `created` and `sent` use a muted
/// foreground token suitable for display inside an outgoing bubble.
public struct FCLChatStatusColors: Sendable, Hashable {
    /// Color applied to the glyph when status is `.created`.
    public let created: FCLChatColorToken

    /// Color applied to the glyph when status is `.sent`.
    public let sent: FCLChatColorToken

    /// Color applied to the glyph when status is `.read`.
    ///
    /// Defaults to a vivid green accent to signal that the message has been seen.
    public let read: FCLChatColorToken

    /// Creates a status color set.
    ///
    /// - Parameters:
    ///   - created: Color token for the `.created` glyph.
    ///   - sent: Color token for the `.sent` glyph.
    ///   - read: Color token for the `.read` glyph.
    public init(
        created: FCLChatColorToken,
        sent: FCLChatColorToken,
        read: FCLChatColorToken
    ) {
        self.created = created
        self.sent = sent
        self.read = read
    }
}
