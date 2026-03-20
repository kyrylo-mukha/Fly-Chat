#if canImport(UIKit)
import AVFoundation
import SwiftUI
import UIKit

// MARK: - FCLCameraBridge

/// A `UIViewControllerRepresentable` bridge to `UIImagePickerController` configured
/// for camera capture. Returns the captured image as an `FCLAttachment`.
struct FCLCameraBridge: UIViewControllerRepresentable {
    let isVideoEnabled: Bool
    let onCapture: (FCLAttachment) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if isVideoEnabled {
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.videoQuality = .typeMedium
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, @unchecked Sendable {
        // Safety invariant: onCapture/onCancel are always called on the main thread
        // (UIImagePickerControllerDelegate callbacks are dispatched on the main queue).
        // Follow-up: remove @unchecked Sendable when delegate gains MainActor isolation.
        let onCapture: (FCLAttachment) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (FCLAttachment) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Check for video first
            if let videoURL = info[.mediaURL] as? URL {
                let fileName = "Camera_\(UUID().uuidString.prefix(8)).\(videoURL.pathExtension)"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: tempURL)
                try? FileManager.default.copyItem(at: videoURL, to: tempURL)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? nil
                let attachment = FCLAttachment(
                    type: .video,
                    url: tempURL,
                    fileName: fileName,
                    fileSize: fileSize
                )
                onCapture(attachment)
                return
            }

            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.8) else { return }

            let fileName = "Camera_\(UUID().uuidString.prefix(8)).jpg"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? data.write(to: tempURL)

            let fileSize = Int64(data.count)
            let attachment = FCLAttachment(
                type: .image,
                url: tempURL,
                fileName: fileName,
                fileSize: fileSize
            )
            onCapture(attachment)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

// MARK: - FCLCameraPreviewCell

/// A live camera preview cell for the gallery grid using `AVCaptureVideoPreviewLayer`.
///
/// Shows a live camera feed when access is granted, falling back to a static camera icon
/// when the camera is unavailable (e.g., simulator, permissions denied).
struct FCLCameraPreviewCell: UIViewRepresentable {
    func makeUIView(context: Context) -> FCLCameraPreviewUIView {
        FCLCameraPreviewUIView()
    }

    func updateUIView(_ uiView: FCLCameraPreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: FCLCameraPreviewUIView, coordinator: ()) {
        uiView.stopSession()
    }
}

final class FCLCameraPreviewUIView: UIView, @unchecked Sendable {
    // Safety invariant: all UI work happens on the main thread. The capture session
    // runs on sessionQueue. No mutable state is shared without synchronization.
    // Follow-up: refactor to actor-based isolation when UIView supports it.
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.flychat.camera-preview")
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
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
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
struct FCLCameraBridge_Previews: PreviewProvider {
    static var previews: some View {
        FCLCameraPreviewCell()
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 100, height: 100)
            .previewDisplayName("Camera Preview Cell")
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
#endif
#endif
