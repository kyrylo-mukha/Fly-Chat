import Foundation

// MARK: - FCLAttachmentInputDelegate

/// Delegate protocol that lets the host app tune the caption field line count in
/// the attachment preview relative to the chat's main input.
///
/// The preview's max visible lines = `chatMaxLines + attachmentInputLineCountDelta(chatMaxLines:)`.
/// Return `Int.min` to force a single line regardless of `chatMaxLines`. The effective
/// value is always clamped by ``fclAttachmentInputEffectiveLines(chatMax:delta:)``.
@MainActor
public protocol FCLAttachmentInputDelegate: AnyObject {
    /// Returns the delta applied to the chat's max-line count.
    ///
    /// Default: `-3`. Return `Int.min` to sentinel "force single line".
    /// Effective value is clamped to `>= 1` by ``fclAttachmentInputEffectiveLines(chatMax:delta:)``.
    /// - Parameter chatMaxLines: The chat input's configured maximum visible line count.
    func attachmentInputLineCountDelta(chatMaxLines: Int) -> Int
}

public extension FCLAttachmentInputDelegate {
    func attachmentInputLineCountDelta(chatMaxLines: Int) -> Int { -3 }
}

// MARK: - Line Count Clamp Helper

/// Computes the attachment preview's effective max visible line count.
///
/// Applies `delta` to `chatMax`, clamping the result to `>= 1`.
/// `delta == Int.min` is the sentinel for "force single line".
/// - Returns: Effective maximum visible line count. Always `>= 1`.
public func fclAttachmentInputEffectiveLines(chatMax: Int, delta: Int) -> Int {
    if delta == .min { return 1 }
    if chatMax <= 1 { return 1 }
    let candidate = chatMax + delta
    let clamped = candidate < 2 ? 2 : candidate
    return clamped <= 0 ? 1 : clamped
}
