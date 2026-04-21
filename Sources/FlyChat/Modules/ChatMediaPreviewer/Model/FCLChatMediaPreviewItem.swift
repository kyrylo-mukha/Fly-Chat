import Foundation
import CoreGraphics

// MARK: - FCLChatMediaPreviewSourceDelegate

/// Data feed the chat media previewer observes to derive its pager contents.
///
/// The chat presenter adopts this protocol so the previewer module stays free of
/// any compile-time dependency on chat-module concrete types. The previewer reads
/// the ordered list of conversation media but does not mutate it.
@MainActor
public protocol FCLChatMediaPreviewSourceDelegate: AnyObject, ObservableObject {
    /// All image and video attachments across the conversation in chronological order,
    /// each paired with the message identifier and its index within that message's media run.
    var allConversationMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)] { get }

    /// Returns the current window-space frame for the cell rendering the given attachment,
    /// or `nil` when the cell is not visible on screen.
    ///
    /// The previewer calls this at dismiss-time to zoom the content back into its
    /// originating cell. A `nil` return triggers the center-collapse fallback animation
    /// (shrink to 0×0 at screen center, alpha → 0, duration 0.28s easeIn).
    ///
    /// - Parameter id: Stable identifier of the attachment whose cell frame is requested.
    func currentFrame(forItemID id: UUID) -> CGRect?

    /// Requests the data source to scroll the cell for the given attachment into view.
    ///
    /// Called by the previewer immediately before dismissal when the source cell is
    /// not currently visible, giving the host an opportunity to bring it on-screen so
    /// the zoom-back animation can target a real frame. Implementations may choose to
    /// scroll synchronously, asynchronously, or not at all; returning `false` signals
    /// that the cell will not be made visible and the previewer should use the
    /// center-collapse fallback immediately.
    ///
    /// - Parameters:
    ///   - id: Stable identifier of the attachment whose source cell should become visible.
    ///   - animated: `true` when the scroll should be animated.
    /// - Returns: `true` if the cell will be visible by the time dismiss begins; `false` otherwise.
    func ensureVisible(itemID id: UUID, animated: Bool) -> Bool
}

public extension FCLChatMediaPreviewSourceDelegate {
    func currentFrame(forItemID id: UUID) -> CGRect? { nil }

    func ensureVisible(itemID id: UUID, animated: Bool) -> Bool { false }
}

// MARK: - Backward Compatibility Typealias

/// Backward-compatibility alias for hosts that adopted the previous protocol name.
/// Deprecated: use `FCLChatMediaPreviewSourceDelegate` directly.
public typealias FCLChatMediaPreviewDataSource = FCLChatMediaPreviewSourceDelegate

// MARK: - FCLChatMediaPreviewItem

/// Minimal payload describing a single asset the chat media previewer should open to.
///
/// The chat screen constructs this when the user taps an attachment cell. It carries
/// the asset identifier, a reference back to the concrete attachment, and the
/// window-space frame of the originating cell so the previewer can drive a zoom
/// transition from the tapped cell.
///
/// The type is main-actor confined because `sourceFrame` is gathered on the main
/// thread from live SwiftUI geometry and has no meaning off the main actor.
@MainActor
public struct FCLChatMediaPreviewItem: Identifiable {
    /// Stable identifier of the attachment the previewer should anchor to.
    public let id: UUID
    /// Reference to the concrete attachment being previewed.
    public let asset: FCLAttachment
    /// Window-space frame of the source cell at the moment the preview was
    /// requested, or `nil` when the cell is offscreen (previewer falls back to a
    /// center-collapse transition).
    public let sourceFrame: CGRect?

    /// Creates a new preview item.
    /// - Parameters:
    ///   - id: Identifier for the item. Defaults to `asset.id` so downstream
    ///     consumers can correlate items with attachments directly.
    ///   - asset: The concrete attachment to preview.
    ///   - sourceFrame: Window-space frame of the originating cell, if visible.
    public init(id: UUID? = nil, asset: FCLAttachment, sourceFrame: CGRect? = nil) {
        self.id = id ?? asset.id
        self.asset = asset
        self.sourceFrame = sourceFrame
    }
}
