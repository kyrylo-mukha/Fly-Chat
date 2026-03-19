import XCTest
@testable import FlyChat
#if canImport(UIKit)
import UIKit
#endif

final class FCLUtilityTests: XCTestCase {

    // MARK: - Avatar Acronym & Color

    func testDjb2HashIsDeterministic() {
        let hash1 = FCLAvatarColorGenerator.djb2Hash("JD")
        let hash2 = FCLAvatarColorGenerator.djb2Hash("JD")
        XCTAssertEqual(hash1, hash2)
    }

    func testDjb2HashDiffersForDifferentInputs() {
        let hash1 = FCLAvatarColorGenerator.djb2Hash("JD")
        let hash2 = FCLAvatarColorGenerator.djb2Hash("KM")
        XCTAssertNotEqual(hash1, hash2)
    }

    func testAcronymFromSingleName() {
        XCTAssertEqual(FCLAvatarColorGenerator.initials(from: "Alice"), "A")
    }

    func testAcronymFromTwoNames() {
        XCTAssertEqual(FCLAvatarColorGenerator.initials(from: "John Doe"), "JD")
    }

    func testAcronymFromEmptyString() {
        XCTAssertEqual(FCLAvatarColorGenerator.initials(from: ""), "?")
    }

    func testAcronymFromThreeNames() {
        XCTAssertEqual(FCLAvatarColorGenerator.initials(from: "John Michael Doe"), "JD")
    }

    func testHueIsInValidRange() {
        let hue = FCLAvatarColorGenerator.hue(for: "JD")
        XCTAssertGreaterThanOrEqual(hue, 0)
        XCTAssertLessThan(hue, 360)
    }

    func testHueIsDeterministic() {
        let h1 = FCLAvatarColorGenerator.hue(for: "KM")
        let h2 = FCLAvatarColorGenerator.hue(for: "KM")
        XCTAssertEqual(h1, h2)
    }

    // MARK: - Attachment Grid Layout

    func testAttachmentGridSingleItemIsFullWidth() {
        let layout = FCLAttachmentGridLayout.grid(for: 1)
        XCTAssertEqual(layout, [[0]])
    }

    func testAttachmentGridTwoItemsSideBySide() {
        let layout = FCLAttachmentGridLayout.grid(for: 2)
        XCTAssertEqual(layout, [[0, 1]])
    }

    func testAttachmentGridThreeItems() {
        let layout = FCLAttachmentGridLayout.grid(for: 3)
        XCTAssertEqual(layout, [[0], [1, 2]])
    }

    func testAttachmentGridFourItems() {
        let layout = FCLAttachmentGridLayout.grid(for: 4)
        XCTAssertEqual(layout, [[0, 1], [2, 3]])
    }

    func testAttachmentGridFiveItems() {
        let layout = FCLAttachmentGridLayout.grid(for: 5)
        XCTAssertEqual(layout, [[0, 1], [2, 3], [4]])
    }

    func testAttachmentGridEmpty() {
        let layout = FCLAttachmentGridLayout.grid(for: 0)
        XCTAssertEqual(layout, [])
    }

    // MARK: - File Size Formatting

    func testFileSizeFormattingBytes() {
        XCTAssertEqual(FCLFileSizeFormatter.format(bytes: 500), "500 B")
    }

    func testFileSizeFormattingKB() {
        XCTAssertEqual(FCLFileSizeFormatter.format(bytes: 1024), "1.0 KB")
    }

    func testFileSizeFormattingMB() {
        XCTAssertEqual(FCLFileSizeFormatter.format(bytes: 1_048_576), "1.0 MB")
    }

    func testFileSizeFormattingGB() {
        XCTAssertEqual(FCLFileSizeFormatter.format(bytes: 1_073_741_824), "1.0 GB")
    }

    func testFileSizeFormattingNil() {
        XCTAssertNil(FCLFileSizeFormatter.format(bytes: nil))
    }

    // MARK: - Send Button State

    #if canImport(UIKit)
    func testSendButtonDisabledBelowMinimumLength() {
        XCTAssertFalse(FCLInputBar.isSendEnabled(text: "", minimumLength: 2, hasAttachments: false))
        XCTAssertFalse(FCLInputBar.isSendEnabled(text: "a", minimumLength: 2, hasAttachments: false))
        XCTAssertTrue(FCLInputBar.isSendEnabled(text: "ab", minimumLength: 2, hasAttachments: false))
    }

    func testSendButtonEnabledWithAttachmentsRegardlessOfText() {
        XCTAssertTrue(FCLInputBar.isSendEnabled(text: "", minimumLength: 2, hasAttachments: true))
    }

    func testSendButtonTrimsWhitespace() {
        XCTAssertFalse(FCLInputBar.isSendEnabled(text: "  ", minimumLength: 1, hasAttachments: false))
        XCTAssertTrue(FCLInputBar.isSendEnabled(text: " a ", minimumLength: 1, hasAttachments: false))
    }
    #endif

    // MARK: - Attachment Manager

    #if canImport(UIKit)
    @MainActor
    func testAttachmentManagerAddAndRemove() {
        let manager = FCLAttachmentManager()
        let attachment = FCLAttachment(type: .image, url: URL(string: "file:///tmp/img.jpg")!, fileName: "img.jpg")

        manager.appendAttachments([attachment])
        XCTAssertEqual(manager.attachments.count, 1)

        manager.removeAttachment(at: 0)
        XCTAssertTrue(manager.attachments.isEmpty)
    }

    @MainActor
    func testAttachmentManagerClearAttachments() {
        let manager = FCLAttachmentManager()
        let a1 = FCLAttachment(type: .image, url: URL(string: "file:///tmp/1.jpg")!, fileName: "1.jpg")
        let a2 = FCLAttachment(type: .file, url: URL(string: "file:///tmp/2.pdf")!, fileName: "2.pdf")
        manager.appendAttachments([a1, a2])

        manager.clearAttachments()
        XCTAssertTrue(manager.attachments.isEmpty)
    }
    #endif
}
