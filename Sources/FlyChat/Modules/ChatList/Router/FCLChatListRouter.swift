import Foundation

/// A protocol defining the navigation contract for the chat list module.
///
/// Conform to this protocol to provide custom navigation behavior when the user
/// selects a chat from the list. The presenter delegates all navigation through
/// an instance of this protocol.
public protocol FCLChatListRouting {
    /// Navigates to the selected chat conversation.
    ///
    /// - Parameter chat: The chat summary the user selected from the list.
    func openChat(_ chat: FCLChatSummary)
}

/// A closure-based router that forwards chat selection events to a callback.
///
/// This is a convenience implementation of ``FCLChatListRouting`` that wraps a
/// simple closure, making it easy for host apps to handle navigation without
/// creating a dedicated router type.
public final class FCLChatListActionRouter: FCLChatListRouting {
    /// The closure invoked when a chat is selected.
    private let onOpenChat: (FCLChatSummary) -> Void

    /// Creates a new action router with the given callback.
    ///
    /// - Parameter onOpenChat: A closure called when the user taps a chat row,
    ///   receiving the selected ``FCLChatSummary``.
    public init(onOpenChat: @escaping (FCLChatSummary) -> Void) {
        self.onOpenChat = onOpenChat
    }

    /// Forwards the chat selection to the stored closure.
    ///
    /// - Parameter chat: The chat summary the user selected.
    public func openChat(_ chat: FCLChatSummary) {
        onOpenChat(chat)
    }
}
