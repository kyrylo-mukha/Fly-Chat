import CoreGraphics
import SwiftUI

/// Delegate protocol for customizing the visual appearance of chat bubbles and message text.
///
/// Implement this protocol in the host app and return it from ``FCLChatDelegate/appearance``
/// to override default colors, fonts, tail styles, and bubble sizing. Every property has a
/// default implementation that returns the corresponding value from ``FCLAppearanceDefaults``,
/// so you only need to override the properties you want to customize.
@MainActor
public protocol FCLAppearanceDelegate: AnyObject {
    /// The background color of outgoing (sender) message bubbles.
    ///
    /// Default: blue (`FCLAppearanceDefaults.senderBubbleColor`).
    var senderBubbleColor: FCLChatColorToken { get }

    /// The background color of incoming (receiver) message bubbles.
    ///
    /// Default: light gray (`FCLAppearanceDefaults.receiverBubbleColor`).
    var receiverBubbleColor: FCLChatColorToken { get }

    /// The text color used inside outgoing (sender) message bubbles.
    ///
    /// Default: white (`FCLAppearanceDefaults.senderTextColor`).
    var senderTextColor: FCLChatColorToken { get }

    /// The text color used inside incoming (receiver) message bubbles.
    ///
    /// Default: near-black (`FCLAppearanceDefaults.receiverTextColor`).
    var receiverTextColor: FCLChatColorToken { get }

    /// Font configuration for message text, controlling size and weight.
    ///
    /// Default: `FCLChatMessageFontConfiguration()` (system defaults).
    var messageFont: FCLChatMessageFontConfiguration { get }

    /// The tail style applied to message bubbles (e.g., edged, none).
    ///
    /// Default: `.edged(.bottom)`.
    var tailStyle: FCLBubbleTailStyle { get }

    /// The minimum height of a message bubble, in points.
    ///
    /// Ensures that very short messages still render a comfortably tappable bubble.
    /// Default: `40`.
    var minimumBubbleHeight: CGFloat { get }

    /// Edge insets applied around the attachment image grid inside a bubble, in points.
    ///
    /// - Important: Deprecated. The attachment inset is now fixed at 1pt on all sides
    ///   (`FCLChatLayout.attachmentInset`). Any value returned by this property is ignored
    ///   by the library. The property remains in the protocol for source compatibility only.
    @available(*, deprecated, message: "Attachment inset is now fixed at 1pt; value is ignored. Use FCLChatLayout.attachmentInset.")
    var attachmentInsets: FCLEdgeInsets { get }

    /// Spacing between individual attachment cells within the image grid, in points.
    ///
    /// Default: `1`.
    var attachmentItemSpacing: CGFloat { get }

    /// Custom icons for the three message delivery status states.
    ///
    /// Each slot is optional; a `nil` value in a slot causes the library to use its built-in
    /// glyph for that state (SF Symbol for `.created` / `.sent`; a custom path for `.read`).
    /// Default: `FCLChatStatusIcons()` (all slots `nil` — all built-in glyphs used).
    var statusIcons: FCLChatStatusIcons { get }

    /// Color tokens applied to the delivery status glyph for each state.
    ///
    /// Default: muted white for `.created` and `.sent`; vivid green accent for `.read`.
    var statusColors: FCLChatStatusColors { get }
}

public extension FCLAppearanceDelegate {
    var senderBubbleColor: FCLChatColorToken { FCLAppearanceDefaults.senderBubbleColor }
    var receiverBubbleColor: FCLChatColorToken { FCLAppearanceDefaults.receiverBubbleColor }
    var senderTextColor: FCLChatColorToken { FCLAppearanceDefaults.senderTextColor }
    var receiverTextColor: FCLChatColorToken { FCLAppearanceDefaults.receiverTextColor }
    var messageFont: FCLChatMessageFontConfiguration { FCLAppearanceDefaults.messageFont }
    var tailStyle: FCLBubbleTailStyle { FCLAppearanceDefaults.tailStyle }
    var minimumBubbleHeight: CGFloat { FCLAppearanceDefaults.minimumBubbleHeight }
    @available(*, deprecated, message: "Attachment inset is now fixed at 1pt; value is ignored. Use FCLChatLayout.attachmentInset.")
    var attachmentInsets: FCLEdgeInsets { FCLAppearanceDefaults.attachmentInsets }
    var attachmentItemSpacing: CGFloat { FCLAppearanceDefaults.attachmentItemSpacing }
    var statusIcons: FCLChatStatusIcons { FCLAppearanceDefaults.statusIcons }
    var statusColors: FCLChatStatusColors { FCLAppearanceDefaults.statusColors }
}
