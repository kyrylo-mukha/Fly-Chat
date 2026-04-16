#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLPickerTransitionAnimator

/// Custom `UIViewControllerAnimatedTransitioning` that morphs the chat attach
/// button's on-screen rect into the picker's full sheet frame (and back).
///
/// The morph uses a snapshot of the picker's top ~40 pt as a "pill" that scales
/// and translates between the button rect and the sheet top. The rest of the
/// picker body cross-fades on top once the pill reaches its final position.
///
/// Why a pill snapshot rather than a full-screen snapshot: the picker's content
/// area is tall and rectangular. A full-screen snapshot stretched from a
/// ~36×36 pt attach button would distort aspect ratio severely — text in the
/// tab bar would squish horizontally while scaling up. The top ~40 pt strip is
/// effectively a pill shape whose aspect ratio is close enough to the attach
/// button's bounding rect that the scale looks natural. It also keeps the
/// snapshot cheap (one narrow view vs. the full sheet).
///
/// The animator re-reads the target frame at the start of every
/// `animateTransition(using:)` call, so mid-transition rotation is handled
/// without stale cached geometry.
@MainActor
final class FCLPickerTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    /// `true` when presenting (button → sheet), `false` when dismissing (sheet → button).
    let isPresenting: Bool
    /// Relay publishing the attach button's current window-space frame.
    let sourceRelay: FCLPickerSourceRelay
    /// Optional completion hook invoked with the final transition outcome
    /// (`true` when completed, `false` when cancelled). Used by the
    /// transitioning delegate to flip the SwiftUI `isPresented` binding on
    /// dismiss finish.
    var onCompletion: ((Bool) -> Void)?
    /// Height of the snapshot pill taken from the picker's top edge.
    private let pillHeight: CGFloat = 40

    init(isPresenting: Bool, sourceRelay: FCLPickerSourceRelay) {
        self.isPresenting = isPresenting
        self.sourceRelay = sourceRelay
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        FCLPickerTransitionCurves.morphDuration
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView

        // Always re-read the attach button frame here so rotation mid-transition
        // picks up the latest geometry. Fall back to a sensible off-screen rect
        // when no frame has been published yet.
        let buttonFrame: CGRect = {
            if let frame = sourceRelay.sourceFrame, frame.width > 0, frame.height > 0 {
                return frame
            }
            return CGRect(
                x: containerView.bounds.midX - 18,
                y: containerView.bounds.maxY - 60,
                width: 36,
                height: 36
            )
        }()

        if isPresenting {
            animatePresent(context: transitionContext, buttonFrame: buttonFrame)
        } else {
            animateDismiss(context: transitionContext, buttonFrame: buttonFrame)
        }
    }

    // MARK: Present

    private func animatePresent(
        context: any UIViewControllerContextTransitioning,
        buttonFrame: CGRect
    ) {
        let container = context.containerView
        guard let toView = context.view(forKey: .to) ?? context.viewController(forKey: .to)?.view else {
            context.completeTransition(true)
            return
        }

        let finalFrame = context.finalFrame(for: context.viewController(forKey: .to)!)
        toView.frame = finalFrame
        toView.layoutIfNeeded()
        container.addSubview(toView)

        // Pill snapshot of the picker's top strip.
        let pillRect = CGRect(
            x: finalFrame.minX,
            y: finalFrame.minY,
            width: finalFrame.width,
            height: pillHeight
        )
        let snapshot = toView.resizableSnapshotView(
            from: toView.convert(pillRect, from: container),
            afterScreenUpdates: true,
            withCapInsets: .zero
        ) ?? UIView()
        snapshot.frame = buttonFrame
        snapshot.layer.cornerRadius = min(buttonFrame.width, buttonFrame.height) / 2
        snapshot.clipsToBounds = true
        container.addSubview(snapshot)

        toView.alpha = 0

        // Use the shared (response, dampingFraction) → (mass, stiffness, damping)
        // converter so both animator call sites share a single source of truth
        // and land on the exact spring envelope the spec dictates (response
        // 0.38, dampingFraction 0.86) — the `dampingRatio:` overload only
        // accepts damping and forces UIKit to pick its own natural period.
        let timing = springTimingParameters(
            response: FCLPickerTransitionCurves.springResponse,
            dampingFraction: FCLPickerTransitionCurves.springDampingFraction
        )
        let animator = UIViewPropertyAnimator(
            duration: FCLPickerTransitionCurves.morphDuration,
            timingParameters: timing
        )
        animator.addAnimations {
            snapshot.frame = pillRect
            snapshot.layer.cornerRadius = 0
        }
        // Fade the real picker in during the second half so the pill hands off
        // cleanly once it has reached its destination shape.
        let fadeAnimator = UIViewPropertyAnimator(
            duration: FCLPickerTransitionCurves.morphDuration * 0.6,
            curve: .easeOut
        ) {
            toView.alpha = 1
        }
        animator.addCompletion { _ in
            snapshot.removeFromSuperview()
            context.completeTransition(!context.transitionWasCancelled)
        }
        animator.startAnimation()
        fadeAnimator.startAnimation(afterDelay: FCLPickerTransitionCurves.morphDuration * 0.35)
    }

    // MARK: Dismiss

    private func animateDismiss(
        context: any UIViewControllerContextTransitioning,
        buttonFrame: CGRect
    ) {
        let container = context.containerView
        guard let fromView = context.view(forKey: .from) ?? context.viewController(forKey: .from)?.view else {
            context.completeTransition(true)
            return
        }

        let startFrame = fromView.frame
        let pillRect = CGRect(
            x: startFrame.minX,
            y: startFrame.minY,
            width: startFrame.width,
            height: pillHeight
        )
        let snapshot = fromView.resizableSnapshotView(
            from: fromView.convert(pillRect, from: container),
            afterScreenUpdates: false,
            withCapInsets: .zero
        ) ?? UIView()
        snapshot.frame = pillRect
        snapshot.layer.cornerRadius = 0
        snapshot.clipsToBounds = true
        container.addSubview(snapshot)

        // Same converter as in `animatePresent` to keep the dismiss spring
        // envelope aligned with the present spring envelope.
        let timing = springTimingParameters(
            response: FCLPickerTransitionCurves.springResponse,
            dampingFraction: FCLPickerTransitionCurves.springDampingFraction
        )
        let animator = UIViewPropertyAnimator(
            duration: FCLPickerTransitionCurves.morphDuration,
            timingParameters: timing
        )
        animator.addAnimations {
            fromView.alpha = 0
            snapshot.frame = buttonFrame
            snapshot.layer.cornerRadius = min(buttonFrame.width, buttonFrame.height) / 2
        }
        let completionHook = onCompletion
        animator.addCompletion { _ in
            snapshot.removeFromSuperview()
            fromView.removeFromSuperview()
            let didComplete = !context.transitionWasCancelled
            context.completeTransition(didComplete)
            completionHook?(didComplete)
        }
        animator.startAnimation()
    }
}

// MARK: - FCLPickerPanDelegate

/// Gesture delegate for the picker's dismiss pan.
///
/// Split out from ``FCLPickerPresentation/Coordinator`` because
/// `UIGestureRecognizerDelegate` is `@MainActor`-annotated in the iOS SDK, and
/// conforming the nested `Coordinator` (which is not `@MainActor`-isolated
/// because it must be capturable by `@Sendable` `NotificationCenter` closures)
/// would force the class onto the main actor and break the `deinit`'s access
/// to the non-Sendable observer array. Hosting the delegate in its own
/// `@MainActor` helper keeps the isolation boundaries clean.
@MainActor
final class FCLPickerPanDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var host: UIViewController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only allow the dismiss pan to begin inside the top ~56 pt strip of
        // the sheet, and only when the user's motion is predominantly downward.
        // Rejecting here (instead of toggling `isEnabled` in the `.began`
        // handler as the previous implementation did) lets inner gesture
        // recognizers — the gallery collection view's own pan in particular —
        // pick up the touch cleanly.
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let view = host?.view else { return true }
        let start = pan.location(in: view)
        let translation = pan.translation(in: view)
        let verticalDominant = abs(translation.y) >= abs(translation.x)
        let downward = translation.y >= 0
        return start.y <= 56 && verticalDominant && downward
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Permit inner scroll views and tap recognizers to fire alongside the
        // dismiss pan when both qualify. Without this, the dismiss pan's
        // exclusivity starves the gallery collection view of its own pan.
        true
    }
}

// MARK: - FCLPickerInteractiveDismiss

/// Percent-driven interactive controller for the swipe-down dismiss path.
///
/// Progress is computed as `translation.y / sheetHeight`. Releases below
/// ``FCLPickerTransitionCurves/interactiveCancelThreshold`` cancel the
/// dismissal (the sheet snaps back); releases at or above the threshold
/// finish it through the same morph animator used by every other dismiss
/// trigger.
@MainActor
final class FCLPickerInteractiveDismiss: UIPercentDrivenInteractiveTransition {
    /// `true` while a pan is in flight — the transitioning delegate consults
    /// this to decide whether to return `self` from
    /// `interactionControllerForDismissal(using:)`.
    private(set) var isActive: Bool = false

    func begin() {
        isActive = true
    }

    func end(shouldFinish: Bool) {
        if shouldFinish {
            finish()
        } else {
            cancel()
        }
        isActive = false
    }
}

// MARK: - FCLPickerTransitioningDelegate

/// Binds the custom animator + interactive controller to the presented picker
/// controller. A single instance is retained for the lifetime of the picker
/// presentation.
@MainActor
final class FCLPickerTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    let sourceRelay: FCLPickerSourceRelay
    let interactiveDismiss = FCLPickerInteractiveDismiss()
    /// Invoked by the animator's completion on dismiss so the SwiftUI binding
    /// can be flipped back to `false` without a separate observation channel.
    var onDismissCompleted: (() -> Void)?

    init(sourceRelay: FCLPickerSourceRelay) {
        self.sourceRelay = sourceRelay
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        FCLPickerTransitionAnimator(isPresenting: true, sourceRelay: sourceRelay)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        let animator = FCLPickerTransitionAnimator(isPresenting: false, sourceRelay: sourceRelay)
        animator.onCompletion = { [weak self] completed in
            if completed { self?.onDismissCompleted?() }
        }
        return animator
    }

    func interactionControllerForDismissal(
        using animator: any UIViewControllerAnimatedTransitioning
    ) -> (any UIViewControllerInteractiveTransitioning)? {
        interactiveDismiss.isActive ? interactiveDismiss : nil
    }

    // Supplying a presentation controller is required for `.custom`
    // modalPresentationStyle to lay the presented view out correctly. Without
    // this, UIKit inherits the frame from the presenting view controller —
    // which is the 0 × 0 SwiftUI bridge VC — and the animator receives a
    // zero-sized `finalFrame`, leaving the picker invisible.
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        FCLPickerPresentationController(
            presentedViewController: presented,
            presenting: presenting,
            sourceRelay: sourceRelay
        )
    }
}

// MARK: - FCLPickerPresentationController

/// Presentation controller that renders the picker as a half-sheet anchored to
/// the bottom of the container, matching the pre-overhaul `.presentationDetents`
/// look while keeping the custom `FCLPickerTransitionAnimator` for the open /
/// close morph.
///
/// Layout:
/// - The presented view fills the container horizontally and extends from the
///   bottom up to `topInset` (safe-area top + a ~10 pt peek, minimum 54 pt).
///   This matches the `.large` detent of `UISheetPresentationController`.
/// - Top corners are rounded at 16 pt so the sheet reads as a modal card.
/// - A translucent dim backdrop sits behind the sheet; the strip above the
///   sheet and the sides remain clear so the morph animator can still capture
///   the top 40 pt of the presented view as its pill snapshot.
///
/// The dim view also catches tap-outside touches and routes them through
/// ``FCLPickerSourceRelay/requestDismiss()`` so every dismiss path — tap-outside,
/// swipe-down, close button, accessibility escape — funnels through the same
/// morph animator and keyboard-hide sequencing.
@MainActor
final class FCLPickerPresentationController: UIPresentationController {
    /// Relay routing dismiss intents back through the shared morph animator.
    /// Retained so the tap recognizer's target can invoke `requestDismiss()`
    /// without crossing isolation boundaries.
    private let sourceRelay: FCLPickerSourceRelay

    /// Translucent backdrop installed as the container view's first subview so
    /// UIKit layers the presented view on top of it. The dim remains visible
    /// in the strip above the sheet (between the top safe area and the sheet's
    /// top edge) and catches tap-outside touches that would otherwise not have
    /// a receiver.
    private var dimView: UIView?

    /// Minimum gap reserved between the top of the container and the top of
    /// the sheet. Matches the visual peek that `.large` detent provides.
    private let topInsetFallback: CGFloat = 54

    init(
        presentedViewController: UIViewController,
        presenting presentingViewController: UIViewController?,
        sourceRelay: FCLPickerSourceRelay
    ) {
        self.sourceRelay = sourceRelay
        super.init(
            presentedViewController: presentedViewController,
            presenting: presentingViewController
        )
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let bounds = container.bounds
        let safeTop = container.safeAreaInsets.top
        // Leave a peek at the top so the sheet reads as a modal card, not a
        // full-screen takeover. Use the larger of the safe-area-aware offset
        // and a hard fallback so the peek is preserved even on devices /
        // preview hosts that report zero safe-area insets.
        let topInset = max(safeTop + 10, topInsetFallback)
        return CGRect(
            x: 0,
            y: topInset,
            width: bounds.width,
            height: bounds.height - topInset
        )
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
        dimView?.frame = containerView?.bounds ?? .zero
    }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        guard let containerView else { return }

        // Dim backdrop — behind the presented view so it does not obstruct the
        // morph pill snapshot. Fades from 0 → full alpha alongside the morph.
        let dim = UIView(frame: containerView.bounds)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        dim.isUserInteractionEnabled = true
        dim.alpha = 0
        dim.accessibilityIdentifier = "FCLPickerPresentationDim"
        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDimTap(_:))
        )
        tap.cancelsTouchesInView = false
        dim.addGestureRecognizer(tap)
        containerView.insertSubview(dim, at: 0)
        dimView = dim

        // Round the top corners to match the `.presentationDetents` look. The
        // bottom corners stay square — the sheet sits flush against the
        // bottom edge of the container.
        if let presentedView {
            presentedView.layer.cornerRadius = 16
            presentedView.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner
            ]
            presentedView.layer.masksToBounds = true
        }

        if let coordinator = presentedViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.dimView?.alpha = 1
            })
        } else {
            dim.alpha = 1
        }
    }

    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()
        guard let coordinator = presentedViewController.transitionCoordinator else {
            dimView?.alpha = 0
            return
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.dimView?.alpha = 0
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        if completed {
            dimView?.removeFromSuperview()
            dimView = nil
        } else {
            dimView?.alpha = 1
        }
    }

    @objc private func handleDimTap(_ recognizer: UITapGestureRecognizer) {
        sourceRelay.requestDismiss()
    }
}

// MARK: - FCLPickerPresentation

/// SwiftUI bridge that presents the picker content inside a transparent host
/// controller using the custom morph transition.
///
/// Mirrors the role of ``FCLTransparentFullScreenCover`` but swaps UIKit's
/// default cross-dissolve for the shared ``FCLPickerTransitionAnimator``. Every
/// dismiss trigger routes through ``FCLPickerSourceRelay/requestDismiss()``,
/// which flips `isPresented` back to `false` and lets the transitioning
/// delegate drive the collapse.
struct FCLPickerPresentation<CoverContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let sourceRelay: FCLPickerSourceRelay
    let content: () -> CoverContent

    // `@unchecked Sendable` is required so the `Coordinator` can be captured
    // inside the `@Sendable` closures passed to
    // `NotificationCenter.addObserver(forName:object:queue:using:)`. The
    // invariant: every access to Coordinator state happens on the main actor —
    // `makeCoordinator` / `updateUIViewController` are @MainActor by virtue of
    // `UIViewControllerRepresentable`, `handlePan` is explicitly @MainActor,
    // the notification callbacks run on `.main` and funnel through
    // `MainActor.assumeIsolated`, and `deinit` touches only
    // `NotificationCenter.removeObserver(_:)` which is thread-safe.
    final class Coordinator: NSObject, @unchecked Sendable {
        weak var ownedHost: UIViewController?
        var transitioningDelegate: FCLPickerTransitioningDelegate?
        var panGesture: UIPanGestureRecognizer?
        var panDelegate: FCLPickerPanDelegate?
        var keyboardIsVisible: Bool = false
        var keyboardObservers: [NSObjectProtocol] = []

        deinit {
            for observer in keyboardObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // `handlePan(_:)` must live on the primary class declaration: extensions of
        // classes from a generic context (`FCLPickerPresentation<CoverContent>`) cannot
        // contain `@objc` members, and `UIPanGestureRecognizer`'s target-action API
        // requires Obj-C exposure.
        @MainActor
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let host = ownedHost,
                  let view = host.view,
                  let transitioning = transitioningDelegate else { return }
            let interactive = transitioning.interactiveDismiss
            let translationY = gesture.translation(in: view).y
            let height = max(view.bounds.height, 1)
            let progress = max(0, min(1, translationY / height))

            switch gesture.state {
            case .began:
                // `FCLPickerPanDelegate.shouldBegin` already gated the start
                // location to the top pill region. Flip the interactive
                // controller on **before** routing dismiss through the relay —
                // the relay's handler triggers the SwiftUI binding flip that
                // re-enters `updateUIViewController`'s else branch to call
                // `host.dismiss(animated: true)`. When UIKit then asks the
                // transitioning delegate for an interaction controller,
                // `interactiveDismiss.isActive` must already be `true` so the
                // percent-driven controller is returned; otherwise the
                // swipe-down dismiss would fall back to a non-interactive
                // morph and ignore the user's drag progress.
                interactive.begin()
                // Route through the relay so the keyboard-hide sequencing
                // (0.15 s lead) runs just like the close button and
                // accessibility escape paths. Any other dismiss path (tap,
                // close, escape) already uses the relay; routing swipe-down
                // the same way keeps all four triggers behaviorally aligned.
                transitioning.sourceRelay.requestDismiss()
            case .changed:
                guard interactive.isActive else { return }
                interactive.update(progress)
            case .ended, .cancelled, .failed:
                guard interactive.isActive else { return }
                let velocity = gesture.velocity(in: view).y
                let shouldFinish = progress >= FCLPickerTransitionCurves.interactiveCancelThreshold
                    || velocity > 800
                interactive.end(shouldFinish: shouldFinish)
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        let show = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                coordinator.keyboardIsVisible = true
            }
        }
        let hide = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                coordinator.keyboardIsVisible = false
            }
        }
        coordinator.keyboardObservers = [show, hide]
        return coordinator
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented {
            if let host = context.coordinator.ownedHost, host.presentingViewController != nil {
                (host as? UIHostingController<CoverContent>)?.rootView = content()
                return
            }
            guard uiViewController.presentedViewController == nil else { return }

            let host = UIHostingController(rootView: content())
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .custom
            let transitioning = FCLPickerTransitioningDelegate(sourceRelay: sourceRelay)
            host.transitioningDelegate = transitioning
            context.coordinator.transitioningDelegate = transitioning
            context.coordinator.ownedHost = host
            let isPresentedBindingForCompletion = $isPresented
            transitioning.onDismissCompleted = {
                isPresentedBindingForCompletion.wrappedValue = false
            }

            // Wire the shared dismiss hook. Every close path calls this.
            let isPresentedBinding = $isPresented
            sourceRelay.dismissHandler = {
                // Keyboard-first sequencing: if the keyboard is up, resign and
                // wait ~0.15 s before collapsing so the keyboard visually leaves
                // before the picker morphs down.
                let keyboardUp = context.coordinator.keyboardIsVisible
                if keyboardUp {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + FCLPickerTransitionCurves.keyboardHideLead
                    ) {
                        isPresentedBinding.wrappedValue = false
                    }
                } else {
                    isPresentedBinding.wrappedValue = false
                }
            }

            // Route accessibility escape through the same dismiss hook.
            host.view.accessibilityViewIsModal = true
            installEscapeGesture(on: host, coordinator: context.coordinator)

            // Pan-to-dismiss on the top pill region. An external
            // `FCLPickerPanDelegate` gates `shouldBegin` and permits
            // simultaneous recognition so inner scroll recognizers keep
            // working.
            let pan = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            let panDelegate = FCLPickerPanDelegate()
            panDelegate.host = host
            pan.delegate = panDelegate
            pan.cancelsTouchesInView = false
            host.view.addGestureRecognizer(pan)
            context.coordinator.panGesture = pan
            context.coordinator.panDelegate = panDelegate

            uiViewController.present(host, animated: true)
        } else {
            guard let host = context.coordinator.ownedHost,
                  host.presentingViewController != nil else { return }
            host.dismiss(animated: true)
            context.coordinator.ownedHost = nil
            context.coordinator.transitioningDelegate = nil
            sourceRelay.dismissHandler = nil
        }
    }

    private func installEscapeGesture(on host: UIViewController, coordinator: Coordinator) {
        // UIAccessibility escape gesture (two-finger Z) → `accessibilityPerformEscape`
        // is invoked by the system on the hosted view. The SwiftUI content cannot
        // override it easily; we swap the host's view to a small subclass that
        // forwards the call to the relay's dismiss hook.
        //
        // CRITICAL: the inner `hostView` must track the outer `escapeView`'s
        // size. When the presentation controller later resizes `escapeView` to
        // the final sheet frame, the inner hosting view would otherwise stay
        // pinned to the pre-present bounds (typically a small default size from
        // `UIHostingController.loadView()`), and SwiftUI would lay the entire
        // sheet out inside that tiny rect — producing the user-visible bug
        // where only a ~40 pt fragment of the sheet's top renders at the
        // top-left. Setting `autoresizingMask` is the minimal fix; using Auto
        // Layout constraints would achieve the same result.
        let relay = sourceRelay
        let escapeView = EscapeRelayView(frame: host.view.bounds) { [weak relay] in
            relay?.requestDismiss()
        }
        escapeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        escapeView.backgroundColor = .clear
        escapeView.isUserInteractionEnabled = true
        let hostView = host.view!
        hostView.frame = escapeView.bounds
        hostView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        escapeView.addSubview(hostView)
        host.view = escapeView
    }

    private final class EscapeRelayView: UIView {
        let onEscape: () -> Void
        init(frame: CGRect, onEscape: @escaping () -> Void) {
            self.onEscape = onEscape
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { nil }
        override func accessibilityPerformEscape() -> Bool {
            onEscape()
            return true
        }
    }
}

// MARK: - View convenience

extension View {
    /// Presents `content` as a custom full-screen picker overlay that animates
    /// through ``FCLPickerTransitionAnimator``. Binding flips back to `false`
    /// whenever the animator finishes a dismissal (the caller observes the
    /// binding to tear down presenter state).
    func fclPickerPresentation<CoverContent: View>(
        isPresented: Binding<Bool>,
        sourceRelay: FCLPickerSourceRelay,
        @ViewBuilder content: @escaping () -> CoverContent
    ) -> some View {
        background(
            FCLPickerPresentation(
                isPresented: isPresented,
                sourceRelay: sourceRelay,
                content: content
            )
            .frame(width: 0, height: 0)
        )
    }
}

// MARK: - Previews

#if DEBUG
struct FCLPickerTransition_Previews: PreviewProvider {
    static var previews: some View {
        FCLPickerTransitionPreviewHost()
            .previewDisplayName("Picker Morph Host (tap paperclip)")
    }
}

@MainActor
private struct FCLPickerTransitionPreviewHost: View {
    @State private var isPresented = false
    @State private var relay = FCLPickerSourceRelay()
    @State private var buttonFrame: CGRect = .zero

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(.systemBackground).ignoresSafeArea()
            Button {
                isPresented = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.blue.opacity(0.15)))
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            let frame = proxy.frame(in: .global)
                            relay.sourceFrame = frame
                            buttonFrame = frame
                        }
                        .onChange(of: proxy.frame(in: .global)) { _, new in
                            relay.sourceFrame = new
                            buttonFrame = new
                        }
                }
            )
            .padding(16)
        }
        .fclPickerPresentation(isPresented: $isPresented, sourceRelay: relay) {
            ZStack(alignment: .topTrailing) {
                Color(.secondarySystemBackground).ignoresSafeArea()
                VStack {
                    Capsule()
                        .fill(Color(.tertiaryLabel))
                        .frame(width: 36, height: 5)
                        .padding(.top, 10)
                    Text("Mock picker body")
                        .font(.headline)
                        .padding()
                    Spacer()
                }
                Button("Close") { relay.requestDismiss() }
                    .padding()
            }
        }
    }
}
#endif
#endif
