#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLCameraSourceRelay

/// Publishes the attachment-picker camera cell's on-screen frame (in window
/// coordinates) and coordinates the pulse-highlight played on the cell when
/// the camera closes back to it.
///
/// Mirrors the role of ``FCLPickerSourceRelay`` for the standalone Camera
/// module. The gallery camera cell writes its frame here on appear and on
/// scroll; the custom camera transition (``FCLCameraTransition``) reads the
/// frame at the start of every `animateTransition(using:)` so rotation or
/// scrolling mid-transition is handled without stale geometry.
///
/// The relay also carries a lightweight `isTransitioning` flag. When set to
/// `true`, the camera screen defers `AVCaptureSession` teardown (normally
/// invoked from `onDisappear`) so the cross-dissolve between camera and the
/// pre-send previewer does not flash a black frame. The host flips the flag
/// back to `false` once the transition completes.
///
/// SwiftUI view structs cannot be `AnyObject`; this small reference-type relay
/// is held by the presenting host via `@State`/`@StateObject` so its identity
/// survives body re-evaluations.
@MainActor
public final class FCLCameraSourceRelay: ObservableObject {
    /// Gallery camera cell frame in the key window's coordinate space, or
    /// `nil` when the cell is not currently visible (scrolled off-screen or
    /// the picker is not presented).
    @Published public var sourceFrame: CGRect?

    /// `true` while an open/close/cross-dissolve is in flight. The camera view
    /// consults this flag in its `onDisappear` path to keep the capture
    /// session alive across cross-dissolves.
    @Published public var isTransitioning: Bool = false

    /// Incrementing tick used to trigger the pulse-highlight overlay on the
    /// camera cell. The cell observes this value and, when it increments,
    /// runs a single 0.35s ease-in-out pulse.
    @Published public var pulseTick: Int = 0

    public init() {}

    /// Triggers a single pulse-highlight cycle on the source cell.
    public func firePulse() {
        pulseTick &+= 1
    }
}
#endif
