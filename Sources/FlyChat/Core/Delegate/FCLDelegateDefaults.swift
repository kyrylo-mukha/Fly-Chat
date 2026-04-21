import CoreGraphics
import SwiftUI

// MARK: - FCLChatLayout

/// Fixed layout constants for the chat timeline.
///
/// These values are not delegate-customizable and represent the library's canonical
/// geometry for structural layout decisions.
public enum FCLChatLayout {
    /// Fixed inset (in points) applied on all edges of the attachment grid container
    /// inside a chat bubble. The delegate-customizable `attachmentInsets` property is
    /// deprecated; this constant is used instead.
    public static let attachmentInset: CGFloat = 1
}

// MARK: - FCLAppearanceDefaults

/// Default values for ``FCLAppearanceDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLAppearanceDelegate`` or does not override a specific property.
enum FCLAppearanceDefaults {
    static let senderBubbleColor = FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0)
    static let receiverBubbleColor = FCLChatColorToken(red: 0.914, green: 0.914, blue: 0.922)
    static let senderTextColor = FCLChatColorToken(red: 1, green: 1, blue: 1)
    static let receiverTextColor = FCLChatColorToken(red: 0.08, green: 0.08, blue: 0.09)
    static let messageFont = FCLChatMessageFontConfiguration()
    static let tailStyle: FCLBubbleTailStyle = .edged(.bottom)
    static let minimumBubbleHeight: CGFloat = 40
    static let attachmentInsets = FCLEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
    static let attachmentItemSpacing: CGFloat = 1
    /// `read` slot is `nil` by convention — `FCLChatMessageStatusView` falls back to
    /// the custom `FCLDoubleCheckmarkShape` path when no icon is supplied.
    static let statusIcons = FCLChatStatusIcons()
    static let statusColors = FCLChatStatusColors(
        created: FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.6),
        sent: FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.6),
        read: FCLChatColorToken(red: 0.27, green: 0.78, blue: 0.47)
    )
}

/// Default values for ``FCLLayoutDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLLayoutDelegate`` or does not override a specific property.
enum FCLLayoutDefaults {
    static let incomingSide: FCLChatBubbleSide = .left
    static let outgoingSide: FCLChatBubbleSide = .right
    static let maxBubbleWidthRatio: CGFloat = 0.78
    static let intraGroupSpacing: CGFloat = 3
    static let interGroupSpacing: CGFloat = 10
    static let showsStatusForOutgoing = true
}

/// Default values for ``FCLAvatarDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLAvatarDelegate`` or does not override a specific property.
enum FCLAvatarDefaults {
    static let avatarSize: CGFloat = 28
    static let showOutgoingAvatar = false
    static let showIncomingAvatar = true
}

/// Default values for ``FCLInputDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLInputDelegate`` or does not override a specific property.
enum FCLInputDefaults {
    static let placeholderText = "Message"
    static let minimumTextLength = 1
    static let maxRows: Int? = nil
    static let showAttachButton = true
    static let containerMode: FCLInputBarContainerMode = .fieldOnlyRounded
    static let liquidGlass = false
    static let backgroundColor = FCLChatColorToken(red: 0.93, green: 0.94, blue: 0.96)
    static let fieldBackgroundColor = FCLChatColorToken(red: 1, green: 1, blue: 1)
    /// 22pt = half of the 44pt minimum hit target, producing a full-pill shape.
    static let fieldCornerRadius: CGFloat = 22
    static let lineHeight: CGFloat? = nil
    static let returnKeySends = true
    static let contentInsets = FCLEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    static let elementSpacing: CGFloat = 8
    static let attachmentThumbnailSize: CGFloat = 32
}

#if canImport(UIKit)
/// Default values for ``FCLAttachmentDelegate`` properties.
///
/// These constants are used as fallbacks when the host app does not provide
/// a custom ``FCLAttachmentDelegate`` or does not override a specific property.
enum FCLAttachmentDefaults {
    static let mediaCompression: FCLMediaCompression = .default
    static let recentFiles: [FCLRecentFile] = []
    static let customTabs: [any FCLCustomAttachmentTab] = []
    static let isVideoEnabled = true
    static let isFileTabEnabled = true
    static let isCameraVideoEnabled = true
    static let tabTransition: FCLPickerTabTransition = .slide
}
#endif
