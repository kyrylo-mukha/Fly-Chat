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

    nonisolated func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
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

        let timing = UISpringTimingParameters(
            dampingRatio: FCLPickerTransitionCurves.springDampingFraction,
            initialVelocity: .zero
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

        let timing = UISpringTimingParameters(
            dampingRatio: FCLPickerTransitionCurves.springDampingFraction,
            initialVelocity: .zero
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

    nonisolated func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        MainActor.assumeIsolated {
            FCLPickerTransitionAnimator(isPresenting: true, sourceRelay: sourceRelay)
        }
    }

    nonisolated func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        MainActor.assumeIsolated {
            let animator = FCLPickerTransitionAnimator(isPresenting: false, sourceRelay: sourceRelay)
            animator.onCompletion = { [weak self] completed in
                if completed { self?.onDismissCompleted?() }
            }
            return animator
        }
    }

    nonisolated func interactionControllerForDismissal(
        using animator: any UIViewControllerAnimatedTransitioning
    ) -> (any UIViewControllerInteractiveTransitioning)? {
        MainActor.assumeIsolated {
            interactiveDismiss.isActive ? interactiveDismiss : nil
        }
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

    final class Coordinator {
        weak var ownedHost: UIViewController?
        var transitioningDelegate: FCLPickerTransitioningDelegate?
        var panGesture: UIPanGestureRecognizer?
        var keyboardIsVisible: Bool = false
        var keyboardObservers: [NSObjectProtocol] = []

        deinit {
            let observers = keyboardObservers
            Task { @MainActor in
                for observer in observers {
                    NotificationCenter.default.removeObserver(observer)
                }
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

            // Pan-to-dismiss on the top pill region.
            let pan = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            host.view.addGestureRecognizer(pan)
            context.coordinator.panGesture = pan

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
        let relay = sourceRelay
        let escapeView = EscapeRelayView(frame: host.view.bounds) { [weak relay] in
            relay?.requestDismiss()
        }
        escapeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        escapeView.backgroundColor = .clear
        escapeView.isUserInteractionEnabled = true
        // Embed the hosting view inside the escape view so the escape gesture
        // reaches us before SwiftUI swallows it.
        let hostView = host.view!
        hostView.frame = escapeView.bounds
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

extension FCLPickerPresentation.Coordinator {
    @MainActor
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let host = ownedHost,
              let view = host.view,
              let transitioning = transitioningDelegate else { return }
        let interactive = transitioning.interactiveDismiss
        let translationY = gesture.translation(in: view).y
        let height = max(view.bounds.height, 1)
        let progress = max(0, min(1, translationY / height))

        // Only engage downward drags from the top ~40pt pill region. A drag
        // started outside that strip is ignored so inner scroll views keep
        // working.
        switch gesture.state {
        case .began:
            let startY = gesture.location(in: view).y - translationY
            guard startY <= 56 else {
                gesture.isEnabled = false
                gesture.isEnabled = true
                return
            }
            interactive.begin()
            host.dismiss(animated: true)
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
