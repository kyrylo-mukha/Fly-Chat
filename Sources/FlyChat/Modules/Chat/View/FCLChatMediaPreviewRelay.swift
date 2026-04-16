#if canImport(UIKit)
import UIKit

// MARK: - FCLChatMediaPreviewRelay

/// Concrete ``FCLMediaPreviewSource`` implementation owned by the chat screen.
///
/// SwiftUI view structs cannot be `AnyObject`, so the chat screen holds this small
/// reference-type relay instead of adopting ``FCLMediaPreviewSource`` directly. The
/// attachment grid reports the window-space frames of visible cells into the relay's
/// ``frames`` dictionary (keyed by `attachment.id.uuidString`). The chat media
/// previewer reads those frames on dismiss to animate content back into the
/// originating cell; if the key is missing the preview collapses to a zero-size
/// point at the screen center.
@MainActor
final class FCLChatMediaPreviewRelay: FCLMediaPreviewSource {
    /// Window-space frames of currently-visible attachment cells, keyed by the
    /// attachment's `uuidString`. Updated as the chat timeline scrolls and as cells
    /// enter/leave the visible region.
    var frames: [String: CGRect] = [:]

    /// Returns the current window-space frame for the given attachment ID, or `nil`
    /// if the corresponding cell is not visible.
    func mediaPreviewFrame(forAssetID id: String) -> CGRect? {
        frames[id]
    }
}
#endif
