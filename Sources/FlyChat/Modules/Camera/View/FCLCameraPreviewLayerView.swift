#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import SwiftUI
import UIKit

/// UIKit-backed view that hosts an `AVCaptureVideoPreviewLayer`.
///
/// The layer's `videoGravity` is set to `.resizeAspectFill` so the preview
/// fills the available area (matching iOS Camera behavior). Pinch-to-zoom
/// and tap-to-focus are implemented here via UIKit gesture recognizers and
/// bridged to the SwiftUI layer through closures supplied by the caller.
@MainActor
final class FCLCameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }
}

/// SwiftUI wrapper for `FCLCameraPreviewUIView`.
struct FCLCameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Called when the user taps to focus. Provides the normalized device
    /// point (0...1 in each axis, `AVCaptureDevice`-coordinate space) and
    /// the tap location in the SwiftUI view's coordinate space.
    let onTapToFocus: (_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void
    /// Phases of a pinch gesture reported by the preview layer.
    enum PinchPhase {
        case began
        case changed(scale: CGFloat, velocity: CGFloat)
        case ended
    }

    /// Called for each phase of a pinch gesture. The caller is responsible
    /// for snapshotting the pre-gesture zoom at `.began` and applying scale
    /// deltas via the presenter's pinch entry point.
    let onPinch: (PinchPhase) -> Void
    /// Enables/disables tap-to-focus and pinch-to-zoom on the preview. Used
    /// to suppress gesture deltas during a camera flip animation so pre-flip
    /// coordinates and in-flight pinch scales do not leak into post-flip
    /// device configuration.
    var gesturesEnabled: Bool = true
    /// Scope 08: optional relay that records the preview view reference so
    /// the close transition can take a Metal-safe `snapshotView(...)` of the
    /// live preview layer without reaching through the view hierarchy.
    var sourceRelay: FCLCameraSourceRelay?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapToFocus: onTapToFocus, onPinch: onPinch)
    }

    func makeUIView(context: Context) -> FCLCameraPreviewUIView {
        let view = FCLCameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.session = session

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        context.coordinator.pinchRecognizer = pinch

        context.coordinator.previewView = view
        context.coordinator.applyGesturesEnabled(gesturesEnabled)
        // Scope 08: register the preview view with the relay so the close
        // transition can snapshot the live Metal-backed preview layer.
        sourceRelay?.previewView = view
        return view
    }

    func updateUIView(_ uiView: FCLCameraPreviewUIView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
        context.coordinator.applyGesturesEnabled(gesturesEnabled)
        sourceRelay?.previewView = uiView
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var previewView: FCLCameraPreviewUIView?
        weak var tapRecognizer: UITapGestureRecognizer?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        let onTapToFocus: (CGPoint, CGPoint) -> Void
        let onPinch: (PinchPhase) -> Void

        init(onTapToFocus: @escaping (CGPoint, CGPoint) -> Void,
             onPinch: @escaping (PinchPhase) -> Void) {
            self.onTapToFocus = onTapToFocus
            self.onPinch = onPinch
        }

        func applyGesturesEnabled(_ enabled: Bool) {
            // Setting `isEnabled = false` cancels any in-flight gesture and
            // prevents new touches from being recognized — exactly what is
            // needed during the flip rotation so pre-flip pinch deltas and
            // tap-to-focus coordinates do not leak into the post-flip device.
            tapRecognizer?.isEnabled = enabled
            pinchRecognizer?.isEnabled = enabled
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = previewView else { return }
            let point = recognizer.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: point)
            onTapToFocus(devicePoint, point)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onPinch(.began)
            case .changed:
                onPinch(.changed(scale: recognizer.scale, velocity: recognizer.velocity))
            case .ended, .cancelled, .failed:
                onPinch(.ended)
            default:
                break
            }
        }
    }
}

#if DEBUG
#Preview("Preview layer placeholder") {
    // A live preview requires a real AVCaptureSession + device, which is
    // unavailable in Xcode previews. Show a stand-in so the surrounding
    // overlay previews have something to render on top of.
    ZStack {
        Color.black
        Text("Camera preview")
            .foregroundStyle(.white.opacity(0.4))
    }
    .ignoresSafeArea()
}
#endif

#endif
