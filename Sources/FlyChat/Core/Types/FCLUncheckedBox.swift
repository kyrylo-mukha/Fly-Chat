import Foundation

/// Internal helper that transfers a non-`Sendable` value across actor
/// boundaries when the caller holds a documented invariant that the value is
/// not aliased at the hand-off.
///
/// FlyChat uses this only where Apple's Objective-C-rooted API surface keeps
/// a type from being `Sendable` even though the project's concurrency model
/// guarantees serial access (e.g., `AVCaptureDevice` handed off from the
/// camera session queue to `FCLCameraZoomController`'s executor). Each use
/// site must document the invariant that makes the transfer safe.
struct FCLUncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
