import CoreGraphics

// MARK: - FCLMediaPreviewSource

/// Supplies the on-screen rectangle of the cell currently rendering a given media asset.
///
/// The chat screen (or any host that presents the chat media previewer) adopts this
/// protocol so the preview can query the source frame for zoom-in / zoom-out style
/// dismissal.
///
/// Implementations are expected to walk the visible attachment grid and return the frame
/// of the cell that corresponds to the requested attachment identifier, expressed in the
/// key window's coordinate space. Returning `nil` indicates that the source cell is
/// offscreen — the preview then falls back to a center-collapse dismiss animation.
@MainActor
public protocol FCLMediaPreviewSource: AnyObject {
    /// Returns the on-screen frame in window coordinates for the cell rendering the given asset, or nil if the cell is not currently visible.
    ///
    /// - Parameter id: The stable identifier of the attachment whose source cell frame is requested.
    /// - Returns: A rectangle in the key window's coordinate space, or `nil` if the cell is not visible.
    func mediaPreviewFrame(forAssetID id: String) -> CGRect?
}

// MARK: - FCLMediaPreviewTransitionDescriptor

/// Snapshot of the presentation anchor used to drive the custom preview transition.
///
/// Captures the source cell's window-space frame at the moment presentation or dismissal
/// begins. When `sourceFrame` is `nil` the transition falls back to a centered collapse.
@MainActor
struct FCLMediaPreviewTransitionDescriptor {
    /// Stable attachment identifier the transition is anchored to.
    let assetID: String
    /// Source cell frame in window coordinates, or `nil` when the source cell is not visible.
    let sourceFrame: CGRect?
}

// MARK: - FCLMediaPreviewAspectFit

/// Computes the destination rectangle that fits `aspectRatio` inside `bounds` using
/// a Photos-app–style aspect fit.
///
/// The result fills by width when the content aspect is wider than `bounds`, by height
/// otherwise. Zero or negative inputs fall back to `bounds` unchanged.
///
/// - Parameters:
///   - aspectRatio: Content aspect ratio expressed as `width / height`.
///   - bounds: Container rectangle the content must fit inside.
/// - Returns: The centered, aspect-correct rectangle inside `bounds`.
@MainActor
func fclMediaPreviewAspectFit(aspectRatio: CGFloat, in bounds: CGRect) -> CGRect {
    guard aspectRatio.isFinite, aspectRatio > 0, bounds.width > 0, bounds.height > 0 else {
        return bounds
    }
    let boundsRatio = bounds.width / bounds.height
    let size: CGSize
    if aspectRatio > boundsRatio {
        size = CGSize(width: bounds.width, height: bounds.width / aspectRatio)
    } else {
        size = CGSize(width: bounds.height * aspectRatio, height: bounds.height)
    }
    let origin = CGPoint(
        x: bounds.midX - size.width / 2,
        y: bounds.midY - size.height / 2
    )
    return CGRect(origin: origin, size: size)
}
