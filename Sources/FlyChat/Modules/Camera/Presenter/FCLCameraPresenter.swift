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
/// Publishes observable state on the main actor; all session mutation runs on a
/// dedicated serial queue so the main thread is never blocked.
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

    // MARK: Capture count and thumbnail

    @Published public private(set) var capturedCount: Int = 0

    /// Thumbnail of the most recently captured asset.
    /// Driven by the relay's `capturedAssets` publisher when a relay is provided;
    /// otherwise updated via `updateLastCapturedThumbnail(_:)`.
    @Published public var lastCapturedThumbnail: UIImage?

    // MARK: Session plumbing

    private let sessionQueue = DispatchQueue(label: "com.flychat.camera.session")

    // `nonisolated(unsafe)`: mutated only on `sessionQueue`. The session is read on
    // the main thread solely to construct `AVCaptureVideoPreviewLayer(session:)`,
    // which is a safe observer that performs its own internal synchronization.
    nonisolated(unsafe) private let session = AVCaptureSession()

    nonisolated(unsafe) private var videoDeviceInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var audioDeviceInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private var movieOutput: AVCaptureMovieFileOutput?

    private let zoomController = FCLCameraZoomController()
    private var zoomStreamTask: Task<Void, Never>?

    // MARK: Capture relay

    private let captureRelay: FCLCaptureSessionRelay?
    private var captureRelayCancellable: AnyCancellable?

    nonisolated(unsafe) private var activePhotoDelegate: PhotoCaptureDelegate?
    nonisolated(unsafe) private var activeMovieDelegate: MovieRecordingDelegate?

    // `nonisolated(unsafe)`: deinit is nonisolated; storing as unsafe lets it
    // call `invalidate()` without a Swift 6 actor-isolation error.
    nonisolated(unsafe) private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

    // MARK: Init

    public init(
        configuration: FCLCameraConfiguration = FCLCameraConfiguration(),
        captureRelay: FCLCaptureSessionRelay? = nil
    ) {
        self.configuration = configuration
        self.mode = configuration.defaultMode
        self.flashMode = configuration.defaultFlash
        self.captureRelay = captureRelay
        startZoomStreamTask()
        bindCaptureRelayIfNeeded()
    }

    private func bindCaptureRelayIfNeeded() {
        guard let relay = captureRelay else { return }
        captureRelayCancellable = relay.$capturedAssets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] assets in
                self?.lastCapturedThumbnail = assets.last?.thumbnail
            }
    }

    deinit {
        recordingTimer?.invalidate()
        zoomStreamTask?.cancel()
        let capturedSession = session
        sessionQueue.async {
            if capturedSession.isRunning {
                capturedSession.stopRunning()
            }
        }
    }

    // MARK: Preview layer bridging

    /// Returns the underlying `AVCaptureSession` for constructing an
    /// `AVCaptureVideoPreviewLayer`. Do not mutate the session directly.
    public func previewSession() -> AVCaptureSession {
        session
    }

    // MARK: Authorization

    /// Requests camera (and microphone when `allowsVideo` is true) access.
    /// Updates `authorizationState` before returning.
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
        guard videoDeviceInput == nil else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let device = Self.preferredDevice(for: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        }

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
                if let audio = self.audioDeviceInput, self.session.inputs.contains(audio) {
                    self.session.removeInput(audio)
                    self.audioDeviceInput = nil
                }
            case .video:
                self.session.sessionPreset = .high
                if self.audioDeviceInput == nil,
                   let audioDevice = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                   self.session.canAddInput(audioInput) {
                    self.session.addInput(audioInput)
                    self.audioDeviceInput = audioInput
                }
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

    /// Sets an absolute zoom factor in user-visible units (e.g. 0.5, 1.0, 2.0).
    /// Pass `animated: false` during recording to avoid frame-rate glitches.
    public func setZoom(_ factor: CGFloat, animated: Bool = false) {
        let isRecordingNow = isRecording
        Task {
            await zoomController.setZoom(
                factor,
                animated: animated && !isRecordingNow
            )
        }
    }

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

    private nonisolated func refreshZoomDeviceBinding() {
        // `AVCaptureDevice` is not `Sendable`; wrap in `FCLUncheckedBox` to
        // transfer ownership from the session queue to the zoom actor's executor.
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

    /// Sets focus and exposure at a normalized device point (0…1).
    /// - Parameter devicePoint: coordinate obtained from
    ///   `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`.
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
                // Lock failure; camera remains at previous focus.
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
            // Determine the file extension before entering the session queue;
            // resolved settings from `AVCapturePhotoSettings` are not needed later.
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

    // MARK: Close / done intent signals

    /// Stops any in-progress recording (when requested) and clears captured state.
    public func closeTapped(stopRecordingIfNeeded: Bool = false) {
        if stopRecordingIfNeeded, isRecording {
            sessionQueue.async { [weak self] in
                guard let self, let movieOutput = self.movieOutput,
                      movieOutput.isRecording else { return }
                movieOutput.stopRecording()
            }
        }
        clearResults()
    }

    /// Clears staged results after the user confirms Done so a later re-entry
    /// does not observe stale captures.
    public func doneTapped() {
        clearResults()
    }

    public func updateLastCapturedThumbnail(_ image: UIImage?) {
        lastCapturedThumbnail = image
    }

    #if DEBUG
    /// Returns a presenter seeded with `capturedCount` and `lastCapturedThumbnail`
    /// for use in SwiftUI previews without a live `AVCaptureSession`.
    public static func makeForPreview(
        capturedCount: Int,
        thumbnail: UIImage?,
        configuration: FCLCameraConfiguration = FCLCameraConfiguration(
            allowsVideo: true,
            maxAssets: 5
        )
    ) -> FCLCameraPresenter {
        let presenter = FCLCameraPresenter(configuration: configuration)
        presenter.capturedCount = capturedCount
        presenter.lastCapturedThumbnail = thumbnail
        return presenter
    }
    #endif
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

/// Bridges `AVCaptureFileOutputRecordingDelegate` into an async continuation.
/// `@unchecked Sendable`: all mutable state is touched only from AVFoundation's
/// internal queue and the main actor via installed callbacks.
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
        // Some errors are non-fatal (e.g. max-duration reached);
        // `AVErrorRecordingSuccessfullyFinishedKey` distinguishes them.
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
