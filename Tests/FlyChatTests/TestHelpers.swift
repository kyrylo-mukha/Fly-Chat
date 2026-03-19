import XCTest
@testable import FlyChat
#if canImport(UIKit)
import UIKit
#endif

let testOutgoingSender = FCLChatMessageSender(id: "test-outgoing", displayName: "Test User")
let testIncomingSender = FCLChatMessageSender(id: "test-incoming", displayName: "Other User")

// MARK: - Test Spies

final class FCLChatListRouterSpy: FCLChatListRouting {
    var openedChatIDs: [UUID] = []

    func openChat(_ chat: FCLChatSummary) {
        openedChatIDs.append(chat.id)
    }
}

final class FCLChatRouterSpy: FCLChatRouting {
    var sentMessageIDs: [UUID] = []
    var deletedMessageIDs: [UUID] = []

    func didSendMessage(_ message: FCLChatMessage) {
        sentMessageIDs.append(message.id)
    }

    func didDeleteMessage(_ message: FCLChatMessage) {
        deletedMessageIDs.append(message.id)
    }
}

#if canImport(UIKit)
final class FCLAttachmentPickerDelegateSpy: FCLAttachmentPickerDelegate {
    var presentPickerCalled = false

    func presentPicker(from viewController: UIViewController, completion: @escaping ([FCLAttachment]) -> Void) {
        presentPickerCalled = true
        completion([])
    }
}
#endif

// MARK: - Delegate Test Spies

@MainActor
final class TestChatDelegate: FCLChatDelegate {
    var appearance: (any FCLAppearanceDelegate)? { nil }
    var avatar: (any FCLAvatarDelegate)? { nil }
    var layout: (any FCLLayoutDelegate)? { TestLayoutDelegate() }
    var input: (any FCLInputDelegate)? { nil }
}

@MainActor
final class TestLayoutDelegate: FCLLayoutDelegate {
    var incomingSide: FCLChatBubbleSide { .right }
    // other properties use protocol defaults
}

@MainActor
final class FCLContextMenuDelegateSpy: FCLContextMenuDelegate {
    var returnedActions: [FCLContextMenuAction] = []
    var receivedMessages: [(FCLChatMessage, FCLChatMessageDirection)] = []

    func contextMenuActions(
        for message: FCLChatMessage,
        direction: FCLChatMessageDirection
    ) -> [FCLContextMenuAction] {
        receivedMessages.append((message, direction))
        return returnedActions
    }
}
