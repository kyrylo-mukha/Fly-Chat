import XCTest
@testable import FlyChat

final class AttachmentPickerTests: XCTestCase {

    // MARK: - FCLPickerTab

    func testPickerTabGalleryIdentity() {
        let tab = FCLPickerTab.gallery
        XCTAssertEqual(tab, .gallery)
        XCTAssertNotEqual(tab, .file)
    }

    func testPickerTabCustomIdentity() {
        let a = FCLPickerTab.custom(id: "location")
        let b = FCLPickerTab.custom(id: "location")
        let c = FCLPickerTab.custom(id: "poll")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testPickerTabIdentifiable() {
        XCTAssertEqual(FCLPickerTab.gallery.id, "gallery")
        XCTAssertEqual(FCLPickerTab.file.id, "file")
        XCTAssertEqual(FCLPickerTab.custom(id: "loc").id, "custom-loc")
    }

    // MARK: - FCLMediaCompression

    func testMediaCompressionDefaults() {
        let config = FCLMediaCompression.default
        XCTAssertEqual(config.maxDimension, 1920)
        XCTAssertEqual(config.jpegQuality, 0.7)
        XCTAssertEqual(config.videoExportPreset, .mediumQuality)
    }

    func testMediaCompressionCustomValues() {
        let config = FCLMediaCompression(
            maxDimension: 1080,
            jpegQuality: 0.5,
            videoExportPreset: .lowQuality
        )
        XCTAssertEqual(config.maxDimension, 1080)
        XCTAssertEqual(config.jpegQuality, 0.5)
        XCTAssertEqual(config.videoExportPreset, .lowQuality)
    }

    func testVideoExportPresetRawValues() {
        XCTAssertEqual(FCLVideoExportPreset.lowQuality.rawValue, "lowQuality")
        XCTAssertEqual(FCLVideoExportPreset.passthrough.rawValue, "passthrough")
    }

    // MARK: - FCLRecentFile

    func testRecentFileStoresValues() {
        let file = FCLRecentFile(
            id: "f1",
            url: URL(string: "file:///tmp/doc.pdf")!,
            fileName: "doc.pdf",
            fileSize: 1024,
            date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(file.id, "f1")
        XCTAssertEqual(file.fileName, "doc.pdf")
        XCTAssertEqual(file.fileSize, 1024)
        XCTAssertNotNil(file.date)
    }

    func testRecentFileOptionalFields() {
        let file = FCLRecentFile(
            id: "f2",
            url: URL(string: "file:///tmp/img.png")!,
            fileName: "img.png",
            fileSize: nil,
            date: nil
        )
        XCTAssertNil(file.fileSize)
        XCTAssertNil(file.date)
    }
}
