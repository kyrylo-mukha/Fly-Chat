#if canImport(UIKit)
import Foundation
import UIKit

// MARK: - FCLCapturedAsset

/// A single capture produced by the built-in camera during a session.
///
/// Main-actor confined because `thumbnail` is `UIImage` (not `Sendable`);
/// this is preferred over `@unchecked Sendable`.
@MainActor
public struct FCLCapturedAsset: Identifiable {
    public let id: UUID
    /// Decoded preview for the camera Done-chip and the pre-send editor thumbnail rail.
    /// `nil` while the decode is still in flight.
    public let thumbnail: UIImage?
    /// Location of the full-resolution capture on disk.
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

/// Shared observable list of captures produced during a single camera session.
///
/// Main-actor confined because `capturedAssets` carries `UIImage`, which is not `Sendable`.
/// Both the camera screen and the pre-send editor observe the same instance.
@MainActor
public final class FCLCaptureSessionRelay: ObservableObject {
    /// Captures produced during the current session, oldest first.
    @Published public var capturedAssets: [FCLCapturedAsset] = []

    /// The most recent capture, or `nil` if no captures have been made yet.
    public var lastCapturedAsset: FCLCapturedAsset? { capturedAssets.last }

    /// Creates an empty relay.
    public init() {}

    /// Appends a captured asset to `capturedAssets`.
    public func append(_ asset: FCLCapturedAsset) {
        capturedAssets.append(asset)
    }

    /// Removes the most recent capture. No-op when the list is empty.
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
