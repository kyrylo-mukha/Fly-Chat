import Foundation
#if canImport(UIKit)
import UIKit
#endif

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

#if canImport(UIKit)
/// Carries the optional preview source used by ``FCLMediaPreviewView`` to anchor its
/// zoom-in / zoom-out dismiss animation. The chat screen populates this at construction
/// time and hands it to the preview; downstream tasks attach a concrete source-adopting
/// view that reports attachment-cell frames in window coordinates.
@MainActor
public final class FCLChatMediaPreviewRouter {
    /// The source queried for attachment cell frames on dismiss, or `nil` to fall back
    /// to a centered collapse animation.
    public weak var source: (any FCLMediaPreviewSource)?

    /// Creates a new router with an optional starting source.
    /// - Parameter source: The source adopter used to locate attachment cell frames.
    public init(source: (any FCLMediaPreviewSource)? = nil) {
        self.source = source
    }
}
#endif
