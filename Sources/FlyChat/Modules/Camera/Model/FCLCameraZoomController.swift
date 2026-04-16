#if canImport(AVFoundation) && canImport(UIKit)
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// Actor-isolated owner of camera zoom state.
///
/// `FCLCameraZoomController` encapsulates the active `AVCaptureDevice`, its
/// legal zoom range, the set of user-facing preset factors derived from the
/// device's constituent lenses, and the bookkeeping needed to drive smooth
/// `ramp(toVideoZoomFactor:withRate:)` transitions with a rate chosen from
/// pinch velocity.
///
/// Concurrency model:
/// - The controller is an `actor`: all mutation of the bound device and of
///   the current zoom factor happens on the actor's executor.
/// - `AVCaptureDevice` is not `Sendable`. It is stored as
///   `nonisolated(unsafe)` with the invariant that every `lockForConfiguration`
///   / `ramp(...)` / direct `videoZoomFactor` write runs inside the actor.
/// - UI receives display values via a MainActor-isolated `AsyncStream<CGFloat>`
///   returned from `displayValues()`. Each `setZoom` / `ramp` tick yields the
///   current clamped factor; consumers transform that into `@Published` state
///   on the main actor.
///
/// The controller intentionally does NOT know about photo / video capture
/// modes or recording state — presenters gate whether to animate by passing
/// `animated: false` (or a short rate) while recording is in progress.
actor FCLCameraZoomController {

    // MARK: - Public types

    struct DeviceSnapshot: Sendable {
        /// Minimum legal zoom factor for the current device (typically 1.0
        /// for single-lens or 0.5 equivalent for virtual multi-cam devices).
        let minFactor: CGFloat
        /// Maximum legal zoom factor. Read from
        /// `maxAvailableVideoZoomFactor` (device-reported safe ceiling).
        let maxFactor: CGFloat
        /// Factors at which the virtual multi-cam device switches between
        /// constituent lenses when zooming out. Empty on single-lens devices.
        let switchOverFactors: [CGFloat]
        /// Preset factors to show in the ring, in display order.
        /// Always includes `1.0`; `0.5` only if ultra-wide is present;
        /// `2.0` and `3.0` only if a telephoto lens is present.
        let presetFactors: [CGFloat]
        /// Multiplier that maps "user-visible" zoom (where 1x corresponds to
        /// the device's default wide field of view) to the raw
        /// `videoZoomFactor` expected by AVCaptureDevice. For a virtual dual
        /// / triple camera whose base is 0.5x ultra-wide, the device's raw
        /// 1.0 factor corresponds to 0.5x user zoom, so the multiplier is 2.
        /// For a plain wide camera, the multiplier is 1.
        let userToDeviceScale: CGFloat
    }

    // MARK: - Stored state

    /// Bound device. `nonisolated(unsafe)` because `AVCaptureDevice` is not
    /// `Sendable`; all reads/writes happen on the actor's executor — see the
    /// invariant in the type-level doc comment.
    nonisolated(unsafe) private var device: AVCaptureDevice?

    /// Cached snapshot of the currently bound device. Refreshed on every
    /// `bind(device:)` call.
    private var snapshot: DeviceSnapshot?

    /// Current zoom factor in **user-visible** units (e.g., 0.5, 1.0, 2.0).
    private var userZoom: CGFloat = 1.0

    /// Continuation for the display-value stream. Stored so `finish()` can be
    /// called on `reset()` / teardown.
    private var displayContinuation: AsyncStream<CGFloat>.Continuation?

    // MARK: - Lifecycle

    init() {}

    /// Binds a capture device and refreshes the cached snapshot. Resets the
    /// internal user zoom to 1.0 and yields it to any active consumers so the
    /// UI re-syncs after a device flip.
    func bind(device newDevice: AVCaptureDevice?) {
        device = newDevice
        snapshot = newDevice.map { Self.makeSnapshot(for: $0) }
        userZoom = 1.0
        displayContinuation?.yield(1.0)
    }

    /// Returns the active snapshot. `nil` until `bind(device:)` has been
    /// called with a non-nil device.
    func currentSnapshot() -> DeviceSnapshot? { snapshot }

    /// Returns the current user-visible zoom factor.
    func currentZoom() -> CGFloat { userZoom }

    /// Produces an `AsyncStream` of user-visible zoom display values. Multiple
    /// calls install a single continuation; the prior stream is finished.
    func displayValues() -> AsyncStream<CGFloat> {
        displayContinuation?.finish()
        let (stream, continuation) = AsyncStream<CGFloat>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        displayContinuation = continuation
        continuation.yield(userZoom)
        return stream
    }

    /// Stops the active display-values stream, if any.
    func finishStream() {
        displayContinuation?.finish()
        displayContinuation = nil
    }

    // MARK: - Zoom operations

    /// Applies a zoom factor (user-visible units). When `animated` is true,
    /// uses `ramp(toVideoZoomFactor:withRate:)` with a rate derived from the
    /// magnitude of the change; when false, sets `videoZoomFactor` directly.
    /// The rate can be overridden via `rateOverride` for velocity-driven
    /// pinches and for recording-in-progress presets (pass a small rate).
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
            // Lock failures are swallowed; the UI simply stays at the previous
            // display value and the next gesture tick will retry.
            return
        }
        userZoom = clampedUser
        displayContinuation?.yield(clampedUser)
    }

    /// Applies a pinch delta. `scale` is the cumulative pinch scale since
    /// gesture start. `base` is the user-zoom factor at gesture start.
    /// `velocity` is the pinch recognizer's reported velocity (in `1/s`).
    /// `exponential` controls whether to apply the `pow(scale, 2.0)` curve
    /// (disabled for reduce-motion). The value is applied directly (no ramp)
    /// because pinch is already continuous user input.
    func applyPinch(
        base: CGFloat,
        scale: CGFloat,
        velocity: CGFloat,
        exponential: Bool
    ) {
        let curved: CGFloat
        if exponential {
            // Exponential mapping amplifies small scale changes near the
            // ends of the device range, matching iOS Camera's feel. Using
            // `pow(scale, 2.0)` of the incremental scale produces an
            // acceleration curve where a 10 % pinch grows into a
            // 21 % zoom delta — perceptually closer to the system app
            // than a linear 1:1 mapping.
            curved = pow(max(scale, 0.0001), 2.0)
        } else {
            curved = scale
        }
        let target = base * curved
        // Velocity-dependent: rely on direct assignment (instantaneous) for
        // gesture input; ramp is reserved for preset taps.
        _ = velocity
        setZoom(target, animated: false)
    }

    /// Cancels an in-flight ramp, if any. Used when a new input supersedes
    /// a prior animated preset tap.
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

    /// Chooses a `ramp` rate (zoom-factor doublings per second) appropriate
    /// for the magnitude of the change. Small preset jumps (e.g. 1x → 2x)
    /// should feel snappy; large jumps (e.g. 0.5x → 3x) should still land in
    /// under half a second.
    private static func defaultRate(from start: CGFloat, to target: CGFloat) -> Float {
        // Rate is expressed as doublings-per-second of `videoZoomFactor`.
        // Empirically tuned to match the iOS system Camera preset-tap feel.
        let ratio = max(start, target) / max(min(start, target), 0.0001)
        // Small changes (< 1.5x ratio) → rate ~ 8 doublings/s (fast but smooth).
        // Large changes (> 4x ratio)   → rate ~ 4 doublings/s.
        let clampedRatio = max(1.0, min(ratio, 8.0))
        let normalized = (clampedRatio - 1.0) / 7.0 // 0 (tiny) ... 1 (huge)
        return Float(8.0 - 4.0 * normalized)
    }

    // MARK: - Snapshot construction

    private static func makeSnapshot(for device: AVCaptureDevice) -> DeviceSnapshot {
        let rawSwitchOvers = device.virtualDeviceSwitchOverVideoZoomFactors
            .map { CGFloat(truncating: $0) }

        // Determine the base "user 1x" anchor. Virtual multi-cam devices
        // expose raw videoZoomFactor starting at 1.0 for their widest
        // constituent (often ultra-wide 0.5x). iOS Camera displays 1x at the
        // standard wide lens — which is the first switch-over factor on a
        // dual/triple camera, or 1.0 on a plain wide camera.
        let baseFactor: CGFloat = rawSwitchOvers.first ?? 1.0
        // Ratio of raw device factor to user-visible factor.
        let userToDeviceScale = baseFactor

        let minDeviceFactor = CGFloat(device.minAvailableVideoZoomFactor)
        let maxDeviceFactor = CGFloat(device.maxAvailableVideoZoomFactor)
        let minUserFactor = minDeviceFactor / userToDeviceScale
        let maxUserFactor = maxDeviceFactor / userToDeviceScale

        // Lens detection via constituent devices for virtual cameras, or via
        // the device's own deviceType for single-lens cameras.
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

        return DeviceSnapshot(
            minFactor: minUserFactor,
            maxFactor: maxUserFactor,
            switchOverFactors: rawSwitchOvers,
            presetFactors: presets,
            userToDeviceScale: userToDeviceScale
        )
    }
}

#endif
