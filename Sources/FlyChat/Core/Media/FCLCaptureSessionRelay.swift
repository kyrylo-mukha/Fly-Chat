#if canImport(UIKit)
import Foundation
import UIKit

// MARK: - FCLCapturedAsset

/// Minimal value carrier for an in-flight capture produced by the built-in camera.
///
/// The relay keeps the list of assets captured during a single camera session so
/// that UI affordances across modules (the camera's Done-chip thumbnail, the
/// pre-send attachment editor) can observe the same source of truth without
/// reaching into the camera presenter's internals.
///
/// The thumbnail is a `UIImage`, which is not `Sendable`. Confining this type to
/// the main actor is the project's preferred invariant over marking it
/// `@unchecked Sendable`.
@MainActor
public struct FCLCapturedAsset: Identifiable {
    /// Stable identifier for the captured asset. Callers typically reuse the
    /// underlying camera result's `id` so downstream consumers can correlate.
    public let id: UUID
    /// Small decoded preview image used by the camera Done-chip and the
    /// pre-send editor thumbnail rail. `nil` while the decode is still in flight.
    public let thumbnail: UIImage?
    /// File URL of the captured media on disk.
    public let fileURL: URL

    /// Creates a captured asset.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - thumbnail: Optional decoded thumbnail.
    ///   - fileURL: Location of the full-resolution capture on disk.
    public init(id: UUID = UUID(), thumbnail: UIImage?, fileURL: URL) {
        self.id = id
        self.thumbnail = thumbnail
        self.fileURL = fileURL
    }
}

// MARK: - FCLCaptureSessionRelay

/// Shared relay that holds the in-flight camera capture list for the duration
/// of a single camera-session presentation.
///
/// Consumers:
/// - The camera screen updates `capturedAssets` after each successful capture
///   and reads `lastCapturedAsset?.thumbnail` to drive the Done-chip preview.
/// - The pre-send attachment editor reads `capturedAssets` to drive its
///   thumbnail carousel when launched in camera-stack mode.
///
/// The relay is main-actor confined because its published payload carries
/// `UIImage`, which is not `Sendable`.
@MainActor
public final class FCLCaptureSessionRelay: ObservableObject {
    /// Ordered list of captures produced during the current camera session,
    /// from oldest to most recent.
    @Published public var capturedAssets: [FCLCapturedAsset] = []

    /// Convenience accessor for the most recent capture, or `nil` when the
    /// session has not produced any captures yet.
    public var lastCapturedAsset: FCLCapturedAsset? { capturedAssets.last }

    /// Creates an empty relay.
    public init() {}

    /// Appends a newly captured asset to the tail of `capturedAssets`.
    /// - Parameter asset: The capture to append.
    public func append(_ asset: FCLCapturedAsset) {
        capturedAssets.append(asset)
    }

    /// Removes the most recent capture from the tail of `capturedAssets`.
    /// No-op when the list is empty.
    public func removeLast() {
        guard !capturedAssets.isEmpty else { return }
        capturedAssets.removeLast()
    }

    /// Empties `capturedAssets`. Called when the camera session ends.
    public func clear() {
        capturedAssets.removeAll()
    }
}
#endif
