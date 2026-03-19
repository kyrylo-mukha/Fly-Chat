import XCTest
@testable import FlyChat

final class FCLChatModuleTests: XCTestCase {

    // MARK: - Presenter

    @MainActor
    func testChatPresenterSendDraftCreatesOutgoingMessageAndClearsDraft() {
        let router = FCLChatRouterSpy()
        let presenter = FCLChatPresenter(messages: [], draftText: "Hello", currentUser: testOutgoingSender, router: router)

        presenter.sendDraft()

        XCTAssertEqual(presenter.messages.count, 1)
        XCTAssertEqual(presenter.messages.first?.text, "Hello")
        XCTAssertEqual(presenter.messages.first?.direction, .outgoing)
        XCTAssertTrue(presenter.draftText.isEmpty)
        XCTAssertEqual(router.sentMessageIDs.count, 1)
    }

    @MainActor
    func testChatPresenterDeleteMessageRemovesItAndRoutesAction() {
        let router = FCLChatRouterSpy()
        let message = FCLChatMessage(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            text: "Delete me",
            direction: .incoming,
            sender: testIncomingSender
        )
        let presenter = FCLChatPresenter(messages: [message], draftText: "", currentUser: testOutgoingSender, router: router)

        presenter.deleteMessage(message)

        XCTAssertTrue(presenter.messages.isEmpty)
        XCTAssertEqual(router.deletedMessageIDs, [message.id])
    }

    // MARK: - Delegate Resolution

    @MainActor
    func testPresenterUsesDefaultsWhenNoDelegate() {
        let sender = FCLChatMessageSender(id: "u1", displayName: "User")
        let presenter = FCLChatPresenter(messages: [], currentUser: sender)
        XCTAssertEqual(presenter.resolvedIncomingSide, .left)
        XCTAssertEqual(presenter.resolvedOutgoingSide, .right)
        XCTAssertEqual(presenter.resolvedMaxBubbleWidthRatio, 0.78)
        XCTAssertEqual(presenter.resolvedIntraGroupSpacing, 4)
        XCTAssertEqual(presenter.resolvedInterGroupSpacing, 12)
    }

    @MainActor
    func testPresenterUsesCustomDelegate() {
        let sender = FCLChatMessageSender(id: "u1", displayName: "User")
        let customDelegate = TestChatDelegate()
        let presenter = FCLChatPresenter(messages: [], currentUser: sender, delegate: customDelegate)
        XCTAssertEqual(presenter.resolvedIncomingSide, .right)
    }

    // MARK: - Tail Grouping

    @MainActor
    func testTailGroupingEdgedBottomLastMessageGetsEdged() {
        let m1 = FCLChatMessage(text: "a", direction: .outgoing, sentAt: Date().addingTimeInterval(-3), sender: testOutgoingSender)
        let m2 = FCLChatMessage(text: "b", direction: .outgoing, sentAt: Date().addingTimeInterval(-2), sender: testOutgoingSender)
        let m3 = FCLChatMessage(text: "c", direction: .outgoing, sentAt: Date().addingTimeInterval(-1), sender: testOutgoingSender)
        let presenter = FCLChatPresenter(messages: [m1, m2, m3], currentUser: testOutgoingSender)

        XCTAssertEqual(presenter.tailStyle(for: m1, configStyle: .edged(.bottom)), .none)
        XCTAssertEqual(presenter.tailStyle(for: m2, configStyle: .edged(.bottom)), .none)
        XCTAssertEqual(presenter.tailStyle(for: m3, configStyle: .edged(.bottom)), .edged(.bottom))
    }

    @MainActor
    func testTailGroupingEdgedTopFirstMessageGetsEdged() {
        let m1 = FCLChatMessage(text: "a", direction: .outgoing, sentAt: Date().addingTimeInterval(-3), sender: testOutgoingSender)
        let m2 = FCLChatMessage(text: "b", direction: .outgoing, sentAt: Date().addingTimeInterval(-2), sender: testOutgoingSender)
        let m3 = FCLChatMessage(text: "c", direction: .outgoing, sentAt: Date().addingTimeInterval(-1), sender: testOutgoingSender)
        let presenter = FCLChatPresenter(messages: [m1, m2, m3], currentUser: testOutgoingSender)

        XCTAssertEqual(presenter.tailStyle(for: m1, configStyle: .edged(.top)), .edged(.top))
        XCTAssertEqual(presenter.tailStyle(for: m2, configStyle: .edged(.top)), .none)
        XCTAssertEqual(presenter.tailStyle(for: m3, configStyle: .edged(.top)), .none)
    }

    @MainActor
    func testTailGroupingNoneAllMessagesGetNone() {
        let m1 = FCLChatMessage(text: "a", direction: .outgoing, sender: testOutgoingSender)
        let m2 = FCLChatMessage(text: "b", direction: .incoming, sender: testIncomingSender)
        let presenter = FCLChatPresenter(messages: [m1, m2], currentUser: testOutgoingSender)

        XCTAssertEqual(presenter.tailStyle(for: m1, configStyle: .none), .none)
        XCTAssertEqual(presenter.tailStyle(for: m2, configStyle: .none), .none)
    }

    @MainActor
    func testTailGroupingSingleMessageGetsEdged() {
        let m1 = FCLChatMessage(text: "only", direction: .outgoing, sender: testOutgoingSender)
        let presenter = FCLChatPresenter(messages: [m1], currentUser: testOutgoingSender)

        XCTAssertEqual(presenter.tailStyle(for: m1, configStyle: .edged(.bottom)), .edged(.bottom))
        XCTAssertEqual(presenter.tailStyle(for: m1, configStyle: .edged(.top)), .edged(.top))
    }

    @MainActor
    func testTailGroupingMixedDirections() {
        let m1 = FCLChatMessage(text: "a", direction: .outgoing, sentAt: Date().addingTimeInterval(-4), sender: testOutgoingSender)
        let m2 = FCLChatMessage(text: "b", direction: .outgoing, sentAt: Date().addingTimeInterval(-3), sender: testOutgoingSender)
        let m3 = FCLChatMessage(text: "c", direction: .incoming, sentAt: Date().addingTimeInterval(-2), sender: testIncomingSender)
        let m4 = FCLChatMessage(text: "d", direction: .incoming, sentAt: Date().addingTimeInterval(-1), sender: testIncomingSender)
        let presenter = FCLChatPresenter(messages: [m1, m2, m3, m4], currentUser: testOutgoingSender)

        // edged(.bottom): last in each group
        XCTAssertEqual(presenter.tailStyle(for: m1, configStyle: .edged(.bottom)), .none)
        XCTAssertEqual(presenter.tailStyle(for: m2, configStyle: .edged(.bottom)), .edged(.bottom))
        XCTAssertEqual(presenter.tailStyle(for: m3, configStyle: .edged(.bottom)), .none)
        XCTAssertEqual(presenter.tailStyle(for: m4, configStyle: .edged(.bottom)), .edged(.bottom))

        // edged(.top): first in each group
        XCTAssertEqual(presenter.tailStyle(for: m1, configStyle: .edged(.top)), .edged(.top))
        XCTAssertEqual(presenter.tailStyle(for: m2, configStyle: .edged(.top)), .none)
        XCTAssertEqual(presenter.tailStyle(for: m3, configStyle: .edged(.top)), .edged(.top))
        XCTAssertEqual(presenter.tailStyle(for: m4, configStyle: .edged(.top)), .none)
    }

    @MainActor
    func testTailGroupingRecalculatesAfterDeletion() {
        let m1 = FCLChatMessage(text: "a", direction: .outgoing, sentAt: Date().addingTimeInterval(-3), sender: testOutgoingSender)
        let m2 = FCLChatMessage(text: "b", direction: .outgoing, sentAt: Date().addingTimeInterval(-2), sender: testOutgoingSender)
        let m3 = FCLChatMessage(text: "c", direction: .outgoing, sentAt: Date().addingTimeInterval(-1), sender: testOutgoingSender)
        let presenter = FCLChatPresenter(messages: [m1, m2, m3], currentUser: testOutgoingSender)

        XCTAssertEqual(presenter.tailStyle(for: m2, configStyle: .edged(.bottom)), .none)
        XCTAssertEqual(presenter.tailStyle(for: m3, configStyle: .edged(.bottom)), .edged(.bottom))

        presenter.deleteMessage(m3)
        XCTAssertEqual(presenter.tailStyle(for: m2, configStyle: .edged(.bottom)), .edged(.bottom))
    }

    // MARK: - Spacing

    @MainActor
    func testPresenterSpacingAfterSameGroup() {
        let s = FCLChatMessageSender(id: "u1", displayName: "A")
        let m1 = FCLChatMessage(text: "a", direction: .outgoing, sentAt: Date().addingTimeInterval(-2), sender: s)
        let m2 = FCLChatMessage(text: "b", direction: .outgoing, sentAt: Date().addingTimeInterval(-1), sender: s)
        let presenter = FCLChatPresenter(messages: [m1, m2], currentUser: s)

        XCTAssertEqual(presenter.spacing(after: m1), presenter.resolvedIntraGroupSpacing)
        XCTAssertEqual(presenter.spacing(after: m2), 0) // last message, no spacing after
    }

    @MainActor
    func testPresenterSpacingBetweenGroups() {
        let s1 = FCLChatMessageSender(id: "u1", displayName: "A")
        let s2 = FCLChatMessageSender(id: "u2", displayName: "B")
        let m1 = FCLChatMessage(text: "a", direction: .outgoing, sentAt: Date().addingTimeInterval(-2), sender: s1)
        let m2 = FCLChatMessage(text: "b", direction: .incoming, sentAt: Date().addingTimeInterval(-1), sender: s2)
        let presenter = FCLChatPresenter(messages: [m1, m2], currentUser: s1)

        XCTAssertEqual(presenter.spacing(after: m1), presenter.resolvedInterGroupSpacing)
    }

    // MARK: - Context Menu (Presenter)

    @MainActor
    func testPresenterContextMenuActionsFromDelegate() {
        let spy = FCLContextMenuDelegateSpy()
        let copyAction = FCLContextMenuAction(title: "Copy") { _ in }
        spy.returnedActions = [copyAction]

        let message = FCLChatMessage(text: "test", direction: .outgoing, sender: testOutgoingSender)
        let presenter = FCLChatPresenter(
            messages: [message],
            currentUser: testOutgoingSender,
            contextMenuDelegate: spy
        )

        let actions = presenter.contextMenuActions(for: message)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.title, "Copy")
        XCTAssertEqual(spy.receivedMessages.first?.1, .outgoing)
    }

    @MainActor
    func testPresenterContextMenuActionsEmptyWithoutDelegate() {
        let message = FCLChatMessage(text: "test", direction: .outgoing, sender: testOutgoingSender)
        let presenter = FCLChatPresenter(messages: [message], currentUser: testOutgoingSender)

        let actions = presenter.contextMenuActions(for: message)
        XCTAssertTrue(actions.isEmpty)
    }

    @MainActor
    func testPresenterContextMenuDelegateReceivesIncomingDirection() {
        let spy = FCLContextMenuDelegateSpy()
        spy.returnedActions = []

        let message = FCLChatMessage(text: "hi", direction: .incoming, sender: testIncomingSender)
        let presenter = FCLChatPresenter(
            messages: [message],
            currentUser: testOutgoingSender,
            contextMenuDelegate: spy
        )

        _ = presenter.contextMenuActions(for: message)
        XCTAssertEqual(spy.receivedMessages.first?.1, .incoming)
    }

    // MARK: - Message Model

    func testChatMessageRequiresSender() {
        let sender = FCLChatMessageSender(id: "user-1", displayName: "John")
        let message = FCLChatMessage(text: "Hi", direction: .outgoing, sender: sender)
        XCTAssertEqual(message.sender.id, "user-1")
        XCTAssertEqual(message.sender.displayName, "John")
    }

    func testChatMessageDefaultAttachmentsIsEmpty() {
        let message = FCLChatMessage(text: "Hello", direction: .outgoing, sender: testOutgoingSender)
        XCTAssertTrue(message.attachments.isEmpty)
    }

    func testChatMessageWithAttachments() {
        let attachment = FCLAttachment(type: .file, url: URL(string: "file:///tmp/doc.pdf")!, fileName: "doc.pdf")
        let message = FCLChatMessage(text: "See attached", direction: .outgoing, attachments: [attachment], sender: testOutgoingSender)

        XCTAssertEqual(message.attachments.count, 1)
        XCTAssertEqual(message.attachments.first?.fileName, "doc.pdf")
    }

    // MARK: - Attachment Model

    func testAttachmentStoresProvidedValues() {
        let url = URL(string: "file:///tmp/test.jpg")!
        let attachment = FCLAttachment(
            type: .image,
            url: url,
            thumbnailData: Data([0xFF]),
            fileName: "test.jpg"
        )

        XCTAssertEqual(attachment.type, .image)
        XCTAssertEqual(attachment.url, url)
        XCTAssertEqual(attachment.thumbnailData, Data([0xFF]))
        XCTAssertEqual(attachment.fileName, "test.jpg")
    }

    func testAttachmentFileSizeDefaultsToNil() {
        let attachment = FCLAttachment(type: .file, url: URL(string: "file:///tmp/a.pdf")!, fileName: "a.pdf")
        XCTAssertNil(attachment.fileSize)
    }

    func testAttachmentStoresFileSize() {
        let attachment = FCLAttachment(type: .file, url: URL(string: "file:///tmp/a.pdf")!, fileName: "a.pdf", fileSize: 1024)
        XCTAssertEqual(attachment.fileSize, 1024)
    }
}
