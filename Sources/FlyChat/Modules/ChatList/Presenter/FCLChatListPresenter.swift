import Combine
import Foundation

/// Presenter for the chat list module; holds the current summaries and forwards interactions to the router.
@MainActor
public final class FCLChatListPresenter: ObservableObject {
    /// The current list of chat summaries displayed in the chat list.
    @Published public private(set) var chats: [FCLChatSummary]

    private let router: (any FCLChatListRouting)?

    /// Creates a presenter with an explicit router for navigation.
    ///
    /// - Parameters:
    ///   - chats: The initial array of chat summaries to display.
    ///   - router: An optional router conforming to ``FCLChatListRouting`` that handles
    ///     navigation when the user selects a chat. Pass `nil` to disable navigation.
    public init(chats: [FCLChatSummary], router: (any FCLChatListRouting)? = nil) {
        self.chats = chats
        self.router = router
    }

    /// Creates a presenter with a closure-based tap handler for convenience.
    ///
    /// - Parameters:
    ///   - chats: The initial array of chat summaries to display.
    ///   - onChatTap: An optional closure invoked when the user taps a chat row.
    ///     Pass `nil` to disable tap handling.
    public convenience init(chats: [FCLChatSummary], onChatTap: ((FCLChatSummary) -> Void)?) {
        if let onChatTap {
            self.init(chats: chats, router: FCLChatListActionRouter(onOpenChat: onChatTap))
        } else {
            self.init(chats: chats, router: nil)
        }
    }

    /// Notifies the presenter that the user tapped a specific chat row.
    ///
    /// - Parameter chat: The chat summary that was tapped.
    public func didTapChat(_ chat: FCLChatSummary) {
        router?.openChat(chat)
    }
}
