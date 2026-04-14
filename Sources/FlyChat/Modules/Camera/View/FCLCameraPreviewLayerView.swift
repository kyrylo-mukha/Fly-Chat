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
    /// Called during a pinch gesture. Argument is the cumulative scale
    /// factor relative to the start of the pinch (starts at the current
    /// presenter zoom factor).
    let onPinchZoom: (_ factor: CGFloat) -> Void
    /// Supplies the zoom factor that was active at pinch start so the
    /// gesture can apply incremental deltas relative to it.
    let zoomFactorProvider: () -> CGFloat
    /// Enables/disables tap-to-focus and pinch-to-zoom on the preview. Used
    /// to suppress gesture deltas during a camera flip animation so pre-flip
    /// coordinates and in-flight pinch scales do not leak into post-flip
    /// device configuration.
    var gesturesEnabled: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapToFocus: onTapToFocus,
                    onPinchZoom: onPinchZoom,
                    zoomFactorProvider: zoomFactorProvider)
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
        return view
    }

    func updateUIView(_ uiView: FCLCameraPreviewUIView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
        context.coordinator.applyGesturesEnabled(gesturesEnabled)
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var previewView: FCLCameraPreviewUIView?
        weak var tapRecognizer: UITapGestureRecognizer?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        let onTapToFocus: (CGPoint, CGPoint) -> Void
        let onPinchZoom: (CGFloat) -> Void
        let zoomFactorProvider: () -> CGFloat

        private var pinchStartZoom: CGFloat = 1

        init(onTapToFocus: @escaping (CGPoint, CGPoint) -> Void,
             onPinchZoom: @escaping (CGFloat) -> Void,
             zoomFactorProvider: @escaping () -> CGFloat) {
            self.onTapToFocus = onTapToFocus
            self.onPinchZoom = onPinchZoom
            self.zoomFactorProvider = zoomFactorProvider
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
                pinchStartZoom = zoomFactorProvider()
            case .changed:
                let factor = pinchStartZoom * recognizer.scale
                onPinchZoom(factor)
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
