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

// MARK: - FCLAttachmentPickerPresenter

#if canImport(UIKit)
@MainActor
extension AttachmentPickerTests {

    func testInitialStateIsBrowsing() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        XCTAssertEqual(presenter.state, .browsing)
        XCTAssertTrue(presenter.selectedAssets.isEmpty)
    }

    func testSelectAssetTransitionsToBrowsingToGallerySelected() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        presenter.toggleAssetSelection("asset-1")
        XCTAssertEqual(presenter.state, .gallerySelected)
    }

    func testDeselectAllReturnsToGalleryBrowsing() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        presenter.toggleAssetSelection("asset-1")
        presenter.toggleAssetSelection("asset-1")
        XCTAssertEqual(presenter.state, .browsing)
    }

    func testTabSwitchingBlockedInGallerySelected() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        presenter.toggleAssetSelection("asset-1")
        XCTAssertEqual(presenter.state, .gallerySelected)
        presenter.selectTab(.file)
        XCTAssertEqual(presenter.selectedTab, .gallery)
    }

    func testTabSwitchingAllowedInBrowsing() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        presenter.selectTab(.file)
        XCTAssertEqual(presenter.selectedTab, .file)
        presenter.selectTab(.gallery)
        XCTAssertEqual(presenter.selectedTab, .gallery)
    }

    func testFileTabHiddenWhenDisabled() {
        let delegate = TestAttachmentDelegate()
        delegate.fileTabEnabled = false
        let presenter = FCLAttachmentPickerPresenter(delegate: delegate) { _, _ in }
        XCTAssertFalse(presenter.availableTabs.contains(.file))
    }

    func testGallerySendDeliversAttachmentsAndCaption() {
        var receivedAttachments: [FCLAttachment] = []
        var receivedCaption: String?
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { attachments, caption in
            receivedAttachments = attachments
            receivedCaption = caption
        }
        presenter.toggleAssetSelection("asset-1")
        presenter.captionText = "Hello"
        let attachment = FCLAttachment(
            type: .image,
            url: URL(string: "file:///tmp/img.png")!,
            fileName: "img.png"
        )
        presenter.sendGalleryAttachments([attachment])
        XCTAssertEqual(presenter.state, .sending)
        XCTAssertEqual(receivedAttachments.count, 1)
        XCTAssertEqual(receivedCaption, "Hello")
    }

    func testFileSendDeliversAttachmentWithNilCaption() {
        var receivedAttachments: [FCLAttachment] = []
        var receivedCaption: String? = "should-be-nil"
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { attachments, caption in
            receivedAttachments = attachments
            receivedCaption = caption
        }
        let attachment = FCLAttachment(
            type: .file,
            url: URL(string: "file:///tmp/doc.pdf")!,
            fileName: "doc.pdf"
        )
        presenter.sendFileAttachment(attachment)
        XCTAssertEqual(presenter.state, .sending)
        XCTAssertEqual(receivedAttachments.count, 1)
        XCTAssertNil(receivedCaption)
    }

    func testGallerySendWithEmptyCaptionPassesNil() {
        var receivedCaption: String? = "should-be-nil"
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, caption in
            receivedCaption = caption
        }
        presenter.captionText = "   "
        let attachment = FCLAttachment(
            type: .image,
            url: URL(string: "file:///tmp/img.png")!,
            fileName: "img.png"
        )
        presenter.sendGalleryAttachments([attachment])
        XCTAssertNil(receivedCaption)
    }

    func testErrorStateAndRecovery() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        presenter.toggleAssetSelection("asset-1")
        presenter.handleError("Something went wrong")
        XCTAssertEqual(presenter.state, .error("Something went wrong"))
        presenter.dismissError()
        XCTAssertEqual(presenter.state, .gallerySelected)
    }
}
#endif
