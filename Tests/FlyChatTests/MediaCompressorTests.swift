#if canImport(UIKit)
import XCTest
@testable import FlyChat
import UIKit

final class MediaCompressorTests: XCTestCase {

    func testImageDownscaleRespectsMaxDimension() throws {
        let image = createTestImage(width: 4000, height: 3000)
        let config = FCLMediaCompression(maxDimension: 1920)
        let result = FCLMediaCompressor.downscale(image, config: config)
        XCTAssertLessThanOrEqual(result.size.width, 1920)
        XCTAssertLessThanOrEqual(result.size.height, 1920)
        XCTAssertEqual(result.size.height, 1440, accuracy: 1)
    }

    func testImageSmallerThanMaxDimensionNotUpscaled() throws {
        let image = createTestImage(width: 800, height: 600)
        let config = FCLMediaCompression(maxDimension: 1920)
        let result = FCLMediaCompressor.downscale(image, config: config)
        XCTAssertEqual(result.size.width, 800, accuracy: 1)
        XCTAssertEqual(result.size.height, 600, accuracy: 1)
    }

    func testJPEGCompressionProducesData() throws {
        let image = createTestImage(width: 100, height: 100)
        let data = FCLMediaCompressor.compressToJPEG(image, quality: 0.7)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data!.count, 0)
    }

    func testVideoExportPresetMapping() {
        XCTAssertEqual(FCLMediaCompressor.avPreset(for: .lowQuality), "AVAssetExportPresetLowQuality")
        XCTAssertEqual(FCLMediaCompressor.avPreset(for: .mediumQuality), "AVAssetExportPresetMediumQuality")
        XCTAssertEqual(FCLMediaCompressor.avPreset(for: .highQuality), "AVAssetExportPresetHighestQuality")
        XCTAssertEqual(FCLMediaCompressor.avPreset(for: .passthrough), "AVAssetExportPresetPassthrough")
    }

    private func createTestImage(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#endif
