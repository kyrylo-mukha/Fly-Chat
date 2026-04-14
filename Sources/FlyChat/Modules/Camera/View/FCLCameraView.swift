#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import ImageIO
import SwiftUI
import UIKit

/// Top-level SwiftUI screen for the FlyChat camera module.
///
/// Arranges an `AVCaptureVideoPreviewLayer`-backed view under an overlay of
/// top/bottom bars, focus reticle, and record timer. Wires all user
/// interactions to `FCLCameraPresenter` and surfaces final results to the
/// caller via closures (typically owned by `FCLCameraRouter`).
public struct FCLCameraView: View {
    @StateObject private var presenter: FCLCameraPresenter
    private let onFinish: ([FCLCameraCaptureResult]) -> Void
    private let onCancel: () -> Void

    @State private var focusTap: FCLCameraFocusTap?
    @State private var flipAnimationTrigger: Int = 0
    @State private var captureInFlight: Bool = false
    @State private var shutterFlashOpacity: Double = 0
    @State private var flipMidpointBlur: Bool = false
    @State private var previewGesturesEnabled: Bool = true
    @State private var latestThumbnail: UIImage?

    public init(
        presenter: FCLCameraPresenter,
        onFinish: @escaping ([FCLCameraCaptureResult]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content

            overlay

            // Photo shutter flash feedback overlay (on top, non-interactive).
            // iOS Camera flashes white briefly on capture — match that.
            Color.white
                .opacity(shutterFlashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .task {
            if presenter.authorizationState == .notDetermined {
                _ = await presenter.requestAuthorization()
            }
            if presenter.authorizationState == .authorized {
                presenter.startSession()
            }
        }
        .onDisappear {
            presenter.stopSession()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch presenter.authorizationState {
        case .authorized:
            previewContent
        case .notDetermined:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        case .denied, .restricted:
            deniedContent
        }
    }

    private var previewContent: some View {
        GeometryReader { proxy in
            ZStack {
                FCLCameraPreviewLayerView(
                    session: presenter.previewSession(),
                    onTapToFocus: { devicePoint, viewPoint in
                        presenter.focusAndExpose(at: devicePoint)
                        focusTap = FCLCameraFocusTap(location: viewPoint)
                    },
                    onPinchZoom: { factor in
                        presenter.setZoom(factor)
                    },
                    zoomFactorProvider: { presenter.zoomFactor },
                    gesturesEnabled: previewGesturesEnabled
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                // Focus reticle lives in the same coordinate space as the
                // tap points reported by the preview layer above.
                FCLCameraFocusIndicator(tap: focusTap)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .rotation3DEffect(
                .degrees(Double(flipAnimationTrigger) * 180),
                axis: (x: 0, y: 1, z: 0)
            )
            .blur(radius: flipMidpointBlur ? 20 : 0)
            .opacity(flipMidpointBlur ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.35), value: flipAnimationTrigger)
            .animation(.easeInOut(duration: 0.175), value: flipMidpointBlur)
            .ignoresSafeArea()
        }
    }

    private var deniedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera access is off")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Enable camera access in Settings to take photos and videos.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                openSettings()
            } label: {
                Text("Open Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
            }
            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .tint(.white)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                FCLCameraTopBar(
                    flashMode: presenter.flashMode,
                    showsDone: shouldShowDone,
                    isRecording: presenter.isRecording,
                    onClose: handleClose,
                    onToggleFlash: cycleFlash,
                    onDone: handleDone
                )

                if presenter.isRecording {
                    FCLCameraRecordTimer(
                        duration: presenter.recordingDuration,
                        isRecording: true
                    )
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                }
            }

            Spacer()

            FCLCameraBottomBar(
                mode: presenter.mode,
                isRecording: presenter.isRecording,
                allowsVideo: presenter.configuration.allowsVideo,
                capturedCount: presenter.capturedResults.count,
                latestThumbnail: latestThumbnail,
                canShowStack: presenter.configuration.maxAssets > 1,
                currentZoom: presenter.zoomFactor,
                showsZoomPresets: !presenter.isRecording,
                onSetMode: { presenter.setMode($0) },
                onShutter: { handleShutter() },
                onFlip: handleFlip,
                onOpenStack: handleDone,
                onSelectZoomPreset: { presenter.setZoom($0) }
            )
        }
        .onChange(of: presenter.capturedResults.count) { _, _ in
            refreshLatestThumbnail()
        }
    }

    // MARK: - Actions

    private var shouldShowDone: Bool {
        presenter.configuration.maxAssets > 1
            && !presenter.capturedResults.isEmpty
            && !presenter.isRecording
    }

    private func handleClose() {
        if presenter.isRecording {
            Task { try? await presenter.stopRecording() }
        }
        presenter.clearResults()
        onCancel()
    }

    private func handleDone() {
        guard !presenter.capturedResults.isEmpty else { return }
        let results = presenter.capturedResults
        // Clear staged camera results on every Done exit so the
        // presenter cannot leak stale captures into a later re-entry. The
        // router currently constructs a fresh presenter per-presentation, but
        // making the clear explicit here also covers any future host that
        // retains the presenter across sessions.
        presenter.clearResults()
        onFinish(results)
    }

    private func handleFlip() {
        flipAnimationTrigger += 1
        presenter.flipCamera()
        // Suppress preview tap/pinch recognizers for the duration of
        // the flip rotation so pre-rotation tap coordinates and in-flight
        // pinch deltas cannot leak into the post-flip device configuration.
        previewGesturesEnabled = false
        // Mid-rotation blur + fade to hide the hardware handoff.
        Task { @MainActor in
            flipMidpointBlur = true
            try? await Task.sleep(nanoseconds: 175_000_000)
            flipMidpointBlur = false
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            previewGesturesEnabled = true
        }
    }

    private func cycleFlash() {
        let next: FCLCameraFlashMode
        switch presenter.flashMode {
        case .auto: next = .on
        case .on: next = .off
        case .off: next = .auto
        }
        presenter.setFlash(next)
    }

    private func handleShutter() {
        switch presenter.mode {
        case .photo:
            guard !captureInFlight else { return }
            captureInFlight = true
            triggerShutterFlash()
            Task {
                defer { captureInFlight = false }
                do {
                    _ = try await presenter.capturePhoto()
                    finishIfSingleAsset()
                } catch {
                    // Silently ignore; presenter state remains consistent.
                }
            }
        case .video:
            if presenter.isRecording {
                Task {
                    do {
                        _ = try await presenter.stopRecording()
                        finishIfSingleAsset()
                    } catch {
                        // Silently ignore; presenter cleans up timers.
                    }
                }
            } else {
                do {
                    try presenter.startRecording()
                } catch {
                    // Silently ignore.
                }
            }
        }
    }

    private func triggerShutterFlash() {
        Task { @MainActor in
            shutterFlashOpacity = 0.85
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeOut(duration: 0.12)) {
                shutterFlashOpacity = 0
            }
        }
    }

    private func finishIfSingleAsset() {
        if presenter.configuration.maxAssets == 1,
           !presenter.capturedResults.isEmpty {
            onFinish(presenter.capturedResults)
        }
    }

    /// Decode a small thumbnail from the most recent capture off the
    /// main thread and feed it into the stack counter tile. For videos the
    /// thumbnail URL is preferred; if absent (current capture pipeline does
    /// not pre-generate one), the file URL is used directly — `UIImage` will
    /// load only a downsampled representation thanks to `.scaledToFill` in
    /// the consumer view, but we still constrain pixel work here.
    private func refreshLatestThumbnail() {
        guard let last = presenter.capturedResults.last else {
            latestThumbnail = nil
            return
        }
        let url = last.thumbnailURL ?? last.fileURL
        let mediaType = last.mediaType
        Task { @MainActor in
            // Decode off the main actor on a utility-priority detached task,
            // then await its result back on the main actor for state assignment.
            let image = await Task.detached(priority: .utility) {
                Self.loadThumbnail(at: url, mediaType: mediaType)
            }.value
            self.latestThumbnail = image
        }
    }

    nonisolated private static func loadThumbnail(at url: URL, mediaType: FCLCameraMode) -> UIImage? {
        switch mediaType {
        case .photo:
            // Downsample via ImageIO for memory efficiency.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else {
                return UIImage(contentsOfFile: url.path)
            }
            return UIImage(cgImage: cg)
        case .video:
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 256, height: 256)
            let time = CMTime(seconds: 0.0, preferredTimescale: 600)
            if let cg = try? generator.copyCGImage(at: time, actualTime: nil) {
                return UIImage(cgImage: cg)
            }
            return nil
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#if DEBUG
#Preview("Camera — default") {
    FCLCameraView(
        presenter: FCLCameraPresenter(configuration: FCLCameraConfiguration()),
        onFinish: { _ in },
        onCancel: { }
    )
}

#Preview("Camera — multi-capture") {
    FCLCameraView(
        presenter: FCLCameraPresenter(
            configuration: FCLCameraConfiguration(allowsVideo: true, maxAssets: 5)
        ),
        onFinish: { _ in },
        onCancel: { }
    )
}
#endif

#endif
