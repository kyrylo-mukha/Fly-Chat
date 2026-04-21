#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLCameraTransitionCurves

/// Canonical timing constants for the camera open/close morph.
/// Centralized so the animator and the pulse overlay stay in lockstep.
enum FCLCameraTransitionCurves {
    static let morphDuration: TimeInterval = 0.32
    static let crossDissolveDuration: TimeInterval = 0.25
    static let springDampingFraction: CGFloat = 0.86
    static let pulseDuration: TimeInterval = 0.35
    /// Fraction of the close morph over which the snapshot fades out
    /// (applied at the tail of the animation).
    static let closeSnapshotFadeFraction: CGFloat = 0.40
}

// MARK: - FCLCameraTransition

/// `UIViewControllerAnimatedTransitioning` driving the camera module's open
/// and close morph from the gallery camera cell's source rect.
/// Close path uses `snapshotView(afterScreenUpdates:)` because
/// `AVCaptureVideoPreviewLayer` is Metal-backed and cannot be captured with
/// `drawHierarchy(in:afterScreenUpdates:)`.
@MainActor
final class FCLCameraTransition: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresenting: Bool
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
        // `AVCaptureVideoPreviewLayer` is Metal-backed; `drawHierarchy(in:)` returns
        // black. `snapshotView(afterScreenUpdates:)` correctly captures GPU content.
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

    private func isFrameOnScreen(_ frame: CGRect, in container: UIView) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        return container.bounds.intersects(frame)
    }

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
