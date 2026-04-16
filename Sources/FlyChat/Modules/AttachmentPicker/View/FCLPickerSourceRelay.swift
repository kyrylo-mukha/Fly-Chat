#if canImport(UIKit)
import UIKit

// MARK: - FCLPickerSourceRelay

/// Publishes the attach button's on-screen frame (in window coordinates) to any
/// consumer that needs an expand/collapse anchor for the attachment picker.
///
/// The chat input bar writes the button's frame here whenever the button's layout
/// changes. The custom picker transition (``FCLPickerTransitionAnimator``) reads
/// the frame at the start of each ``animateTransition(using:)`` pass so rotation
/// mid-transition is handled naturally — values are never cached pre-rotation.
///
/// The relay also carries a lightweight `dismissHandler` slot that the picker host
/// wires up during presentation. Every dismiss trigger — tap-outside, swipe-down
/// finish, swipe-down cancel, close button, Voice Control escape — routes through
/// this handler so the single animator drives them all. Scope 11's close button
/// plugs in without changes by invoking `requestDismiss()`.
///
/// SwiftUI view structs cannot be `AnyObject`; this small reference-type relay is
/// held by the chat screen via `@State` so its identity survives body re-evaluations.
@MainActor
final class FCLPickerSourceRelay {
    /// Attach button frame in the key window's coordinate space, or `nil` when the
    /// button has not published a frame yet (e.g. during initial layout).
    var sourceFrame: CGRect?

    /// Hook invoked to dismiss the picker through the shared morph animator.
    ///
    /// Consumers (tap-outside overlay, pan gesture, close button, accessibility
    /// escape) call ``requestDismiss()`` instead of touching SwiftUI state
    /// directly, so every dismiss path goes through the same animator.
    var dismissHandler: (() -> Void)?

    /// Routes a dismiss intent through the registered handler. No-op when the
    /// picker is not presented.
    func requestDismiss() {
        dismissHandler?()
    }
}

// MARK: - FCLPickerTransitionCurves

/// Canonical curve constants used by the picker morph. Centralized here so the
/// animator, the interactive pan controller, and any future visual tests stay in
/// lockstep. Values match PRD 10: 0.32 s morph with a `response: 0.38`,
/// `dampingFraction: 0.86` spring envelope.
enum FCLPickerTransitionCurves {
    /// Total morph duration used by the non-interactive animator.
    static let morphDuration: TimeInterval = 0.32
    /// Spring response used to shape the morph envelope.
    static let springResponse: CGFloat = 0.38
    /// Spring damping fraction used to shape the morph envelope.
    static let springDampingFraction: CGFloat = 0.86
    /// Time given for the keyboard to hide before a keyboard-visible dismiss
    /// begins its morph. Slightly longer than the 0.25 s system keyboard curve
    /// floor to keep the keyboard visually gone before the picker starts moving.
    static let keyboardHideLead: TimeInterval = 0.15
    /// Progress threshold used by the swipe-down interactive dismiss. Releases
    /// below this fraction cancel; at or above this fraction finish.
    static let interactiveCancelThreshold: CGFloat = 0.33
}

// MARK: - UISpringTimingParameters helper

/// Builds a `UISpringTimingParameters` instance from SwiftUI-style `(response,
/// dampingFraction)` pair.
///
/// `UISpringTimingParameters(dampingRatio:initialVelocity:)` only accepts a
/// damping ratio; it does not expose the natural period ("response") that
/// SwiftUI's `.spring(response:dampingFraction:)` and the rest of FlyChat's
/// visual language use. The four-argument `(mass:stiffness:damping:...)`
/// overload does, so we convert `(response, dampingFraction)` to
/// `(mass, stiffness, damping)` via the standard formulas:
///
/// ```
/// mass      = 1
/// stiffness = (2 * π / response)^2 * mass
/// damping   = 4 * π * dampingFraction * mass / response
/// ```
///
/// The damping ratio that UIKit derives from the computed `damping`,
/// `stiffness`, and `mass` — `damping / (2 * sqrt(stiffness * mass))` —
/// simplifies back to `dampingFraction`, so the spring envelope lands on the
/// intended feel. See `UISpringTimingParameters.init(mass:stiffness:damping:initialVelocity:)`.
@MainActor
func springTimingParameters(
    response: CGFloat,
    dampingFraction: CGFloat,
    initialVelocity: CGVector = .zero
) -> UISpringTimingParameters {
    let mass: CGFloat = 1
    let stiffness = pow(2 * .pi / response, 2) * mass
    let damping = 4 * .pi * dampingFraction * mass / response
    return UISpringTimingParameters(
        mass: mass,
        stiffness: stiffness,
        damping: damping,
        initialVelocity: initialVelocity
    )
}
#endif
