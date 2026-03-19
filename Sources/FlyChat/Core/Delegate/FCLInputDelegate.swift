import CoreGraphics

/// Delegate protocol for customizing the chat input bar appearance and behavior.
///
/// Implement this protocol in the host app and return it from ``FCLChatDelegate/input``
/// to control placeholder text, field styling, button visibility, keyboard behavior, and more.
/// Every property has a default implementation that returns the corresponding value from
/// ``FCLInputDefaults``, so you only need to override the properties you want to customize.
@MainActor
public protocol FCLInputDelegate: AnyObject {
    /// The placeholder text displayed in the input field when it is empty.
    ///
    /// Default: `"Message"`.
    var placeholderText: String { get }

    /// The minimum number of characters required before the send button becomes enabled.
    ///
    /// Default: `1`.
    var minimumTextLength: Int { get }

    /// The maximum number of visible text rows before the input field begins scrolling.
    ///
    /// Set to `nil` to allow unlimited vertical growth.
    /// Default: `nil` (unlimited).
    var maxRows: Int? { get }

    /// Whether to show the attachment button in the input bar.
    ///
    /// Default: `true`.
    var showAttachButton: Bool { get }

    /// The visual container mode for the input bar (e.g., all-in-rounded, field-only, custom).
    ///
    /// Default: `.fieldOnlyRounded`.
    var containerMode: FCLInputBarContainerMode { get }

    /// Whether to apply the Liquid Glass visual effect (iOS 26+) to the input bar.
    ///
    /// Default: `false`.
    var liquidGlass: Bool { get }

    /// The background color of the entire input bar container area.
    ///
    /// Default: light gray (`FCLInputDefaults.backgroundColor`).
    var backgroundColor: FCLChatColorToken { get }

    /// The background color of the text input field itself.
    ///
    /// Default: white (`FCLInputDefaults.fieldBackgroundColor`).
    var fieldBackgroundColor: FCLChatColorToken { get }

    /// The corner radius of the text input field, in points.
    ///
    /// Default: `18`.
    var fieldCornerRadius: CGFloat { get }

    /// An explicit line height for the text in the input field, in points.
    ///
    /// Set to `nil` to use the system default line height for the current font.
    /// Default: `nil`.
    var lineHeight: CGFloat? { get }

    /// Whether pressing the Return key sends the message instead of inserting a newline.
    ///
    /// Default: `true`.
    var returnKeySends: Bool { get }

    /// The padding between the input bar's container edge and its contents.
    ///
    /// Default: `FCLEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)`.
    var contentInsets: FCLEdgeInsets { get }

    /// Horizontal spacing (in points) between elements in the input bar (e.g., between the field and buttons).
    ///
    /// Default: `8`.
    var elementSpacing: CGFloat { get }

    /// The size (in points) of attachment thumbnail previews shown in the input bar.
    ///
    /// Default: `32`.
    var attachmentThumbnailSize: CGFloat { get }
}

public extension FCLInputDelegate {
    var placeholderText: String { FCLInputDefaults.placeholderText }
    var minimumTextLength: Int { FCLInputDefaults.minimumTextLength }
    var maxRows: Int? { FCLInputDefaults.maxRows }
    var showAttachButton: Bool { FCLInputDefaults.showAttachButton }
    var containerMode: FCLInputBarContainerMode { FCLInputDefaults.containerMode }
    var liquidGlass: Bool { FCLInputDefaults.liquidGlass }
    var backgroundColor: FCLChatColorToken { FCLInputDefaults.backgroundColor }
    var fieldBackgroundColor: FCLChatColorToken { FCLInputDefaults.fieldBackgroundColor }
    var fieldCornerRadius: CGFloat { FCLInputDefaults.fieldCornerRadius }
    var lineHeight: CGFloat? { FCLInputDefaults.lineHeight }
    var returnKeySends: Bool { FCLInputDefaults.returnKeySends }
    var contentInsets: FCLEdgeInsets { FCLInputDefaults.contentInsets }
    var elementSpacing: CGFloat { FCLInputDefaults.elementSpacing }
    var attachmentThumbnailSize: CGFloat { FCLInputDefaults.attachmentThumbnailSize }
}
