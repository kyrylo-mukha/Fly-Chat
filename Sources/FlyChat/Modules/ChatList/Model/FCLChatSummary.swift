import Foundation

/// A lightweight, immutable summary of a single chat conversation for display in a chat list.
///
/// Provides the minimum data needed to render a row: title, last message preview, timestamp, and unread count.
public struct FCLChatSummary: Identifiable, Hashable, Sendable {
    public let id: UUID

    /// The identifier of the sender or participant associated with this chat.
    ///
    /// Used for avatar resolution and participant lookup in the chat list.
    public let senderID: String

    /// The display title of the conversation (e.g., contact name, group name, or channel name).
    public let title: String

    /// A text preview of the most recent message in the conversation.
    public let lastMessage: String

    /// The date and time when the conversation was last updated; used for sorting and display.
    public let updatedAt: Date

    /// The number of unread messages in this conversation.
    public let unreadCount: Int

    /// Creates a new chat summary.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for the chat. Defaults to a new `UUID`.
    ///   - senderID: The identifier of the sender or primary participant.
    ///   - title: The display title for the conversation.
    ///   - lastMessage: A text preview of the most recent message.
    ///   - updatedAt: The date when the conversation was last updated.
    ///   - unreadCount: The number of unread messages. Defaults to `0`.
    public init(
        id: UUID = UUID(),
        senderID: String,
        title: String,
        lastMessage: String,
        updatedAt: Date,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.senderID = senderID
        self.title = title
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
        self.unreadCount = unreadCount
    }
}
