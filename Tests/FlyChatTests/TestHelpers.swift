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

// MARK: - Delegate Test Spies

@MainActor
final class TestChatDelegate: FCLChatDelegate {
    var appearance: (any FCLAppearanceDelegate)? { nil }
    var avatar: (any FCLAvatarDelegate)? { nil }
    var layout: (any FCLLayoutDelegate)? { TestLayoutDelegate() }
    var input: (any FCLInputDelegate)? { nil }
    #if canImport(UIKit)
    var attachment: (any FCLAttachmentDelegate)? { nil }
    #endif
}

@MainActor
final class TestLayoutDelegate: FCLLayoutDelegate {
    var incomingSide: FCLChatBubbleSide { .right }
}

#if canImport(UIKit)
@MainActor
final class TestAttachmentDelegate: FCLAttachmentDelegate {
    var fileTabEnabled = true
    var videoEnabled = true
    var isFileTabEnabled: Bool { fileTabEnabled }
    var isVideoEnabled: Bool { videoEnabled }
}
#endif

/// An `FCLAppearanceDelegate` that relies entirely on protocol defaults, used to verify
/// that the default property values match the expected constants.
@MainActor
final class TestAppearanceDelegateDefault: FCLAppearanceDelegate {}

/// An `FCLLayoutDelegate` that relies entirely on protocol defaults, used to verify
/// that the default property values match the expected constants.
@MainActor
final class TestLayoutDelegateDefault: FCLLayoutDelegate {}

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
