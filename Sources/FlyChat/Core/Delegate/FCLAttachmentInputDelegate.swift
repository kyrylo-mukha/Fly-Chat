import Foundation

// MARK: - FCLAttachmentInputDelegate

/// Delegate protocol that lets the host app tune the multi-line behavior of the
/// attachment preview's caption field relative to the chat's main input.
///
/// The attachment preview's text field caps its visible line count at
/// `chatMaxLines + attachmentInputLineCountDelta(chatMaxLines:)`. A negative
/// delta produces a shorter field than the chat (typical), a positive delta a
/// taller field. Returning `Int.min` forces a single line regardless of
/// `chatMaxLines`.
///
/// The effective value is always clamped to a safe range by
/// ``fclAttachmentInputEffectiveLines(chatMax:delta:)``.
@MainActor
public protocol FCLAttachmentInputDelegate: AnyObject {
    /// Returns the delta applied to the chat's max-line count.
    ///
    /// The default implementation returns `-3`. Implementers may return smaller
    /// (more negative) or explicit values. The preview clamps the effective
    /// maximum as follows:
    /// - `effectiveMax = chatMaxLines + delta`
    /// - if `effectiveMax < 2`, the preview uses `2` unless the delegate returns
    ///   the sentinel `Int.min` to mean "force single line".
    /// - if `chatMaxLines == 1`, the effective max is `1`.
    func attachmentInputLineCountDelta(chatMaxLines: Int) -> Int
}

public extension FCLAttachmentInputDelegate {
    func attachmentInputLineCountDelta(chatMaxLines: Int) -> Int { -3 }
}

// MARK: - Line Count Clamp Helper

/// Pure helper that computes the attachment preview's effective max visible
/// line count from the chat's max line count and a delegate-supplied delta.
///
/// Rules, evaluated in order:
/// 1. If `delta == Int.min`, the result is `1` (sentinel for "single line").
/// 2. If `chatMax <= 1`, the result is `1` (overrides everything else).
/// 3. Otherwise `candidate = chatMax + delta`. If `candidate < 2`, the result is
///    `2`.
/// 4. As a final safeguard, any non-positive result falls back to `1`.
///
/// - Parameters:
///   - chatMax: The chat input's configured maximum visible line count.
///   - delta: The delegate-supplied delta applied to `chatMax`.
/// - Returns: The effective maximum visible line count for the attachment
///   preview's caption field. Always `>= 1`.
public func fclAttachmentInputEffectiveLines(chatMax: Int, delta: Int) -> Int {
    if delta == .min { return 1 }
    if chatMax <= 1 { return 1 }
    let candidate = chatMax + delta
    let clamped = candidate < 2 ? 2 : candidate
    return clamped <= 0 ? 1 : clamped
}
