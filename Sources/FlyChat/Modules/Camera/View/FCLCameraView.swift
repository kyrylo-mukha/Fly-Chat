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
    /// the same source of truth. Scope 07: the presenter subscribes to this
    /// relay's `capturedAssets` publisher at init time and republishes
    /// `.last?.thumbnail` as `lastCapturedThumbnail` — no manual push from the
    /// view is needed. The legacy `updateLastCapturedThumbnail(_:)` path
    /// remains available for presenters constructed without a relay.
    @StateObject private var captureRelay: FCLCaptureSessionRelay

    public init(
        presenter: FCLCameraPresenter,
        sourceRelay: FCLCameraSourceRelay? = nil,
        captureRelay: FCLCaptureSessionRelay? = nil,
        onFinish: @escaping ([FCLCameraCaptureResult]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _captureRelay = StateObject(wrappedValue: captureRelay ?? FCLCaptureSessionRelay())
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

            // Scope 09: top-edge drag-down catcher. When 2+ captures are
            // pending and the user drags downward beyond 80 pt from the top
            // edge of the screen, raise the discard dialog instead of
            // allowing the enclosing presentation to dismiss. The capture
            // area is an invisible 80 pt strip at the top of the screen.
            swipeDownCatcher
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        // Scope 09: suppress interactive dismissal while the user has
        // 2+ captures pending. SwiftUI honors this for sheet-style
        // presentations; the UIHostingController also mirrors
        // `isModalInPresentation` in the router when count changes.
        .interactiveDismissDisabled(presenter.capturedCount >= 2)
        .task {
            if presenter.authorizationState == .notDetermined {
                _ = await presenter.requestAuthorization()
            }
            if presenter.authorizationState == .authorized {
                presenter.startSession()
            }
        }
        .onChange(of: presenter.capturedCount) { _, newCount in
            // Scope 09: mirror the SwiftUI interactive-dismiss gate onto the
            // hosting controller's `isModalInPresentation` so UIKit-level
            // swipe-down on the presented `UIHostingController` also respects
            // the confirmation contract.
            sourceRelay?.isModalInPresentation = newCount >= 2
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

    // MARK: - Swipe-down catcher

    /// Scope 09: invisible 80 pt top-edge strip that detects downward drags
    /// beyond 80 pt and, when 2+ captures are pending, raises the discard
    /// dialog. Cancels the drag so the enclosing presentation sees no motion.
    @ViewBuilder
    private var swipeDownCatcher: some View {
        if presenter.capturedCount >= 2 {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 80)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if value.translation.height > 80 {
                                    showDiscardDialog = true
                                }
                            }
                    )
                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)
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
                    gesturesEnabled: previewGesturesEnabled,
                    sourceRelay: sourceRelay
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
    /// thread and appends the result to the shared capture relay. Scope 07:
    /// the presenter is subscribed to the relay's `capturedAssets` publisher
    /// and republishes `.last?.thumbnail` as `lastCapturedThumbnail`, so no
    /// manual push into the presenter is required here.
    private func refreshLatestThumbnail() {
        guard let last = presenter.capturedResults.last else {
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
            let asset = FCLCapturedAsset(id: captureID, thumbnail: image, fileURL: fileURL)
            if captureRelay.capturedAssets.last?.id == captureID {
                captureRelay.removeLast()
            }
            captureRelay.append(asset)
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
/// Scope 05: four preview variants required by the spec. The "FirstEnter"
/// variants seed an empty presenter; the "SecondEnter" variants use
/// `FCLCameraPresenter.makeForPreview(capturedCount:thumbnail:)` so the
/// Done-chip (count + thumbnail) is exercised in preview.
private let _flcCameraPreviewThumbnail: UIImage = {
    let config = UIImage.SymbolConfiguration(
        pointSize: 18,
        weight: .semibold
    )
    let base = UIImage(
        systemName: "photo.fill",
        withConfiguration: config
    ) ?? UIImage()
    return base.withTintColor(.white, renderingMode: .alwaysOriginal)
}()

#Preview("Camera — FirstEnter-Photo") {
    FCLCameraView(
        presenter: FCLCameraPresenter(
            configuration: FCLCameraConfiguration(allowsVideo: true, maxAssets: 5)
        ),
        onFinish: { _ in },
        onCancel: { }
    )
}

#Preview("Camera — FirstEnter-Video") {
    FCLCameraView(
        presenter: FCLCameraPresenter(
            configuration: FCLCameraConfiguration(
                allowsVideo: true,
                maxAssets: 5,
                defaultMode: .video
            )
        ),
        onFinish: { _ in },
        onCancel: { }
    )
}

#Preview("Camera — SecondEnter-Photo(count=3,thumb)") {
    FCLCameraView(
        presenter: FCLCameraPresenter.makeForPreview(
            capturedCount: 3,
            thumbnail: _flcCameraPreviewThumbnail,
            configuration: FCLCameraConfiguration(
                allowsVideo: true,
                maxAssets: 5
            )
        ),
        onFinish: { _ in },
        onCancel: { }
    )
}

#Preview("Camera — SecondEnter-Video(count=1)") {
    FCLCameraView(
        presenter: FCLCameraPresenter.makeForPreview(
            capturedCount: 1,
            thumbnail: nil,
            configuration: FCLCameraConfiguration(
                allowsVideo: true,
                maxAssets: 5,
                defaultMode: .video
            )
        ),
        onFinish: { _ in },
        onCancel: { }
    )
}
#endif

#endif
