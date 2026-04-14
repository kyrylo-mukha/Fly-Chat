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

    // MARK: - Attachment Input Line Count Clamp

    func testAttachmentInputDefaultDeltaChatMax10() {
        XCTAssertEqual(fclAttachmentInputEffectiveLines(chatMax: 10, delta: -3), 7)
    }

    func testAttachmentInputDefaultDeltaClampsToTwo() {
        XCTAssertEqual(fclAttachmentInputEffectiveLines(chatMax: 4, delta: -3), 2)
    }

    func testAttachmentInputChatMaxOneOverrides() {
        XCTAssertEqual(fclAttachmentInputEffectiveLines(chatMax: 1, delta: 0), 1)
    }

    func testAttachmentInputSentinelForcesSingleLine() {
        XCTAssertEqual(fclAttachmentInputEffectiveLines(chatMax: 10, delta: .min), 1)
    }

    func testAttachmentInputLargeNegativeDeltaClamps() {
        XCTAssertEqual(fclAttachmentInputEffectiveLines(chatMax: 10, delta: -100), 2)
    }

}
