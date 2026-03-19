import Foundation

/// A lightweight, immutable summary of a single chat conversation for display in a chat list.
///
/// `FCLChatSummary` provides the minimum data needed to render a row in the chat list UI,
/// including the conversation title, the most recent message preview, a timestamp, and an
/// unread message count. It conforms to `Identifiable`, `Hashable`, and `Sendable` so it
/// can be safely used across SwiftUI views and concurrent contexts.
public struct FCLChatSummary: Identifiable, Hashable, Sendable {
    /// The unique identifier for this chat conversation.
    public let id: UUID

    /// The identifier of the sender or participant associated with this chat.
    ///
    /// Used for avatar resolution and participant lookup in the chat list.
    public let senderID: String

    /// The display title of the conversation (e.g., contact name, group name, or channel name).
    public let title: String

    /// A text preview of the most recent message in the conversation.
    ///
    /// Displayed as secondary text beneath the title in each chat list row.
    public let lastMessage: String

    /// The date and time when the conversation was last updated.
    ///
    /// Typically reflects the timestamp of the most recent message; used for sorting
    /// and displaying a formatted time label in the chat list row.
    public let updatedAt: Date

    /// The number of unread messages in this conversation.
    ///
    /// When greater than zero, the chat list row renders a badge with this count.
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
