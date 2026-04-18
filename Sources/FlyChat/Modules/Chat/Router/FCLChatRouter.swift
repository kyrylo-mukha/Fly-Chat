import Foundation

/// Protocol defining routing callbacks for chat message lifecycle events.
///
/// Adopt this protocol to receive notifications when messages are sent or deleted,
/// enabling the host app to persist changes, sync with a backend, or trigger navigation.
public protocol FCLChatRouting {
    /// Called after a new message has been sent and added to the local message list.
    /// - Parameter message: The newly sent message.
    func didSendMessage(_ message: FCLChatMessage)
    /// Called after a message has been removed from the local message list.
    /// - Parameter message: The deleted message.
    func didDeleteMessage(_ message: FCLChatMessage)
}

/// A closure-based router that forwards send and delete events to optional callbacks.
///
/// Useful when the host app prefers simple closures over a full protocol conformance.
public final class FCLChatActionRouter: FCLChatRouting {
    /// Closure invoked when a message is sent, or `nil` to ignore.
    private let onSendMessage: ((FCLChatMessage) -> Void)?
    /// Closure invoked when a message is deleted, or `nil` to ignore.
    private let onDeleteMessage: ((FCLChatMessage) -> Void)?

    /// Creates a new action router with optional closure handlers.
    /// - Parameters:
    ///   - onSendMessage: Closure called when a message is sent. Defaults to `nil`.
    ///   - onDeleteMessage: Closure called when a message is deleted. Defaults to `nil`.
    public init(
        onSendMessage: ((FCLChatMessage) -> Void)? = nil,
        onDeleteMessage: ((FCLChatMessage) -> Void)? = nil
    ) {
        self.onSendMessage = onSendMessage
        self.onDeleteMessage = onDeleteMessage
    }

    /// Forwards the sent message to the `onSendMessage` closure, if set.
    /// - Parameter message: The newly sent message.
    public func didSendMessage(_ message: FCLChatMessage) {
        onSendMessage?(message)
    }

    /// Forwards the deleted message to the `onDeleteMessage` closure, if set.
    /// - Parameter message: The deleted message.
    public func didDeleteMessage(_ message: FCLChatMessage) {
        onDeleteMessage?(message)
    }
}

