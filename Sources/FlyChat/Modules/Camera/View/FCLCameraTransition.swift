#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLCameraTransitionCurves

/// Canonical curve constants for the camera open/close morph. Centralized so
/// the animator and the pulse overlay stay in lockstep.
enum FCLCameraTransitionCurves {
    /// Total morph duration for open and close animations. Tuned to a 0.32s
    /// feel that matches the system sheet presentation cadence so the camera
    /// morph stays in the same visual family as the picker presentation.
    static let morphDuration: TimeInterval = 0.32
    /// Cross-dissolve duration between camera and previewer. Defaults to
    /// PRD-08's 0.25s ease-in-out, in sympathy with scope 06's zoom-ramp
    /// (0.25s easeInOut) — see the spec follow-up notes.
    static let crossDissolveDuration: TimeInterval = 0.25
    /// Spring damping used to shape the open/close envelope.
    static let springDampingFraction: CGFloat = 0.86
    /// Single pulse-highlight duration on the source cell after close.
    static let pulseDuration: TimeInterval = 0.35
    /// Fraction of the close morph during which the snapshot fades out.
    /// With a 0.32s morph the snapshot begins fading at ~0.192s
    /// (`1 - 0.40 = 0.60` of the duration) and finishes at 0.32s.
    static let closeSnapshotFadeFraction: CGFloat = 0.40
}

// MARK: - FCLCameraTransition

/// Custom `UIViewControllerAnimatedTransitioning` driving the camera module's
/// open and close animations from a supplied source rect.
///
/// Open: morphs an empty rect at the gallery camera cell's window frame up to
/// the camera screen's full frame, cross-fading the camera view in as it
/// scales.
///
/// Close: captures a Metal-safe snapshot of the live camera preview via
/// `UIView.snapshotView(afterScreenUpdates:)` (required because
/// `AVCaptureVideoPreviewLayer` is GPU-backed — `drawHierarchy(in:)` would
/// return a black frame on modern devices), animates the snapshot from the
/// full-screen camera rect back to the source cell rect, and fades the
/// snapshot out over the final
/// ``FCLCameraTransitionCurves/closeSnapshotFadeFraction`` of the morph.
/// While the snapshot animates, the relay's `firePulse()` is invoked so the
/// source cell plays a single 0.35s ease-in-out pulse-highlight.
///
/// If the source cell is off-screen at close-time (`sourceFrame` is `nil` or
/// outside the window bounds), the close path collapses the snapshot to a
/// zero-sized rect at the screen center with a fade, mirroring the
/// chat-previewer off-screen rule in scope 18.
@MainActor
final class FCLCameraTransition: NSObject, UIViewControllerAnimatedTransitioning {
    /// `true` when presenting (cell → full-screen), `false` when dismissing.
    let isPresenting: Bool
    /// Relay supplying the source cell frame and coordinating the pulse.
    let sourceRelay: FCLCameraSourceRelay

    init(isPresenting: Bool, sourceRelay: FCLCameraSourceRelay) {
        self.isPresenting = isPresenting
        self.sourceRelay = sourceRelay
    }

    nonisolated func transitionDuration(
        using transitionContext: (any UIViewControllerContextTransitioning)?
    ) -> TimeInterval {
        FCLCameraTransitionCurves.morphDuration
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        if isPresenting {
            animateOpen(context: transitionContext)
        } else {
            animateClose(context: transitionContext)
        }
    }

    // MARK: - Open

    private func animateOpen(context: any UIViewControllerContextTransitioning) {
        let container = context.containerView
        guard let toVC = context.viewController(forKey: .to),
              let toView = context.view(forKey: .to) ?? toVC.view else {
            context.completeTransition(true)
            return
        }

        let finalFrame = context.finalFrame(for: toVC)
        toView.frame = finalFrame
        toView.layoutIfNeeded()
        container.addSubview(toView)

        let startFrame = resolvedSourceFrame(in: container)
        // Scale the camera view down to the source cell and fade in as it
        // expands to full screen. Keep a uniform transform so the camera
        // preview does not distort horizontally.
        let sx = max(startFrame.width / max(finalFrame.width, 1), 0.001)
        let sy = max(startFrame.height / max(finalFrame.height, 1), 0.001)
        let scale = min(sx, sy)
        let startCenter = CGPoint(x: startFrame.midX, y: startFrame.midY)
        let endCenter = CGPoint(x: finalFrame.midX, y: finalFrame.midY)

        toView.transform = CGAffineTransform(scaleX: scale, y: scale)
        toView.center = startCenter
        toView.alpha = 0

        let timing = UISpringTimingParameters(
            dampingRatio: FCLCameraTransitionCurves.springDampingFraction,
            initialVelocity: .zero
        )
        let animator = UIViewPropertyAnimator(
            duration: FCLCameraTransitionCurves.morphDuration,
            timingParameters: timing
        )
        animator.addAnimations {
            toView.transform = .identity
            toView.center = endCenter
            toView.alpha = 1
        }
        animator.addCompletion { _ in
            toView.transform = .identity
            toView.frame = finalFrame
            toView.alpha = 1
            context.completeTransition(!context.transitionWasCancelled)
        }
        animator.startAnimation()
    }

    // MARK: - Close

    private func animateClose(context: any UIViewControllerContextTransitioning) {
        let container = context.containerView
        guard let fromView = context.view(forKey: .from)
                ?? context.viewController(forKey: .from)?.view else {
            context.completeTransition(true)
            return
        }

        let fullRect = fromView.frame
        // Scope 08: `AVCaptureVideoPreviewLayer` is Metal-backed on modern
        // devices, so `UIView.drawHierarchy(in:afterScreenUpdates:false)`
        // returns a black frame. `UIView.snapshotView(afterScreenUpdates:)`
        // is documented to correctly capture GPU-backed content, including
        // the preview layer. We snapshot the full hosting view so overlay
        // chrome (top bar, shutter row) morphs with the preview content.
        // The session stays running until the parent router stops it in its
        // dismiss completion, so the snapshot captures a live frame.
        let snapshotView = makeSnapshotView(for: fromView, fallbackFrame: fullRect)
        snapshotView.frame = fullRect
        snapshotView.clipsToBounds = true
        container.addSubview(snapshotView)

        // Hide the real camera view immediately so only the snapshot morphs.
        fromView.isHidden = true

        let target = resolvedSourceFrame(in: container)
        let isOffScreen = !isFrameOnScreen(target, in: container)
        let endFrame: CGRect
        if isOffScreen {
            endFrame = CGRect(
                x: container.bounds.midX,
                y: container.bounds.midY,
                width: 0,
                height: 0
            )
        } else {
            endFrame = target
        }

        // Trigger the source-cell pulse in parallel with the snapshot morph
        // (only when the cell is actually on-screen to receive the pulse).
        if !isOffScreen {
            sourceRelay.firePulse()
        }

        let duration = FCLCameraTransitionCurves.morphDuration
        let timing = UISpringTimingParameters(
            dampingRatio: FCLCameraTransitionCurves.springDampingFraction,
            initialVelocity: .zero
        )
        let morphAnimator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: timing
        )
        morphAnimator.addAnimations {
            snapshotView.frame = endFrame
            snapshotView.layer.cornerRadius = min(endFrame.width, endFrame.height) * 0.04
        }

        // Fade out over the final `closeSnapshotFadeFraction` of the morph.
        let fadeFraction = FCLCameraTransitionCurves.closeSnapshotFadeFraction
        let fadeDuration = duration * TimeInterval(fadeFraction)
        let fadeDelay = duration - fadeDuration
        let fadeAnimator = UIViewPropertyAnimator(
            duration: fadeDuration,
            curve: .easeIn
        ) {
            snapshotView.alpha = 0
        }

        morphAnimator.addCompletion { _ in
            snapshotView.removeFromSuperview()
            fromView.removeFromSuperview()
            context.completeTransition(!context.transitionWasCancelled)
        }
        morphAnimator.startAnimation()
        fadeAnimator.startAnimation(afterDelay: fadeDelay)
    }

    // MARK: - Helpers

    /// Returns the best-known source frame in the container's coordinate
    /// space. Falls back to a bottom-center dot when no frame has been
    /// published (e.g. no picker ever presented).
    private func resolvedSourceFrame(in container: UIView) -> CGRect {
        if let frame = sourceRelay.sourceFrame,
           frame.width > 0, frame.height > 0 {
            return frame
        }
        return CGRect(
            x: container.bounds.midX - 20,
            y: container.bounds.maxY - 80,
            width: 40,
            height: 40
        )
    }

    /// Returns `true` when `frame` is at least partially inside the container
    /// bounds with non-zero size. Used to pick the center-collapse fallback.
    private func isFrameOnScreen(_ frame: CGRect, in container: UIView) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        return container.bounds.intersects(frame)
    }

    /// Produces a Metal-safe snapshot view of the live camera UI. Prefers
    /// `UIView.snapshotView(afterScreenUpdates:)` because
    /// `AVCaptureVideoPreviewLayer` renders via Metal on modern devices and
    /// cannot be captured with `drawHierarchy` or `CALayer.render(in:)`.
    /// Falls back to a black placeholder when snapshotView returns `nil`
    /// (e.g. the view is not yet onscreen).
    private func makeSnapshotView(for view: UIView, fallbackFrame: CGRect) -> UIView {
        if let snap = view.snapshotView(afterScreenUpdates: false) {
            return snap
        }
        let placeholder = UIView(frame: fallbackFrame)
        placeholder.backgroundColor = .black
        return placeholder
    }
}

// MARK: - FCLCameraTransitioningDelegate

/// Binds the camera router's presented hosting controller to
/// ``FCLCameraTransition`` for both open and close.
@MainActor
final class FCLCameraTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    let sourceRelay: FCLCameraSourceRelay

    init(sourceRelay: FCLCameraSourceRelay) {
        self.sourceRelay = sourceRelay
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        FCLCameraTransition(isPresenting: true, sourceRelay: sourceRelay)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        FCLCameraTransition(isPresenting: false, sourceRelay: sourceRelay)
    }
}

// MARK: - Previews

#if DEBUG
/// SwiftUI host that drives ``FCLCameraTransition`` end-to-end. Tap the
/// pseudo-cell to open a mock camera controller and close it again to see
/// the morph and the pulse tick travel through the relay.
struct FCLCameraTransition_Previews: PreviewProvider {
    static var previews: some View {
        FCLCameraTransitionPreviewHost()
            .previewDisplayName("Camera Morph Host")
    }
}

@MainActor
private struct FCLCameraTransitionPreviewHost: View {
    @StateObject private var relay = FCLCameraSourceRelay()
    @State private var cellFrame: CGRect = .zero
    @State private var pulseScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            FCLPalette.systemBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("Camera transition preview")
                    .font(.headline)
                Text("Relay pulse tick: \(relay.pulseTick)")
                    .font(.caption)
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseScale)
                    .overlay(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { cellFrame = proxy.frame(in: .global) }
                                .onChange(of: proxy.frame(in: .global)) { _, new in
                                    cellFrame = new
                                    relay.sourceFrame = new
                                }
                        }
                    )
                    .onAppear { relay.sourceFrame = cellFrame }
            }
            .padding()
        }
        .onChange(of: relay.pulseTick) { _, _ in
            withAnimation(.easeInOut(duration: FCLCameraTransitionCurves.pulseDuration / 2)) {
                pulseScale = 1.08
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + FCLCameraTransitionCurves.pulseDuration / 2
            ) {
                withAnimation(.easeInOut(duration: FCLCameraTransitionCurves.pulseDuration / 2)) {
                    pulseScale = 1
                }
            }
        }
    }
}
#endif
#endif
