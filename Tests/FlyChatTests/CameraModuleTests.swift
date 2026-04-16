#if canImport(UIKit) && canImport(AVFoundation)
import Combine
import UIKit
import XCTest
@testable import FlyChat

/// Camera module tests. Scoped to logic that does not require a live
/// `AVCaptureSession` — session mutation and capture delegates are covered
/// by higher-level integration tests that run on-device.
@MainActor
final class CameraModuleTests: XCTestCase {

    // MARK: - A4: presenter thumbnail mirrors relay's last thumbnail

    /// Scope 07 / A4: when an `FCLCaptureSessionRelay` is injected into the
    /// presenter, the presenter's `lastCapturedThumbnail` MUST track the
    /// `.last?.thumbnail` of the relay's `capturedAssets` publisher.
    func testPresenterMirrorsRelayLastThumbnail() async throws {
        let relay = FCLCaptureSessionRelay()
        let presenter = FCLCameraPresenter(
            configuration: FCLCameraConfiguration(
                allowsVideo: true,
                maxAssets: 5
            ),
            captureRelay: relay
        )

        // Initial state: empty relay, nil thumbnail.
        XCTAssertNil(presenter.lastCapturedThumbnail)

        // Append a first asset — the presenter picks up its thumbnail.
        let first = UIImage(systemName: "1.circle.fill")
        relay.append(
            FCLCapturedAsset(
                id: UUID(),
                thumbnail: first,
                fileURL: URL(fileURLWithPath: "/tmp/a.jpg")
            )
        )
        // Wait for the Combine sink (`receive(on: DispatchQueue.main)`) to
        // land the update on the main actor.
        await Task.yield()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(presenter.lastCapturedThumbnail === first)

        // Append a second asset — the presenter follows the new tail.
        let second = UIImage(systemName: "2.circle.fill")
        relay.append(
            FCLCapturedAsset(
                id: UUID(),
                thumbnail: second,
                fileURL: URL(fileURLWithPath: "/tmp/b.jpg")
            )
        )
        await Task.yield()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(presenter.lastCapturedThumbnail === second)

        // Clearing the relay drops the thumbnail back to nil.
        relay.clear()
        await Task.yield()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(presenter.lastCapturedThumbnail)
    }

    // MARK: - A3: pinch velocity → ramp rate mapping

    /// Scope 06 / A3: `rateFromVelocity(_:)` maps raw pinch velocity
    /// (points/sec) to an AVFoundation ramp rate (doublings/sec) within the
    /// empirically chosen `[1, 32]` envelope.
    func testRateFromVelocityClampsAndScales() {
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(0), 1.0)
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(30), 1.0)
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(60), 1.0)
        // 480 pt/s → rate 8.
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(480), 8.0)
        // Above the cap — saturates at 32.
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(10_000), 32.0)
        // Negative velocities (zoom-out pinch) use magnitude.
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(-480), 8.0)
    }

    // MARK: - A6: preview factory seeds observable state

    /// Scope 05 / A6: `makeForPreview(capturedCount:thumbnail:)` returns a
    /// presenter with seeded `capturedCount` and `lastCapturedThumbnail` so
    /// SwiftUI previews exercise the Done-chip without a live session.
    func testMakeForPreviewSeedsState() {
        let thumbnail = UIImage(systemName: "photo.fill")
        let presenter = FCLCameraPresenter.makeForPreview(
            capturedCount: 3,
            thumbnail: thumbnail
        )
        XCTAssertEqual(presenter.capturedCount, 3)
        XCTAssertTrue(presenter.lastCapturedThumbnail === thumbnail)
    }
}
#endif
