import CoreGraphics

/// Default values for ``FCLAppearanceDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLAppearanceDelegate`` or does not override a specific property.
enum FCLAppearanceDefaults {
    /// Default outgoing bubble color: blue (RGB 0.0, 0.48, 1.0).
    static let senderBubbleColor = FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0)

    /// Default incoming bubble color: light gray (RGB 0.90, 0.91, 0.94).
    static let receiverBubbleColor = FCLChatColorToken(red: 0.90, green: 0.91, blue: 0.94)

    /// Default outgoing text color: white.
    static let senderTextColor = FCLChatColorToken(red: 1, green: 1, blue: 1)

    /// Default incoming text color: near-black (RGB 0.08, 0.08, 0.09).
    static let receiverTextColor = FCLChatColorToken(red: 0.08, green: 0.08, blue: 0.09)

    /// Default message font configuration using system defaults.
    static let messageFont = FCLChatMessageFontConfiguration()

    /// Default bubble tail style: edged with the tail at the bottom.
    static let tailStyle: FCLBubbleTailStyle = .edged(.bottom)

    /// Default minimum bubble height: 40 points.
    static let minimumBubbleHeight: CGFloat = 40
}

/// Default values for ``FCLLayoutDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLLayoutDelegate`` or does not override a specific property.
enum FCLLayoutDefaults {
    /// Default incoming message side: left.
    static let incomingSide: FCLChatBubbleSide = .left

    /// Default outgoing message side: right.
    static let outgoingSide: FCLChatBubbleSide = .right

    /// Default maximum bubble width ratio: 78% of available width.
    static let maxBubbleWidthRatio: CGFloat = 0.78

    /// Default vertical spacing between messages in the same sender group: 4 points.
    static let intraGroupSpacing: CGFloat = 4

    /// Default vertical spacing between different sender groups: 12 points.
    static let interGroupSpacing: CGFloat = 12
}

/// Default values for ``FCLAvatarDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLAvatarDelegate`` or does not override a specific property.
enum FCLAvatarDefaults {
    /// Default avatar size: 40x40 points.
    static let avatarSize: CGFloat = 40

    /// Whether outgoing message avatars are shown by default: `false`.
    static let showOutgoingAvatar = false

    /// Whether incoming message avatars are shown by default: `true`.
    static let showIncomingAvatar = true
}

/// Default values for ``FCLInputDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLInputDelegate`` or does not override a specific property.
enum FCLInputDefaults {
    /// Default placeholder text: `"Message"`.
    static let placeholderText = "Message"

    /// Default minimum text length to enable send: `1` character.
    static let minimumTextLength = 1

    /// Default maximum visible rows: `nil` (unlimited growth).
    static let maxRows: Int? = nil

    /// Default attachment button visibility: `true`.
    static let showAttachButton = true

    /// Default container mode: `.fieldOnlyRounded`.
    static let containerMode: FCLInputBarContainerMode = .fieldOnlyRounded

    /// Default Liquid Glass effect state: `false` (disabled).
    static let liquidGlass = false

    /// Default input bar background color: light gray (RGB 0.93, 0.94, 0.96).
    static let backgroundColor = FCLChatColorToken(red: 0.93, green: 0.94, blue: 0.96)

    /// Default text field background color: white.
    static let fieldBackgroundColor = FCLChatColorToken(red: 1, green: 1, blue: 1)

    /// Default text field corner radius: 18 points.
    static let fieldCornerRadius: CGFloat = 18

    /// Default explicit line height: `nil` (uses system default).
    static let lineHeight: CGFloat? = nil

    /// Default Return key behavior: `true` (sends message).
    static let returnKeySends = true

    /// Default content insets around the input bar's inner content.
    static let contentInsets = FCLEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)

    /// Default spacing between input bar elements: 8 points.
    static let elementSpacing: CGFloat = 8

    /// Default attachment thumbnail preview size: 32 points.
    static let attachmentThumbnailSize: CGFloat = 32
}
