#if canImport(AVFoundation) && canImport(UIKit)
import Combine
import SwiftUI
import UIKit

/// Presents the FlyChat camera full-screen from a host view controller and
/// delivers capture results (or a cancellation signal) back to the caller.
///
/// Typical usage from a host app or another FlyChat module:
/// ```swift
/// let router = FCLCameraRouter(
///     configuration: FCLCameraConfiguration(maxAssets: 5),
///     onFinish: { results in /* hand off to attachment preview */ },
///     onCancel: { /* dismissed without capturing */ }
/// )
/// router.present(from: hostViewController)
/// ```
///
/// When presented from the attachment picker's gallery, callers can supply an
/// ``FCLCameraSourceRelay`` so the open and close animations morph from the
/// camera cell's on-screen rect (scope 08). The relay is optional — when
/// `nil`, the router falls back to the system cross-dissolve.
@MainActor
public final class FCLCameraRouter {
    private let configuration: FCLCameraConfiguration
    private let onFinish: ([FCLCameraCaptureResult]) -> Void
    private let onCancel: () -> Void
    private let sourceRelay: FCLCameraSourceRelay?

    private weak var hostedController: UIViewController?
    private weak var activePresenter: FCLCameraPresenter?
    private var transitioningDelegate: FCLCameraTransitioningDelegate?
    private var modalInPresentationCancellable: AnyCancellable?

    public init(
        configuration: FCLCameraConfiguration = FCLCameraConfiguration(),
        onFinish: @escaping ([FCLCameraCaptureResult]) -> Void,
        onCancel: @escaping () -> Void,
        sourceRelay: FCLCameraSourceRelay? = nil
    ) {
        self.configuration = configuration
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.sourceRelay = sourceRelay
    }

    /// Presents the camera view full-screen from `presenter`.
    ///
    /// When a source relay is attached, the open animation morphs from the
    /// relay's `sourceFrame`. When `sourceFrame` is `nil`, a safe bottom-center
    /// fallback rect is used (see ``FCLCameraTransition``).
    public func present(from presenter: UIViewController) {
        let captureRelay = FCLCaptureSessionRelay()
        let cameraPresenter = FCLCameraPresenter(
            configuration: configuration,
            captureRelay: captureRelay
        )
        activePresenter = cameraPresenter
        let view = FCLCameraView(
            presenter: cameraPresenter,
            sourceRelay: sourceRelay,
            captureRelay: captureRelay,
            onFinish: { [weak self] results in
                self?.dismiss { self?.onFinish(results) }
            },
            onCancel: { [weak self] in
                self?.dismiss { self?.onCancel() }
            }
        )
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .black
        hostedController = hosting

        if let relay = sourceRelay {
            let delegate = FCLCameraTransitioningDelegate(sourceRelay: relay)
            transitioningDelegate = delegate
            hosting.transitioningDelegate = delegate
            hosting.modalPresentationStyle = .custom
            relay.isTransitioning = true
            hosting.isModalInPresentation = relay.isModalInPresentation
            modalInPresentationCancellable = relay.$isModalInPresentation
                .receive(on: DispatchQueue.main)
                .sink { [weak hosting] newValue in
                    hosting?.isModalInPresentation = newValue
                }
            presenter.present(hosting, animated: true) { [weak relay] in
                relay?.isTransitioning = false
            }
        } else {
            hosting.modalPresentationStyle = .fullScreen
            presenter.present(hosting, animated: true)
        }
    }

    /// Opens the camera with an explicit source rect. Convenience wrapper
    /// around ``present(from:)`` for hosts that already know the cell frame
    /// but have not yet wired a long-lived relay.
    ///
    /// Writes `frame` into the relay (if one is configured) and then presents.
    public func open(from presenter: UIViewController, fromSourceFrame frame: CGRect) {
        sourceRelay?.sourceFrame = frame
        present(from: presenter)
    }

    /// Dismisses the camera, animating the close transition when a relay is
    /// attached (snapshot-morph back to the source cell with pulse highlight).
    /// When `animated` is `false` or no host is alive, the teardown is synchronous.
    public func close(animated: Bool = true) {
        guard let hosted = hostedController else { return }
        if !animated {
            hosted.dismiss(animated: false)
            activePresenter?.stopSession()
            activePresenter = nil
            hostedController = nil
            transitioningDelegate = nil
            modalInPresentationCancellable = nil
            return
        }
        sourceRelay?.isTransitioning = true
        hosted.dismiss(animated: true) { [weak self] in
            self?.activePresenter?.stopSession()
            self?.activePresenter = nil
            self?.hostedController = nil
            self?.transitioningDelegate = nil
            self?.modalInPresentationCancellable = nil
            self?.sourceRelay?.isTransitioning = false
        }
    }

    /// Signals that capture is complete and the pre-send editor should open.
    /// Sets `isTransitioning` on the relay so the session stays alive across
    /// the cross-dissolve.
    public func presentPreviewer() {
        guard let presenter = activePresenter,
              !presenter.capturedResults.isEmpty else { return }
        let results = presenter.capturedResults
        presenter.doneTapped()
        sourceRelay?.isTransitioning = true
        dismissForPreviewer { [weak self] in
            self?.onFinish(results)
            // Clear the transitioning flag shortly after the dissolve
            // completes so a subsequent close animates normally.
            DispatchQueue.main.asyncAfter(
                deadline: .now() + FCLCameraTransitionCurves.crossDissolveDuration
            ) { [weak self] in
                self?.sourceRelay?.isTransitioning = false
            }
        }
    }

    /// Backwards-compatible alias for ``presentPreviewer()``.
    public func routeToPreviewer(animated: Bool = true) {
        _ = animated
        presentPreviewer()
    }

    /// Signals the router that the host is re-entering the camera from the previewer.
    /// Keeps the session alive across the cross-dissolve.
    public func returnFromPreviewer() {
        sourceRelay?.isTransitioning = true
        DispatchQueue.main.asyncAfter(
            deadline: .now() + FCLCameraTransitionCurves.crossDissolveDuration
        ) { [weak self] in
            self?.sourceRelay?.isTransitioning = false
        }
    }

    private func dismiss(completion: @escaping () -> Void) {
        // Stop the session here as well as in `onDisappear`: host-driven
        // dismissals can arrive before SwiftUI propagates the disappear event.
        activePresenter?.stopSession()
        activePresenter = nil

        guard let hosted = hostedController else {
            completion()
            return
        }
        hosted.dismiss(animated: true) {
            completion()
        }
        hostedController = nil
        transitioningDelegate = nil
        modalInPresentationCancellable = nil
    }

    /// Dismisses without stopping the session so the cross-dissolve to the
    /// previewer does not flash a black frame.
    private func dismissForPreviewer(completion: @escaping () -> Void) {
        guard let hosted = hostedController else {
            activePresenter = nil
            completion()
            return
        }
        hosted.dismiss(animated: true) { [weak self] in
            let presenterRef = self?.activePresenter
            DispatchQueue.main.asyncAfter(
                deadline: .now() + FCLCameraTransitionCurves.crossDissolveDuration
            ) {
                presenterRef?.stopSession()
            }
            self?.activePresenter = nil
            self?.hostedController = nil
            self?.transitioningDelegate = nil
            self?.modalInPresentationCancellable = nil
            completion()
        }
    }
}

#endif
