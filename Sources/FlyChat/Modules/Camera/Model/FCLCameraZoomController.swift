#if canImport(AVFoundation) && canImport(UIKit)
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// Actor-isolated owner of `AVCaptureDevice` zoom state.
/// Drives `ramp(toVideoZoomFactor:withRate:)` and direct assignments; exposes
/// an `AsyncStream<CGFloat>` of display values for MainActor consumers.
actor FCLCameraZoomController {

    // MARK: - Public types

    struct DeviceSnapshot: Sendable {
        let minFactor: CGFloat
        let maxFactor: CGFloat
        let switchOverFactors: [CGFloat]
        let presetFactors: [CGFloat]
        /// Ratio of raw `videoZoomFactor` to user-visible zoom.
        /// For a dual/triple camera whose widest constituent is ultra-wide (0.5×),
        /// `userToDeviceScale` is 2; for a plain wide camera it is 1.
        let userToDeviceScale: CGFloat
        /// User-visible zoom factor above which the device begins digital upscaling,
        /// or `nil` when the active format does not report a threshold.
        let upscaleThresholdUser: CGFloat?
    }

    // MARK: - Stored state

    /// `nonisolated(unsafe)` because `AVCaptureDevice` is not `Sendable`;
    /// every `lockForConfiguration` / `ramp(...)` / `videoZoomFactor` write
    /// runs on the actor's executor.
    nonisolated(unsafe) private var device: AVCaptureDevice?

    private var snapshot: DeviceSnapshot?
    private var userZoom: CGFloat = 1.0
    private var displayContinuation: AsyncStream<CGFloat>.Continuation?

    // MARK: - Lifecycle

    init() {}

    /// Binds a capture device, refreshes the snapshot, and resets user zoom to 1.0.
    /// The `sending` label transfers ownership of the non-`Sendable` device across
    /// the actor boundary without a strict-concurrency diagnostic.
    func bind(device newDevice: sending AVCaptureDevice?) {
        device = newDevice
        snapshot = newDevice.map { Self.makeSnapshot(for: $0) }
        userZoom = 1.0
        displayContinuation?.yield(1.0)
    }

    func currentSnapshot() -> DeviceSnapshot? { snapshot }

    func currentZoom() -> CGFloat { userZoom }

    /// Returns a stream of user-visible zoom display values.
    /// Subsequent calls replace the active stream; the prior one is finished.
    func displayValues() -> AsyncStream<CGFloat> {
        displayContinuation?.finish()
        let (stream, continuation) = AsyncStream<CGFloat>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        displayContinuation = continuation
        continuation.yield(userZoom)
        return stream
    }

    func finishStream() {
        displayContinuation?.finish()
        displayContinuation = nil
    }

    // MARK: - Zoom operations

    /// Applies a zoom factor in user-visible units.
    /// `animated` chooses between `ramp(toVideoZoomFactor:withRate:)` and direct assignment.
    func setZoom(_ factor: CGFloat, animated: Bool, rateOverride: Float? = nil) {
        guard let device, let snapshot else { return }
        let clampedUser = Self.clamp(
            factor,
            minFactor: snapshot.minFactor,
            maxFactor: snapshot.maxFactor
        )
        let deviceFactor = clampedUser * snapshot.userToDeviceScale
        let clampedDevice = max(
            device.minAvailableVideoZoomFactor,
            min(device.maxAvailableVideoZoomFactor, deviceFactor)
        )
        do {
            try device.lockForConfiguration()
            if animated {
                let rate = rateOverride ?? Self.defaultRate(
                    from: userZoom,
                    to: clampedUser
                )
                device.ramp(toVideoZoomFactor: clampedDevice, withRate: rate)
            } else {
                // Cancel any in-flight ramp before direct assignment.
                if device.isRampingVideoZoom {
                    device.cancelVideoZoomRamp()
                }
                device.videoZoomFactor = clampedDevice
            }
            device.unlockForConfiguration()
        } catch {
            return
        }
        userZoom = clampedUser
        displayContinuation?.yield(clampedUser)
    }

    /// Applies a pinch gesture update.
    /// - Parameters:
    ///   - base: user-zoom factor at gesture start.
    ///   - scale: cumulative pinch scale since gesture start.
    ///   - velocity: pinch recognizer velocity (1/s); fast pinches trigger an animated ramp.
    ///   - exponential: when `true`, applies a `pow(scale, 2.0)` curve for a perceptual feel
    ///     matching iOS Camera; disabled for reduce-motion.
    func applyPinch(
        base: CGFloat,
        scale: CGFloat,
        velocity: CGFloat,
        exponential: Bool
    ) {
        let curved: CGFloat
        if exponential {
            curved = pow(max(scale, 0.0001), 2.0)
        } else {
            curved = scale
        }
        let target = base * curved
        let velocityMagnitude = abs(velocity)
        if velocityMagnitude > Self.fastPinchVelocityThreshold {
            let rate = Self.rateFromVelocity(velocity)
            setZoom(target, animated: true, rateOverride: rate)
        } else {
            setZoom(target, animated: false)
        }
    }

    static let fastPinchVelocityThreshold: CGFloat = 20.0

    static func rateFromVelocity(_ v: CGFloat) -> Float {
        max(1.0, min(32.0, Float(abs(v) / 60)))
    }

    /// Cancels any in-flight `ramp(toVideoZoomFactor:withRate:)`.
    func cancelRamp() {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if device.isRampingVideoZoom {
                device.cancelVideoZoomRamp()
            }
            device.unlockForConfiguration()
        } catch {
            return
        }
    }

    // MARK: - Helpers

    private static func clamp(
        _ factor: CGFloat,
        minFactor: CGFloat,
        maxFactor: CGFloat
    ) -> CGFloat {
        min(max(factor, minFactor), maxFactor)
    }

    private static func defaultRate(from start: CGFloat, to target: CGFloat) -> Float {
        // Doublings-per-second of `videoZoomFactor`; empirically tuned to match
        // the iOS Camera preset-tap feel: small jumps ≈ 8 dps, large jumps ≈ 4 dps.
        let ratio = max(start, target) / max(min(start, target), 0.0001)
        let clampedRatio = max(1.0, min(ratio, 8.0))
        let normalized = (clampedRatio - 1.0) / 7.0
        return Float(8.0 - 4.0 * normalized)
    }

    // MARK: - Snapshot construction

    private static func makeSnapshot(for device: AVCaptureDevice) -> DeviceSnapshot {
        let rawSwitchOvers = device.virtualDeviceSwitchOverVideoZoomFactors
            .map { CGFloat(truncating: $0) }

        // The first switch-over factor maps raw 1.0 → user 1.0 (wide lens anchor).
        // On plain single-lens cameras there are no switch-overs, so the scale is 1.
        let baseFactor: CGFloat = rawSwitchOvers.first ?? 1.0
        let userToDeviceScale = baseFactor

        let minDeviceFactor = CGFloat(device.minAvailableVideoZoomFactor)
        let maxDeviceFactor = CGFloat(device.maxAvailableVideoZoomFactor)
        let minUserFactor = minDeviceFactor / userToDeviceScale
        let maxUserFactor = maxDeviceFactor / userToDeviceScale

        // `videoZoomFactorUpscaleThreshold` lives on `AVCaptureDevice.Format`
        // (not on the device itself); convert to user-visible units so the preset
        // ring can clamp presets that would otherwise force digital upscaling.
        let rawUpscaleThreshold = CGFloat(device.activeFormat.videoZoomFactorUpscaleThreshold)
        let upscaleThresholdUser: CGFloat?
        if rawUpscaleThreshold > 0,
           rawUpscaleThreshold.isFinite,
           rawUpscaleThreshold < maxDeviceFactor {
            upscaleThresholdUser = rawUpscaleThreshold / userToDeviceScale
        } else {
            upscaleThresholdUser = nil
        }

        let constituents = device.constituentDevices
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if constituents.isEmpty {
            deviceTypes = [device.deviceType]
        } else {
            deviceTypes = constituents.map { $0.deviceType }
        }
        let hasUltraWide = deviceTypes.contains(.builtInUltraWideCamera)
        let hasTelephoto = deviceTypes.contains(.builtInTelephotoCamera)

        var presets: [CGFloat] = []
        if hasUltraWide, minUserFactor <= 0.5 + 0.01 {
            presets.append(0.5)
        }
        presets.append(1.0)
        if hasTelephoto {
            if maxUserFactor >= 2.0 { presets.append(2.0) }
            if maxUserFactor >= 3.0 { presets.append(3.0) }
        }

        if let threshold = upscaleThresholdUser {
            presets = presets.map { preset in
                preset > threshold ? threshold : preset
            }
        }

        return DeviceSnapshot(
            minFactor: minUserFactor,
            maxFactor: maxUserFactor,
            switchOverFactors: rawSwitchOvers,
            presetFactors: presets,
            userToDeviceScale: userToDeviceScale,
            upscaleThresholdUser: upscaleThresholdUser
        )
    }
}

#endif
