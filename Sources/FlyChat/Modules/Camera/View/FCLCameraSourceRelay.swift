#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLCameraSourceRelay

/// Reference-type relay that publishes the attachment-picker camera cell's
/// on-screen frame and coordinates the open/close morph transition and
/// pulse-highlight for the Camera module.
@MainActor
public final class FCLCameraSourceRelay: ObservableObject {
    /// Gallery camera cell frame in the key window's coordinate space, or
    /// `nil` when the cell is not visible.
    @Published public var sourceFrame: CGRect?

    /// `true` while an open/close/cross-dissolve is in flight.
    /// The camera view's `onDisappear` path checks this to keep the session
    /// alive across cross-dissolves.
    @Published public var isTransitioning: Bool = false

    /// Incrementing tick that triggers a single pulse-highlight on the source cell.
    @Published public var pulseTick: Int = 0

    /// Mirrors the SwiftUI `.interactiveDismissDisabled(_:)` gate onto the
    /// `UIHostingController.isModalInPresentation` so UIKit swipe-down respects
    /// the same confirmation contract as the SwiftUI gate.
    @Published public var isModalInPresentation: Bool = false

    /// Weak reference to the preview view for Metal-safe snapshot capture
    /// (`snapshotView(afterScreenUpdates:)`) during the close transition.
    public weak var previewView: UIView?

    public init() {}

    public func firePulse() {
        pulseTick &+= 1
    }
}
#endif
