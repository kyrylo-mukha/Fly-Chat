#if canImport(AVFoundation) && canImport(UIKit)
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
@MainActor
public final class FCLCameraRouter {
    private let configuration: FCLCameraConfiguration
    private let onFinish: ([FCLCameraCaptureResult]) -> Void
    private let onCancel: () -> Void

    private weak var hostedController: UIViewController?
    private weak var activePresenter: FCLCameraPresenter?

    public init(
        configuration: FCLCameraConfiguration = FCLCameraConfiguration(),
        onFinish: @escaping ([FCLCameraCaptureResult]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    /// Presents the camera view full-screen from `presenter`.
    public func present(from presenter: UIViewController) {
        let cameraPresenter = FCLCameraPresenter(configuration: configuration)
        activePresenter = cameraPresenter
        let view = FCLCameraView(
            presenter: cameraPresenter,
            onFinish: { [weak self] results in
                self?.dismiss { self?.onFinish(results) }
            },
            onCancel: { [weak self] in
                self?.dismiss { self?.onCancel() }
            }
        )
        let hosting = UIHostingController(rootView: view)
        hosting.modalPresentationStyle = .fullScreen
        hosting.view.backgroundColor = .black
        hostedController = hosting
        presenter.present(hosting, animated: true)
    }

    private func dismiss(completion: @escaping () -> Void) {
        // Defensive: stop the capture session on every teardown path. The
        // SwiftUI `.onDisappear` on `FCLCameraView` also calls `stopSession()`,
        // but cover-dismiss races and host-driven dismissals can land before
        // SwiftUI propagates the disappear event — make the stop idempotent
        // by also issuing it here.
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
    }
}

#endif
