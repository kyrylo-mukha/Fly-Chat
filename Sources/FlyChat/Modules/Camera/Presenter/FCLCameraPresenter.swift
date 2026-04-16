#if canImport(AVFoundation) && canImport(UIKit)
@preconcurrency import AVFoundation
import Combine
import CoreGraphics
import Foundation
import UIKit

// MARK: - Public supporting types

/// Physical camera position.
public enum FCLCameraPosition: String, Sendable, Hashable, CaseIterable {
    case back
    case front

    fileprivate var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back: return .back
        case .front: return .front
        }
    }
}

/// Camera authorization state, combining camera and (when video is enabled) microphone.
public enum FCLCameraAuthorizationState: Sendable, Hashable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

/// Errors surfaced by the camera presenter.
public enum FCLCameraError: Error, Sendable {
    case notAuthorized
    case sessionNotRunning
    case deviceUnavailable
    case photoCaptureFailed(String)
    case videoRecordingFailed(String)
    case invalidOperation(String)
}

// MARK: - Presenter

/// Owns the `AVCaptureSession` and drives photo/video capture for the Camera module.
///
/// Concurrency model:
/// - The presenter itself is `@MainActor` and publishes observable state.
/// - Session mutation and output calls are dispatched onto a dedicated
///   serial `DispatchQueue` (`com.flychat.camera.session`) so the main
///   thread is never blocked by `AVCaptureSession` configuration or I/O.
/// - `AVCaptureSession` is not `Sendable`. It is stored as
///   `nonisolated(unsafe)` with the documented invariant that all mutation
///   happens on the session queue. The session reference is handed to
///   `AVCaptureVideoPreviewLayer(session:)` on the main thread by the
///   overlay — this is safe because `AVCaptureVideoPreviewLayer` only
///   observes the session and performs its own internal synchronization.
@MainActor
public final class FCLCameraPresenter: ObservableObject {
    // MARK: Configuration

    public let configuration: FCLCameraConfiguration

    // MARK: Observable state

    @Published public private(set) var mode: FCLCameraMode
    @Published public private(set) var flashMode: FCLCameraFlashMode
    @Published public private(set) var position: FCLCameraPosition = .back
    @Published public private(set) var zoomFactor: CGFloat = 1
    /// Device-derived preset factors (user-visible, e.g. `[0.5, 1, 2, 3]`).
    /// Updated when the bound device changes (initial configure or flip).
    @Published public private(set) var zoomPresets: [CGFloat] = [1.0]
    /// Legal user-visible zoom range for the current device.
    @Published public private(set) var zoomRange: ClosedRange<CGFloat> = 1.0...1.0
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var capturedResults: [FCLCameraCaptureResult] = []
    @Published public private(set) var isSessionRunning: Bool = false
    @Published public private(set) var authorizationState: FCLCameraAuthorizationState = .notDetermined

    // MARK: Scope 05 — capture count and thumbnail

    /// Number of assets captured in the current session. MainActor-safe.
    @Published public private(set) var capturedCount: Int = 0

    /// Thumbnail of the most recently captured asset. Kept in sync by
    /// `FCLCameraView.refreshLatestThumbnail()` via the shared
    /// `FCLCaptureSessionRelay` so the Done-chip always shows the latest capture.
    @Published public var lastCapturedThumbnail: UIImage?

    // MARK: Session plumbing

    /// Serial queue for all `AVCaptureSession` mutation and output interaction.
    /// Invariant: the session and its inputs/outputs are only touched here.
    private let sessionQueue = DispatchQueue(label: "com.flychat.camera.session")

    // Invariant: mutated only on `sessionQueue`. Read from main thread only to
    // hand into `AVCaptureVideoPreviewLayer(session:)`, which is a safe observer.
    nonisolated(unsafe) private let session = AVCaptureSession()

    nonisolated(unsafe) private var videoDeviceInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var audioDeviceInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private var movieOutput: AVCaptureMovieFileOutput?

    /// Zoom state owner. Actor-isolated; all AVCaptureDevice lock/ramp calls
    /// for zoom happen inside it. The presenter subscribes to the actor's
    /// display-value stream and republishes on the main actor.
    private let zoomController = FCLCameraZoomController()
    private var zoomStreamTask: Task<Void, Never>?

    // Active delegates held strong for the life of a capture.
    nonisolated(unsafe) private var activePhotoDelegate: PhotoCaptureDelegate?
    nonisolated(unsafe) private var activeMovieDelegate: MovieRecordingDelegate?

    // Invariant: mutated only on the main actor. Stored as nonisolated(unsafe)
    // so that deinit (which is nonisolated) can safely invalidate the timer
    // without triggering a Swift 6 actor-isolation error.
    nonisolated(unsafe) private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

    // MARK: Init

    public init(configuration: FCLCameraConfiguration = FCLCameraConfiguration()) {
        self.configuration = configuration
        self.mode = configuration.defaultMode
        self.flashMode = configuration.defaultFlash
        startZoomStreamTask()
    }

    deinit {
        recordingTimer?.invalidate()
        zoomStreamTask?.cancel()
        // Defensive teardown: ensure the capture session is stopped even when
        // higher-level lifecycle paths (router dismantle, hosting controller
        // disappearance) are bypassed. The session and queue are
        // `nonisolated(unsafe)` (see invariants above) so they are safe to
        // touch from this nonisolated deinit. `stopRunning()` is a no-op when
        // the session is already stopped.
        let capturedSession = session
        sessionQueue.async {
            if capturedSession.isRunning {
                capturedSession.stopRunning()
            }
        }
    }

    // MARK: Preview layer bridging

    /// Main-thread accessor for the underlying `AVCaptureSession`.
    ///
    /// The UI overlay uses this to construct an
    /// `AVCaptureVideoPreviewLayer(session:)` for its preview bridge.
    /// Do not mutate the returned session from the caller — use the
    /// presenter's methods instead.
    public func previewSession() -> AVCaptureSession {
        session
    }

    // MARK: Authorization

    /// Requests camera (and microphone when `allowsVideo` is true) access.
    ///
    /// Authorization contract: callers MUST `await requestAuthorization()` and
    /// confirm the returned `Bool` is `true` (or that `authorizationState`
    /// transitioned to `.authorized`) **before** invoking `capturePhoto()`,
    /// `startRecording()`, or `stopRecording()`. The `authorizationState`
    /// publisher is updated synchronously on the main actor inside this method
    /// before it returns, so a subsequent capture call performed in the same
    /// task continuation is guaranteed to see the up-to-date state and pass
    /// the internal `authorizationState == .authorized` guard.
    /// - Returns: `true` when all required permissions are granted.
    public func requestAuthorization() async -> Bool {
        let cameraGranted = await Self.requestAccess(for: .video)
        var micGranted = true
        if configuration.allowsVideo {
            micGranted = await Self.requestAccess(for: .audio)
        }
        let state = Self.combinedAuthorizationState(
            video: AVCaptureDevice.authorizationStatus(for: .video),
            audio: configuration.allowsVideo ? AVCaptureDevice.authorizationStatus(for: .audio) : .authorized
        )
        self.authorizationState = state
        return cameraGranted && micGranted
    }

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func combinedAuthorizationState(
        video: AVAuthorizationStatus,
        audio: AVAuthorizationStatus
    ) -> FCLCameraAuthorizationState {
        func map(_ status: AVAuthorizationStatus) -> FCLCameraAuthorizationState {
            switch status {
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .restricted: return .restricted
            case .authorized: return .authorized
            @unknown default: return .denied
            }
        }
        let v = map(video)
        let a = map(audio)
        // Choose the "worst" outcome across both permissions.
        let order: [FCLCameraAuthorizationState] = [.denied, .restricted, .notDetermined, .authorized]
        for s in order {
            if v == s || a == s { return s }
        }
        return .authorized
    }

    // MARK: Session lifecycle

    /// Configures (if needed) and starts the capture session. Idempotent.
    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionIfNeeded()
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            Task { @MainActor [weak self] in
                self?.isSessionRunning = running
            }
        }
    }

    /// Stops the capture session. Idempotent.
    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor [weak self] in
                self?.isSessionRunning = false
            }
        }
    }

    private nonisolated func configureSessionIfNeeded() {
        // Called only on sessionQueue.
        guard videoDeviceInput == nil else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Video input
        if let device = Self.preferredDevice(for: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        }

        // Photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        session.commitConfiguration()
        refreshZoomDeviceBinding()
    }

    private nonisolated static func preferredDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera, .builtInTripleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: Mode / flash / flip

    public func setMode(_ newMode: FCLCameraMode) {
        guard newMode != mode else { return }
        if newMode == .video && !configuration.allowsVideo { return }
        mode = newMode

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            switch newMode {
            case .photo:
                self.session.sessionPreset = .photo
                if let movie = self.movieOutput, self.session.outputs.contains(movie) {
                    self.session.removeOutput(movie)
                }
                self.movieOutput = nil
                // Remove audio input when not recording video.
                if let audio = self.audioDeviceInput, self.session.inputs.contains(audio) {
                    self.session.removeInput(audio)
                    self.audioDeviceInput = nil
                }
            case .video:
                self.session.sessionPreset = .high
                // Add audio input if available.
                if self.audioDeviceInput == nil,
                   let audioDevice = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                   self.session.canAddInput(audioInput) {
                    self.session.addInput(audioInput)
                    self.audioDeviceInput = audioInput
                }
                // Add movie output if needed.
                if self.movieOutput == nil {
                    let movie = AVCaptureMovieFileOutput()
                    if self.session.canAddOutput(movie) {
                        self.session.addOutput(movie)
                        self.movieOutput = movie
                    }
                }
            }
            self.session.commitConfiguration()
        }
    }

    public func flipCamera() {
        let newPosition: FCLCameraPosition = (position == .back) ? .front : .back
        position = newPosition

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let newDevice = Self.preferredDevice(for: newPosition.avPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
            self.session.beginConfiguration()
            if let existing = self.videoDeviceInput {
                self.session.removeInput(existing)
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoDeviceInput = newInput
            } else if let existing = self.videoDeviceInput {
                // Roll back.
                self.session.addInput(existing)
            }
            self.session.commitConfiguration()
            self.refreshZoomDeviceBinding()
        }
    }

    public func setFlash(_ newFlash: FCLCameraFlashMode) {
        flashMode = newFlash
    }

    // MARK: Zoom / focus

    /// Sets an absolute zoom factor in user-visible units (e.g., 0.5, 1.0, 2.0).
    /// `animated` chooses between `ramp(toVideoZoomFactor:withRate:)` and a
    /// direct assignment. When recording, callers should pass `animated: false`
    /// to avoid visible frame-rate glitches during ramp.
    public func setZoom(_ factor: CGFloat, animated: Bool = false) {
        let isRecordingNow = isRecording
        Task {
            await zoomController.setZoom(
                factor,
                animated: animated && !isRecordingNow
            )
        }
    }

    /// Applies a pinch gesture update. See `FCLCameraZoomController.applyPinch`.
    public func applyPinchZoom(
        base: CGFloat,
        scale: CGFloat,
        velocity: CGFloat,
        exponential: Bool
    ) {
        Task {
            await zoomController.applyPinch(
                base: base,
                scale: scale,
                velocity: velocity,
                exponential: exponential
            )
        }
    }

    /// Starts the MainActor task that drains the zoom controller's display
    /// stream and republishes values as the `zoomFactor` property.
    private func startZoomStreamTask() {
        zoomStreamTask?.cancel()
        zoomStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.zoomController.displayValues()
            for await value in stream {
                self.zoomFactor = value
            }
        }
    }

    /// Rebinds the zoom controller to the currently bound video device,
    /// refreshing preset factors and legal range. Called on session
    /// configuration and after camera flip.
    private nonisolated func refreshZoomDeviceBinding() {
        // Invoked from `sessionQueue`; captures the current device pointer
        // there and hops to the actor for the bind. `AVCaptureDevice` is not
        // `Sendable`, so the device pointer is wrapped in a `FCLUncheckedBox`
        // for the cross-actor hand-off. The invariant: `videoDeviceInput` is
        // mutated only on the session queue, and the zoom actor owns exclusive
        // access once bound.
        let deviceBox = FCLUncheckedBox(videoDeviceInput?.device)
        Task { [weak self] in
            guard let self else { return }
            await self.zoomController.bind(device: deviceBox.value)
            if let snap = await self.zoomController.currentSnapshot() {
                await MainActor.run { [weak self] in
                    self?.zoomPresets = snap.presetFactors
                    self?.zoomRange = snap.minFactor...snap.maxFactor
                }
            } else {
                await MainActor.run { [weak self] in
                    self?.zoomPresets = [1.0]
                    self?.zoomRange = 1.0...1.0
                }
            }
        }
    }

    /// Sets focus and exposure at a normalized device point (0...1) in the
    /// capture device's coordinate space. The overlay is expected to convert
    /// tap locations using `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`.
    public func focusAndExpose(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // Ignore; camera simply won't refocus.
            }
        }
    }

    // MARK: Photo capture

    /// Captures a still photo. Throws if the session is not running or the
    /// underlying capture fails.
    public func capturePhoto() async throws -> FCLCameraCaptureResult {
        guard authorizationState == .authorized else {
            throw FCLCameraError.notAuthorized
        }

        let currentFlash = flashMode.avFlashMode
        let photoOutput = self.photoOutput

        let result: FCLCameraCaptureResult = try await withCheckedThrowingContinuation { continuation in
            // Determine the output file extension now (before entering the session
            // queue) so the delegate doesn't need codec info from resolved settings.
            let usesHEVC = photoOutput.availablePhotoCodecTypes.contains(.hevc)
            let fileExtension = usesHEVC ? "heic" : "jpg"

            let delegate = PhotoCaptureDelegate(fileExtension: fileExtension) { [weak self] outcome in
                Task { @MainActor [weak self] in
                    self?.activePhotoDelegate = nil
                    switch outcome {
                    case .success(let result):
                        continuation.resume(returning: result)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            Task { @MainActor in
                self.activePhotoDelegate = delegate
            }

            sessionQueue.async {
                let settings: AVCapturePhotoSettings
                if usesHEVC {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    settings = AVCapturePhotoSettings()
                }
                if photoOutput.supportedFlashModes.contains(currentFlash) {
                    settings.flashMode = currentFlash
                }
                settings.photoQualityPrioritization = .quality
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }

        appendResult(result)
        return result
    }

    // MARK: Video recording

    public func startRecording() throws {
        guard configuration.allowsVideo else {
            throw FCLCameraError.invalidOperation("Video recording disabled in configuration")
        }
        guard authorizationState == .authorized else {
            throw FCLCameraError.notAuthorized
        }
        guard !isRecording else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flychat-\(UUID().uuidString).mov")
        let maxDuration = configuration.maxVideoDuration

        sessionQueue.async { [weak self] in
            guard let self, let movieOutput = self.movieOutput else { return }
            if movieOutput.isRecording { return }
            movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 600)

            let delegate = MovieRecordingDelegate { [weak self] outcome in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.finalizeRecording(outcome: outcome)
                }
            }
            Task { @MainActor [weak self] in
                self?.activeMovieDelegate = delegate
            }
            movieOutput.startRecording(to: tempURL, recordingDelegate: delegate)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRecording = true
                self.recordingStartedAt = Date()
                self.recordingDuration = 0
                self.startRecordingTimer()
            }
        }
    }

    public func stopRecording() async throws -> FCLCameraCaptureResult {
        guard isRecording else {
            throw FCLCameraError.invalidOperation("No recording in progress")
        }
        return try await withCheckedThrowingContinuation { continuation in
            // Install continuation on the active delegate.
            if let delegate = activeMovieDelegate {
                delegate.continuation = continuation
            } else {
                continuation.resume(throwing: FCLCameraError.videoRecordingFailed("No active recording"))
                return
            }
            sessionQueue.async { [weak self] in
                guard let self, let movieOutput = self.movieOutput else { return }
                if movieOutput.isRecording {
                    movieOutput.stopRecording()
                }
            }
        }
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let started = self.recordingStartedAt else { return }
                self.recordingDuration = Date().timeIntervalSince(started)
            }
        }
    }

    private func finalizeRecording(outcome: MovieRecordingDelegate.Outcome) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartedAt = nil
        isRecording = false
        let produced: FCLCameraCaptureResult? = {
            switch outcome {
            case .success(let result): return result
            case .failure: return nil
            }
        }()
        if let produced {
            appendResult(produced)
        }
        activeMovieDelegate = nil
    }

    // MARK: Results

    private func appendResult(_ result: FCLCameraCaptureResult) {
        if capturedResults.count >= configuration.maxAssets {
            capturedResults.removeFirst(capturedResults.count - configuration.maxAssets + 1)
        }
        capturedResults.append(result)
        capturedCount = capturedResults.count
    }

    public func removeLastResult() {
        guard !capturedResults.isEmpty else { return }
        capturedResults.removeLast()
        capturedCount = capturedResults.count
    }

    public func clearResults() {
        capturedResults.removeAll()
        capturedCount = 0
        lastCapturedThumbnail = nil
    }

    // MARK: Scope 05 — close / done intent signals

    /// Called when the user taps the close button. The view handles the
    /// confirmation dialog; this method performs the actual teardown.
    /// Stops any in-progress recording before clearing captured state.
    public func closeTapped(stopRecordingIfNeeded: Bool = false) {
        if stopRecordingIfNeeded, isRecording {
            // Fire-and-forget; the delegate finalizes state asynchronously.
            sessionQueue.async { [weak self] in
                guard let self, let movieOutput = self.movieOutput,
                      movieOutput.isRecording else { return }
                movieOutput.stopRecording()
            }
        }
        clearResults()
    }

    /// Called when the user taps the Done chip. The view routes back to the
    /// previewer; the presenter clears staged results so a later re-entry
    /// cannot observe stale captures.
    public func doneTapped() {
        clearResults()
    }

    /// Updates `lastCapturedThumbnail`. Called by `FCLCameraView` after each
    /// successful relay append so the Done-chip reflects the most recent capture.
    public func updateLastCapturedThumbnail(_ image: UIImage?) {
        lastCapturedThumbnail = image
    }
}

// MARK: - Photo delegate

/// Bridges `AVCapturePhotoCaptureDelegate` into an async continuation.
/// `@unchecked Sendable` is justified because the delegate stores only a
/// completion closure invoked exactly once on AVFoundation's internal queue.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Outcome {
        case success(FCLCameraCaptureResult)
        case failure(Error)
    }

    private let completion: (Outcome) -> Void
    private var didFinish = false
    /// File extension determined at capture-settings time and passed in at init
    /// so the delegate does not need to inspect deprecated or unavailable codec
    /// properties on `AVCaptureResolvedPhotoSettings`.
    private let fileExtension: String

    init(fileExtension: String, completion: @escaping (Outcome) -> Void) {
        self.fileExtension = fileExtension
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        if let error {
            completion(.failure(FCLCameraError.photoCaptureFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(FCLCameraError.photoCaptureFailed("No image data")))
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flychat-\(UUID().uuidString).\(fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            completion(.failure(FCLCameraError.photoCaptureFailed(error.localizedDescription)))
            return
        }
        let dims = photo.resolvedSettings.photoDimensions
        let pixelSize = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
        let result = FCLCameraCaptureResult(
            fileURL: url,
            mediaType: .photo,
            pixelSize: pixelSize,
            duration: nil,
            thumbnailURL: nil,
            capturedAt: Date()
        )
        completion(.success(result))
    }
}

// MARK: - Movie delegate

/// Bridges `AVCaptureFileOutputRecordingDelegate` into async flows. The
/// recording start is observed via `started`, and the final outcome is
/// delivered via a stored continuation set when `stopRecording()` is called.
/// `@unchecked Sendable` is justified because all mutable state is touched
/// only from AVFoundation's internal queue and the main actor via the
/// installed callbacks.
private final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum Outcome {
        case success(FCLCameraCaptureResult)
        case failure(Error)
    }

    var continuation: CheckedContinuation<FCLCameraCaptureResult, Error>?
    private let onFinish: (Outcome) -> Void

    init(onFinish: @escaping (Outcome) -> Void) {
        self.onFinish = onFinish
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Some AVFoundation errors are non-fatal (e.g., max-duration reached).
        let nsError = error as NSError?
        let recoverable = (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? (error == nil)
        if let error, !recoverable {
            let failure = FCLCameraError.videoRecordingFailed(error.localizedDescription)
            continuation?.resume(throwing: failure)
            continuation = nil
            onFinish(.failure(failure))
            return
        }

        let asset = AVURLAsset(url: outputFileURL)
        let capturedAt = Date()
        let storedContinuation = continuation
        let storedOnFinish = onFinish
        continuation = nil
        Task {
            // Use modern async load APIs (iOS 16+) to avoid deprecated sync
            // property access on AVAsset/AVAssetTrack.
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            let size: CGSize
            if let track = tracks?.first,
               let natural = try? await track.load(.naturalSize) {
                size = natural
            } else {
                size = .zero
            }
            let durationTime = try? await asset.load(.duration)
            let durationSeconds = durationTime.map { CMTimeGetSeconds($0) }
            let result = FCLCameraCaptureResult(
                fileURL: outputFileURL,
                mediaType: .video,
                pixelSize: size,
                duration: durationSeconds.flatMap { $0.isFinite ? $0 : nil },
                thumbnailURL: nil,
                capturedAt: capturedAt
            )
            storedContinuation?.resume(returning: result)
            storedOnFinish(.success(result))
        }
    }
}

#endif
