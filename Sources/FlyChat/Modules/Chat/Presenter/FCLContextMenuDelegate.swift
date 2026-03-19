import Foundation

/// Delegate that provides context menu actions for chat messages.
///
/// Implement this protocol to supply custom long-press actions (e.g. copy, delete, reply)
/// for individual messages in the chat timeline.
@MainActor
public protocol FCLContextMenuDelegate: AnyObject {
    /// Returns the context menu actions to display for the given message.
    /// - Parameters:
    ///   - message: The message that was long-pressed.
    ///   - direction: Whether the message is incoming or outgoing.
    /// - Returns: An array of context menu actions to present.
    func contextMenuActions(
        for message: FCLChatMessage,
        direction: FCLChatMessageDirection
    ) -> [FCLContextMenuAction]
}
