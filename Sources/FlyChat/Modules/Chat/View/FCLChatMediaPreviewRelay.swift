import CoreGraphics

// MARK: - FCLChatMediaPreviewRelay

/// Reference-type bridge between the chat screen and ``FCLMediaPreviewSource``.
///
/// SwiftUI view structs cannot be `AnyObject`, so the chat screen holds this relay
/// instead of conforming directly. The attachment grid populates ``frames`` with
/// window-space cell rects; the previewer reads them on dismiss for the return animation.
@MainActor
final class FCLChatMediaPreviewRelay: FCLMediaPreviewSource {
    /// Window-space frames of visible attachment cells, keyed by `attachment.id.uuidString`.
    var frames: [String: CGRect] = [:]

    /// Returns the current window-space frame for the given attachment ID, or `nil`
    /// if the corresponding cell is not visible.
    func mediaPreviewFrame(forAssetID id: String) -> CGRect? {
        frames[id]
    }
}
