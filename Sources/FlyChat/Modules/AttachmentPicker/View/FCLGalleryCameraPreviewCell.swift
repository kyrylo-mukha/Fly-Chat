#if canImport(UIKit)
import AVFoundation
import SwiftUI
import UIKit

// MARK: - FCLGalleryCameraPreviewCell

/// A live camera preview cell for the gallery grid using `AVCaptureVideoPreviewLayer`.
///
/// Shows a live camera feed when access is granted, falling back to a static camera icon
/// when the camera is unavailable (e.g., simulator, permissions denied).
///
/// - Note: Host apps must provide `NSCameraUsageDescription` in their `Info.plist`
///   for camera access to be granted.
struct FCLGalleryCameraPreviewCell: UIViewRepresentable {
    func makeUIView(context: Context) -> FCLGalleryCameraPreviewUIView {
        FCLGalleryCameraPreviewUIView()
    }

    func updateUIView(_ uiView: FCLGalleryCameraPreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: FCLGalleryCameraPreviewUIView, coordinator: ()) {
        uiView.stopSession()
    }
}

// MARK: - FCLGalleryCameraPreviewUIView

final class FCLGalleryCameraPreviewUIView: UIView, @unchecked Sendable {
    // Safety invariant: all UI work happens on the main thread. The capture session
    // runs on sessionQueue. No mutable state is shared without synchronization.
    // Follow-up: refactor to actor-based isolation when UIView supports it.
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.flychat.gallery-camera-preview")
    private let fallbackImageView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "camera.fill"))
        iv.tintColor = .secondaryLabel
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.tertiarySystemFill
        clipsToBounds = true
        setupFallback()
        startSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    private func setupFallback() {
        addSubview(fallbackImageView)
        NSLayoutConstraint.activate([
            fallbackImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            fallbackImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            fallbackImageView.widthAnchor.constraint(equalToConstant: 24),
            fallbackImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func startSession() {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil,
              ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        sessionQueue.async { [weak self] in
            let session = AVCaptureSession()
            session.sessionPreset = .low

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            if session.canAddInput(input) {
                session.addInput(input)
            }

            session.startRunning()

            DispatchQueue.main.async {
                guard let self else { return }
                self.captureSession = session
                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.bounds
                self.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
                self.fallbackImageView.isHidden = true
            }
        }
    }

    func stopSession() {
        // Safety: captureSession is created and started on sessionQueue, and stopRunning()
        // is also dispatched to sessionQueue. No concurrent access occurs.
        nonisolated(unsafe) let session = captureSession
        sessionQueue.async {
            session?.stopRunning()
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FCLGalleryCameraPreviewCell_Previews: PreviewProvider {
    static var previews: some View {
        FCLGalleryCameraPreviewCell()
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 100, height: 100)
            .previewDisplayName("Gallery Camera Preview Cell")
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
#endif
#endif
