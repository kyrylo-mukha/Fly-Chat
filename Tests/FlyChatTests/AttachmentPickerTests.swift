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

// MARK: - FCLRecentFilesStore

#if canImport(UIKit)
extension AttachmentPickerTests {

    func testRecentFilesStoreAddAndList() async {
        let store = FCLRecentFilesStore.shared
        await store.clear()

        let url = URL(string: "file:///tmp/test_add.pdf")!
        await store.add(fileURL: url, fileName: "test_add.pdf", fileSize: 1024)

        let list = await store.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.fileName, "test_add.pdf")
        XCTAssertEqual(list.first?.fileSize, 1024)

        await store.clear()
    }

    func testRecentFilesStoreClear() async {
        let store = FCLRecentFilesStore.shared
        await store.clear()

        await store.add(fileURL: URL(string: "file:///tmp/clear_a.pdf")!, fileName: "clear_a.pdf", fileSize: nil as Int64?)
        await store.add(fileURL: URL(string: "file:///tmp/clear_b.pdf")!, fileName: "clear_b.pdf", fileSize: nil as Int64?)

        var list = await store.list()
        XCTAssertEqual(list.count, 2)

        await store.clear()
        list = await store.list()
        XCTAssertTrue(list.isEmpty)
    }

    func testRecentFilesStoreDeduplicate() async {
        let store = FCLRecentFilesStore.shared
        await store.clear()

        let url = URL(string: "file:///tmp/dedup.pdf")!
        await store.add(fileURL: url, fileName: "dedup.pdf", fileSize: 100)
        await store.add(fileURL: url, fileName: "dedup.pdf", fileSize: 200)

        let list = await store.list()
        // Duplicate by URL — should collapse to 1, most recent version retained.
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.fileSize, 200)

        await store.clear()
    }

    func testRecentFilesStoreMostRecentFirst() async {
        let store = FCLRecentFilesStore.shared
        await store.clear()

        await store.add(fileURL: URL(string: "file:///tmp/first.pdf")!, fileName: "first.pdf", fileSize: nil as Int64?)
        await store.add(fileURL: URL(string: "file:///tmp/second.pdf")!, fileName: "second.pdf", fileSize: nil as Int64?)

        let list = await store.list()
        XCTAssertEqual(list.first?.fileName, "second.pdf")

        await store.clear()
    }
}
#endif

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

    // MARK: - Camera capture stack

    func testAppendCameraCaptureTransitionsToGallerySelected() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        XCTAssertEqual(presenter.state, .browsing)
        let attachment = FCLAttachment(
            type: .image,
            url: URL(string: "file:///tmp/cam.jpg")!,
            fileName: "cam.jpg"
        )
        presenter.appendCameraCapture(attachment)
        XCTAssertEqual(presenter.state, .gallerySelected)
        XCTAssertEqual(presenter.cameraCaptures.count, 1)
    }

    func testRemoveCameraCaptureReturnsToBrowsingWhenEmpty() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        let attachment = FCLAttachment(
            type: .image,
            url: URL(string: "file:///tmp/cam.jpg")!,
            fileName: "cam.jpg"
        )
        presenter.appendCameraCapture(attachment)
        XCTAssertEqual(presenter.state, .gallerySelected)
        presenter.removeCameraCapture(attachment.id)
        XCTAssertTrue(presenter.cameraCaptures.isEmpty)
        XCTAssertEqual(presenter.state, .browsing)
    }

    func testSendCameraAttachmentsDeliversAttachmentsAndCaption() {
        var receivedAttachments: [FCLAttachment] = []
        var receivedCaption: String?
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { attachments, caption in
            receivedAttachments = attachments
            receivedCaption = caption
        }
        let attachment = FCLAttachment(
            type: .image,
            url: URL(string: "file:///tmp/cam.jpg")!,
            fileName: "cam.jpg"
        )
        presenter.appendCameraCapture(attachment)
        presenter.captionText = "Smile!"
        presenter.sendCameraAttachments()
        XCTAssertEqual(presenter.state, .sending)
        XCTAssertEqual(receivedAttachments.count, 1)
        XCTAssertEqual(receivedCaption, "Smile!")
        XCTAssertTrue(presenter.cameraCaptures.isEmpty)
    }

    func testSendCameraAttachmentsPassesNilCaptionWhenEmpty() {
        var receivedCaption: String? = "should-be-nil"
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, caption in
            receivedCaption = caption
        }
        let attachment = FCLAttachment(
            type: .image,
            url: URL(string: "file:///tmp/cam.jpg")!,
            fileName: "cam.jpg"
        )
        presenter.appendCameraCapture(attachment)
        presenter.captionText = "  "
        presenter.sendCameraAttachments()
        XCTAssertNil(receivedCaption)
    }

    func testClearCameraCapturesEmptiesArray() {
        let presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
        presenter.appendCameraCapture(FCLAttachment(
            type: .image,
            url: URL(string: "file:///tmp/a.jpg")!,
            fileName: "a.jpg"
        ))
        presenter.appendCameraCapture(FCLAttachment(
            type: .image,
            url: URL(string: "file:///tmp/b.jpg")!,
            fileName: "b.jpg"
        ))
        XCTAssertEqual(presenter.cameraCaptures.count, 2)
        presenter.clearCameraCaptures()
        XCTAssertTrue(presenter.cameraCaptures.isEmpty)
    }
}
#endif
