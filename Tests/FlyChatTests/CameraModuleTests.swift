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

    func testPresenterMirrorsRelayLastThumbnail() async throws {
        let relay = FCLCaptureSessionRelay()
        let presenter = FCLCameraPresenter(
            configuration: FCLCameraConfiguration(
                allowsVideo: true,
                maxAssets: 5
            ),
            captureRelay: relay
        )

        XCTAssertNil(presenter.lastCapturedThumbnail)

        let first = UIImage(systemName: "1.circle.fill")
        relay.append(
            FCLCapturedAsset(
                id: UUID(),
                thumbnail: first,
                fileURL: URL(fileURLWithPath: "/tmp/a.jpg")
            )
        )
        // Wait for the Combine sink (`receive(on: DispatchQueue.main)`) to land the update on the main actor.
        await Task.yield()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(presenter.lastCapturedThumbnail === first)

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

        relay.clear()
        await Task.yield()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(presenter.lastCapturedThumbnail)
    }

    // MARK: - A3: pinch velocity → ramp rate mapping

    func testRateFromVelocityClampsAndScales() {
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(0), 1.0)
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(30), 1.0)
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(60), 1.0)
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(480), 8.0)
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(10_000), 32.0)
        XCTAssertEqual(FCLCameraZoomController.rateFromVelocity(-480), 8.0)
    }

    // MARK: - A6: preview factory seeds observable state

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
