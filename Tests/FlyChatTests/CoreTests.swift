import XCTest
@testable import FlyChat

final class FCLCoreTests: XCTestCase {

    // MARK: - SDK

    func testSDKVersionIsNotEmpty() {
        XCTAssertFalse(FlyChat.version.isEmpty)
    }

    // MARK: - ChatMessageSender

    func testChatMessageSenderStoresValues() {
        let sender = FCLChatMessageSender(id: "user-1", displayName: "John Doe")
        XCTAssertEqual(sender.id, "user-1")
        XCTAssertEqual(sender.displayName, "John Doe")
    }

    func testChatMessageSenderEquality() {
        let a = FCLChatMessageSender(id: "user-1", displayName: "John Doe")
        let b = FCLChatMessageSender(id: "user-1", displayName: "John Doe")
        let c = FCLChatMessageSender(id: "user-2", displayName: "Jane Doe")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ImageSource

    func testImageSourceCases() {
        let named = FCLImageSource.name("avatar")
        let system = FCLImageSource.system("person.circle")
        XCTAssertNotEqual(named, system)
    }

    // MARK: - Delegate Defaults

    func testAppearanceDefaultValues() {
        XCTAssertEqual(FCLAppearanceDefaults.senderBubbleColor, FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0))
        XCTAssertEqual(FCLAppearanceDefaults.receiverBubbleColor, FCLChatColorToken(red: 0.90, green: 0.91, blue: 0.94))
        XCTAssertEqual(FCLAppearanceDefaults.senderTextColor, FCLChatColorToken(red: 1, green: 1, blue: 1))
        XCTAssertEqual(FCLAppearanceDefaults.receiverTextColor, FCLChatColorToken(red: 0.08, green: 0.08, blue: 0.09))
        XCTAssertEqual(FCLAppearanceDefaults.messageFont, FCLChatMessageFontConfiguration())
        XCTAssertEqual(FCLAppearanceDefaults.tailStyle, .edged(.bottom))
        XCTAssertEqual(FCLAppearanceDefaults.minimumBubbleHeight, 40)
    }

    func testLayoutDefaultValues() {
        XCTAssertEqual(FCLLayoutDefaults.incomingSide, .left)
        XCTAssertEqual(FCLLayoutDefaults.outgoingSide, .right)
        XCTAssertEqual(FCLLayoutDefaults.maxBubbleWidthRatio, 0.78)
        XCTAssertEqual(FCLLayoutDefaults.intraGroupSpacing, 4)
        XCTAssertEqual(FCLLayoutDefaults.interGroupSpacing, 12)
    }

    func testInputDefaultValues() {
        XCTAssertEqual(FCLInputDefaults.placeholderText, "Message")
        XCTAssertEqual(FCLInputDefaults.minimumTextLength, 1)
        XCTAssertNil(FCLInputDefaults.maxRows)
        XCTAssertTrue(FCLInputDefaults.showAttachButton)
        XCTAssertEqual(FCLInputDefaults.containerMode, .fieldOnlyRounded)
        XCTAssertFalse(FCLInputDefaults.liquidGlass)
        XCTAssertEqual(FCLInputDefaults.fieldCornerRadius, 18)
        XCTAssertTrue(FCLInputDefaults.returnKeySends)
        XCTAssertEqual(FCLInputDefaults.elementSpacing, 8)
        XCTAssertEqual(FCLInputDefaults.attachmentThumbnailSize, 32)
    }

    // MARK: - Edge Insets

    func testEdgeInsetsStoresValuesAndConverts() {
        let insets = FCLEdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        XCTAssertEqual(insets.top, 1)
        XCTAssertEqual(insets.leading, 2)
        XCTAssertEqual(insets.bottom, 3)
        XCTAssertEqual(insets.trailing, 4)

        let swiftUIInsets = insets.edgeInsets
        XCTAssertEqual(swiftUIInsets.top, 1)
        XCTAssertEqual(swiftUIInsets.leading, 2)
        XCTAssertEqual(swiftUIInsets.bottom, 3)
        XCTAssertEqual(swiftUIInsets.trailing, 4)
    }

    // MARK: - Bubble Shape

    func testBubbleTailStyleDefaultIsEdgedBottom() {
        XCTAssertEqual(FCLAppearanceDefaults.tailStyle, .edged(.bottom))
    }

    func testBubbleTailStyleEdgeEquality() {
        XCTAssertEqual(FCLBubbleTailStyle.edged(.top), FCLBubbleTailStyle.edged(.top))
        XCTAssertNotEqual(FCLBubbleTailStyle.edged(.top), FCLBubbleTailStyle.edged(.bottom))
        XCTAssertNotEqual(FCLBubbleTailStyle.none, FCLBubbleTailStyle.edged(.bottom))
    }

    func testBubbleShapeProducesNonEmptyPathForAllStyles() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let styles: [FCLBubbleTailStyle] = [.none, .edged(.top), .edged(.bottom)]
        let sides: [FCLChatBubbleSide] = [.left, .right]

        for tailStyle in styles {
            for side in sides {
                let shape = FCLChatBubbleShape(side: side, tailStyle: tailStyle)
                let path = shape.path(in: rect)
                XCTAssertFalse(path.isEmpty, "Path should not be empty for \(tailStyle) \(side)")
            }
        }
    }

    func testBubbleShapeNoneIsSameForBothSides() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let leftPath = FCLChatBubbleShape(side: .left, tailStyle: .none).path(in: rect)
        let rightPath = FCLChatBubbleShape(side: .right, tailStyle: .none).path(in: rect)
        XCTAssertEqual(leftPath.boundingRect, rightPath.boundingRect)
    }

    func testBubbleShapeEdgedMirrorsDifferentlyForLeftAndRight() {
        let leftShape = FCLChatBubbleShape(side: .left, tailStyle: .edged(.bottom))
        let rightShape = FCLChatBubbleShape(side: .right, tailStyle: .edged(.bottom))
        XCTAssertNotEqual(leftShape, rightShape)
    }

    // MARK: - Context Menu Action

    func testContextMenuActionRoleEquality() {
        XCTAssertEqual(FCLContextMenuActionRole.default, FCLContextMenuActionRole.default)
        XCTAssertEqual(FCLContextMenuActionRole.destructive, FCLContextMenuActionRole.destructive)
        XCTAssertNotEqual(FCLContextMenuActionRole.default, FCLContextMenuActionRole.destructive)
    }

    func testContextMenuActionStoresValues() {
        nonisolated(unsafe) var handlerCalled = false
        let action = FCLContextMenuAction(
            title: "Copy",
            systemImage: "doc.on.doc",
            role: .default
        ) { _ in handlerCalled = true }

        XCTAssertEqual(action.title, "Copy")
        XCTAssertEqual(action.systemImage, "doc.on.doc")
        XCTAssertEqual(action.role, .default)

        let message = FCLChatMessage(text: "test", direction: .outgoing, sender: testOutgoingSender)
        action.handler(message)
        XCTAssertTrue(handlerCalled)
    }

    func testContextMenuActionDefaultValues() {
        let action = FCLContextMenuAction(title: "Test") { _ in }
        XCTAssertNil(action.systemImage)
        XCTAssertEqual(action.role, .default)
    }

    // MARK: - Attachment Delegate Defaults

    func testAttachmentDefaultValues() {
        #if canImport(UIKit)
        XCTAssertEqual(FCLAttachmentDefaults.mediaCompression, .default)
        XCTAssertTrue(FCLAttachmentDefaults.recentFiles.isEmpty)
        XCTAssertTrue(FCLAttachmentDefaults.customTabs.isEmpty)
        XCTAssertTrue(FCLAttachmentDefaults.isVideoEnabled)
        XCTAssertTrue(FCLAttachmentDefaults.isFileTabEnabled)
        #endif
    }

    // MARK: - Context Menu Delegate

    @MainActor
    func testContextMenuDelegateReceivesCorrectDirection() {
        let spy = FCLContextMenuDelegateSpy()
        let incoming = FCLChatMessage(text: "hi", direction: .incoming, sender: testIncomingSender)
        let outgoing = FCLChatMessage(text: "hello", direction: .outgoing, sender: testOutgoingSender)

        _ = spy.contextMenuActions(for: incoming, direction: .incoming)
        _ = spy.contextMenuActions(for: outgoing, direction: .outgoing)

        XCTAssertEqual(spy.receivedMessages.count, 2)
        XCTAssertEqual(spy.receivedMessages[0].1, .incoming)
        XCTAssertEqual(spy.receivedMessages[1].1, .outgoing)
    }
}
