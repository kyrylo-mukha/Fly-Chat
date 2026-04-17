#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLPickerSourceRelay

/// Publishes the attach button's on-screen frame (in window coordinates) and the
/// attachment picker sheet's top-edge rect to the SwiftUI morph overlay that
/// animates the pill between them.
///
/// The chat input bar writes the button's frame here whenever the button's layout
/// changes. The sheet content writes its top-edge rect here via a transparent
/// `GeometryReader` so the overlay's final position stays exact across detents
/// (`.medium` / `.large`), rotation, and dynamic type.
///
/// The relay also carries a lightweight `dismissHandler` slot that the input bar
/// wires up during presentation. Every dismiss trigger — close button inside the
/// sheet plus Voice Control escape — routes through this handler. The native
/// `.sheet()` already funnels tap-outside and swipe-down through the wrapped
/// `isPresented` binding on the input bar, so the handler is only needed by
/// consumers inside the sheet content (`FCLPickerCloseButton`).
///
/// SwiftUI view structs cannot be `AnyObject`; this small reference-type relay is
/// held by the chat input bar via `@State` so its identity survives body
/// re-evaluations.
@MainActor
final class FCLPickerSourceRelay {
    /// Attach button frame in the key window's coordinate space, or `nil` when the
    /// button has not published a frame yet (e.g. during initial layout).
    var sourceFrame: CGRect?

    /// Sheet's top-edge rect in window coordinates, captured by a transparent
    /// `GeometryReader` mounted at the top of the sheet content. `nil` before
    /// the sheet has rendered its first frame.
    var sheetTopFrame: CGRect?

    /// Hook invoked to dismiss the picker. The input bar installs this when it
    /// presents the sheet; it flips the wrapped `isPresented` binding back to
    /// `false`, which triggers the collapse morph inside the binding's setter
    /// before SwiftUI runs the native sheet slide-down in parallel.
    var dismissHandler: (() -> Void)?

    /// Routes a dismiss intent through the registered handler. No-op when the
    /// picker is not presented.
    func requestDismiss() {
        dismissHandler?()
    }
}

// MARK: - FCLPickerTransitionCurves

/// Canonical curve constants used by the picker morph. Centralized here so the
/// SwiftUI overlay and any future visual tests stay in lockstep. Values match
/// the pre-overhaul animator: 0.32 s morph with a `response: 0.38`,
/// `dampingFraction: 0.86` spring envelope.
enum FCLPickerTransitionCurves {
    /// Total morph duration used by the pill overlay.
    static let morphDuration: TimeInterval = 0.32
    /// Spring response used to shape the morph envelope.
    static let springResponse: CGFloat = 0.38
    /// Spring damping fraction used to shape the morph envelope.
    static let springDampingFraction: CGFloat = 0.86
}
#endif
