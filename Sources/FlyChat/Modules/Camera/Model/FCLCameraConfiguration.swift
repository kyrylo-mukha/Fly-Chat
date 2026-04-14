import Foundation

/// Configuration for the FlyChat camera module.
///
/// All values are clamped to safe defaults so host apps cannot
/// accidentally configure the camera into an invalid state.
public struct FCLCameraConfiguration: Sendable, Equatable {
    /// Whether video recording is available in addition to photo capture.
    public var allowsVideo: Bool
    /// Maximum number of assets that may be captured in a single session.
    /// Clamped to at least 1.
    public var maxAssets: Int
    /// Mode the camera opens in.
    public var defaultMode: FCLCameraMode
    /// Flash mode the camera opens in.
    public var defaultFlash: FCLCameraFlashMode
    /// Maximum duration of a single video recording, in seconds.
    /// Clamped to be strictly greater than zero (defaults to 60s when invalid).
    public var maxVideoDuration: TimeInterval

    public init(
        allowsVideo: Bool = true,
        maxAssets: Int = 1,
        defaultMode: FCLCameraMode = .photo,
        defaultFlash: FCLCameraFlashMode = .auto,
        maxVideoDuration: TimeInterval = 60
    ) {
        self.allowsVideo = allowsVideo
        self.maxAssets = max(1, maxAssets)
        self.defaultMode = defaultMode
        self.defaultFlash = defaultFlash
        self.maxVideoDuration = maxVideoDuration > 0 ? maxVideoDuration : 60
    }
}
