#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import ImageIO
import SwiftUI
import UIKit

/// Top-level SwiftUI screen for the FlyChat camera module.
///
/// Arranges an `AVCaptureVideoPreviewLayer`-backed view under an overlay of
/// top bar, mode-switcher row, shutter row, focus reticle, and record timer.
/// Wires all user interactions to `FCLCameraPresenter` and surfaces final
/// results to the caller via closures (typically owned by `FCLCameraRouter`).
public struct FCLCameraView: View {
    @StateObject private var presenter: FCLCameraPresenter
    /// Optional scope-08 relay used to keep the capture session alive across
    /// cross-dissolves to the pre-send previewer. When `nil` the view falls
    /// back to the original `onDisappear` teardown behavior.
    private let sourceRelay: FCLCameraSourceRelay?
    private let onFinish: ([FCLCameraCaptureResult]) -> Void
    private let onCancel: () -> Void

    @State private var focusTap: FCLCameraFocusTap?
    @State private var flipAnimationTrigger: Int = 0
    @State private var captureInFlight: Bool = false
    @State private var shutterFlashOpacity: Double = 0
    @State private var flipMidpointBlur: Bool = false
    @State private var previewGesturesEnabled: Bool = true
    @State private var pinchBaseZoom: CGFloat = 1.0
    @State private var zoomHUDVisible: Bool = false
    @State private var zoomHUDHideTask: Task<Void, Never>?
    @State private var showDiscardDialog: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shared capture relay mirroring the camera's in-flight capture list. Owned
    /// here so the Done-chip thumbnail and the downstream pre-send editor consume
    /// the same source of truth. The presenter's `lastCapturedThumbnail` is kept
    /// in sync via `updateLastCapturedThumbnail(_:)` after each relay append so
    /// the Done-chip reflects the most recent capture.
    @StateObject private var captureRelay = FCLCaptureSessionRelay()

    public init(
        presenter: FCLCameraPresenter,
        sourceRelay: FCLCameraSourceRelay? = nil,
        onFinish: @escaping ([FCLCameraCaptureResult]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        self.sourceRelay = sourceRelay
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content

            overlay

            zoomHUD
                .allowsHitTesting(false)

            // Photo shutter flash feedback overlay (on top, non-interactive).
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
            // Scope 08: when a cross-dissolve to the pre-send previewer is in
            // flight the relay's `isTransitioning` flag is true — keep the
            // capture session alive so the dissolve does not flash black.
            // The router's `dismissForPreviewer` path stops the session after
            // the dissolve completes.
            if sourceRelay?.isTransitioning == true { return }
            presenter.stopSession()
        }
        // Scope 09: accessibility back gesture (VoiceOver two-finger Z escape)
        // routes through the same close handler as the X button. If 2+ assets
        // are pending, a confirmation dialog is shown. `.accessibilityAction(.escape)`
        // is the iOS-supported hook for the accessibility escape gesture;
        // `.onExitCommand` is macOS/tvOS-only and unavailable on iOS.
        .accessibilityAction(.escape) {
            if presenter.capturedCount >= 2 {
                showDiscardDialog = true
            } else {
                handleClose()
            }
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
                    onPinch: { phase in
                        handlePinch(phase)
                    },
                    gesturesEnabled: previewGesturesEnabled
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

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
                    capturedCount: presenter.capturedCount,
                    isRecording: presenter.isRecording,
                    onClose: handleClose,
                    onToggleFlash: cycleFlash,
                    onDiscardAssets: { captureRelay.clear() },
                    showDiscardDialog: $showDiscardDialog
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

            if presenter.configuration.allowsVideo || !presenter.isRecording {
                FCLCameraZoomPresetRing(
                    currentZoom: presenter.zoomFactor,
                    presets: presenter.zoomPresets,
                    zoomRange: presenter.zoomRange,
                    onSelectPreset: { factor in
                        // While recording, skip the ramp animation to avoid
                        // frame-rate glitches; otherwise animate to mimic
                        // the system Camera preset feel.
                        presenter.setZoom(factor, animated: !presenter.isRecording)
                        showZoomHUD()
                    },
                    onSliderDrag: { factor in
                        presenter.setZoom(factor, animated: false)
                        showZoomHUD()
                    }
                )
                .opacity(presenter.isRecording ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: presenter.isRecording)
            }

            FCLCameraModeSwitcherRow(
                mode: presenter.mode,
                isRecording: presenter.isRecording,
                allowsVideo: presenter.configuration.allowsVideo,
                onFlip: handleFlip,
                onSetMode: { presenter.setMode($0) }
            )

            FCLCameraShutterRow(
                mode: presenter.mode,
                isRecording: presenter.isRecording,
                capturedCount: presenter.capturedCount,
                lastCapturedThumbnail: presenter.lastCapturedThumbnail,
                onShutter: { handleShutter() },
                onDone: handleDone
            )
        }
        .onChange(of: presenter.capturedResults.count) { _, _ in
            refreshLatestThumbnail()
        }
    }

    // MARK: - Actions

    private func handleClose() {
        presenter.closeTapped(stopRecordingIfNeeded: true)
        onCancel()
    }

    private func handleDone() {
        guard !presenter.capturedResults.isEmpty else { return }
        let results = presenter.capturedResults
        presenter.doneTapped()
        onFinish(results)
    }

    private func handleFlip() {
        guard !presenter.isRecording else { return }
        flipAnimationTrigger += 1
        presenter.flipCamera()
        previewGesturesEnabled = false
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

    /// Decodes a small thumbnail from the most recent capture off the main
    /// thread and pushes it into the presenter so the Done chip can display it.
    private func refreshLatestThumbnail() {
        guard let last = presenter.capturedResults.last else {
            presenter.updateLastCapturedThumbnail(nil)
            captureRelay.clear()
            return
        }
        let url = last.thumbnailURL ?? last.fileURL
        let mediaType = last.mediaType
        let captureID = last.id
        let fileURL = last.fileURL
        Task { @MainActor in
            let image = await Task.detached(priority: .utility) {
                Self.loadThumbnail(at: url, mediaType: mediaType)
            }.value
            // Source the Done-chip thumbnail through the shared capture relay so
            // the Done-chip and the pre-send editor share a single in-flight
            // capture store. Tapping Done routes through handleDone → onFinish,
            // which the host router maps to the pre-send editor presentation.
            let asset = FCLCapturedAsset(id: captureID, thumbnail: image, fileURL: fileURL)
            if captureRelay.capturedAssets.last?.id == captureID {
                captureRelay.removeLast()
            }
            captureRelay.append(asset)
            presenter.updateLastCapturedThumbnail(captureRelay.lastCapturedAsset?.thumbnail)
        }
    }

    nonisolated private static func loadThumbnail(at url: URL, mediaType: FCLCameraMode) -> UIImage? {
        switch mediaType {
        case .photo:
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

    // MARK: - Zoom HUD + pinch

    @ViewBuilder
    private var zoomHUD: some View {
        if zoomHUDVisible {
            VStack {
                Spacer().frame(height: 88)
                FCLGlassChip(title: String(format: "%.1f×", Double(presenter.zoomFactor)))
                Spacer()
            }
            .transition(.opacity)
        }
    }

    private func handlePinch(_ phase: FCLCameraPreviewLayerView.PinchPhase) {
        switch phase {
        case .began:
            pinchBaseZoom = presenter.zoomFactor
            showZoomHUD(resetFade: false)
        case .changed(let scale, let velocity):
            presenter.applyPinchZoom(
                base: pinchBaseZoom,
                scale: scale,
                velocity: velocity,
                exponential: !reduceMotion
            )
            showZoomHUD(resetFade: false)
        case .ended:
            showZoomHUD(resetFade: true)
        }
    }

    /// Shows the zoom HUD chip. When `resetFade` is true, (re)starts the
    /// 1.5s fade-out timer. Otherwise keeps the HUD sticky — used during an
    /// active gesture so rapid deltas do not continuously reset the timer.
    private func showZoomHUD(resetFade: Bool = true) {
        withAnimation(reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.85)) {
            zoomHUDVisible = true
        }
        if resetFade {
            zoomHUDHideTask?.cancel()
            zoomHUDHideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    zoomHUDVisible = false
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#if DEBUG
#Preview("Camera — FirstEnter-Photo (count=0)") {
    FCLCameraView(
        presenter: FCLCameraPresenter(
            configuration: FCLCameraConfiguration(allowsVideo: true, maxAssets: 5)
        ),
        onFinish: { _ in },
        onCancel: { }
    )
}

#Preview("Camera — FirstEnter-Video (count=0)") {
    FCLCameraView(
        presenter: {
            let p = FCLCameraPresenter(
                configuration: FCLCameraConfiguration(allowsVideo: true, maxAssets: 5, defaultMode: .video)
            )
            return p
        }(),
        onFinish: { _ in },
        onCancel: { }
    )
}

#Preview("Camera — count=1 (no dialog on close)") {
    FCLCameraView(
        presenter: FCLCameraPresenter(
            configuration: FCLCameraConfiguration(allowsVideo: true, maxAssets: 5)
        ),
        onFinish: { _ in },
        onCancel: { }
    )
}

#Preview("Camera — count=3 (discard dialog available)") {
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
