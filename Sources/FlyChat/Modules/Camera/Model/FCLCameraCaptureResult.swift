import CoreGraphics
import Foundation

/// Result of a single photo or video capture.
public struct FCLCameraCaptureResult: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// On-disk URL of the captured asset (photo or video file).
    public let fileURL: URL
    /// Media type of the asset.
    public let mediaType: FCLCameraMode
    /// Pixel dimensions of the captured asset. Zero-sized if unknown.
    public let pixelSize: CGSize
    /// Duration in seconds (video only); `nil` for photos.
    public let duration: TimeInterval?
    /// Optional thumbnail URL (reserved for future use; `nil` by default).
    public let thumbnailURL: URL?
    /// Timestamp when capture finished.
    public let capturedAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        mediaType: FCLCameraMode,
        pixelSize: CGSize,
        duration: TimeInterval? = nil,
        thumbnailURL: URL? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.mediaType = mediaType
        self.pixelSize = pixelSize
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.capturedAt = capturedAt
    }
}
