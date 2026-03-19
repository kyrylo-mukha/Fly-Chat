import Combine
import Foundation

/// The presenter for the chat list module, responsible for holding the current list of
/// chat summaries and forwarding user interactions to the router.
///
/// `FCLChatListPresenter` follows the MVP pattern: the view observes its published
/// `chats` array, and user actions (e.g., tapping a chat row) are forwarded through
/// the presenter to the injected ``FCLChatListRouting`` router.
///
/// This class is `@MainActor`-isolated because it drives SwiftUI view updates.
@MainActor
public final class FCLChatListPresenter: ObservableObject {
    /// The current list of chat summaries displayed in the chat list.
    ///
    /// Published so that SwiftUI views automatically re-render when the array changes.
    @Published public private(set) var chats: [FCLChatSummary]

    /// The router responsible for handling navigation actions originating from the chat list.
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
    /// Internally wraps the closure in an ``FCLChatListActionRouter``.
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
    /// Forwards the selection to the router so it can perform the appropriate navigation.
    ///
    /// - Parameter chat: The chat summary that was tapped.
    public func didTapChat(_ chat: FCLChatSummary) {
        router?.openChat(chat)
    }
}
