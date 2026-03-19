import Foundation

/// Indicates whether a chat message is received from another user or sent by the current user.
public enum FCLChatMessageDirection: String, Sendable, Hashable {
    /// A message received from another participant.
    case incoming
    /// A message sent by the current user.
    case outgoing
}

/// A single chat message within a conversation, containing text, optional attachments, and sender metadata.
public struct FCLChatMessage: Identifiable, Hashable, Sendable {
    /// Unique identifier for the message.
    public let id: UUID
    /// The plain-text body of the message.
    public let text: String
    /// Whether this message is incoming or outgoing relative to the current user.
    public let direction: FCLChatMessageDirection
    /// The timestamp when the message was sent.
    public let sentAt: Date
    /// Media or file attachments included with this message.
    public let attachments: [FCLAttachment]
    /// The user who authored this message.
    public let sender: FCLChatMessageSender

    /// Creates a new chat message.
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - text: The plain-text body of the message.
    ///   - direction: Whether the message is incoming or outgoing.
    ///   - sentAt: The timestamp when the message was sent. Defaults to the current date.
    ///   - attachments: Media or file attachments. Defaults to an empty array.
    ///   - sender: The user who authored this message.
    public init(
        id: UUID = UUID(),
        text: String,
        direction: FCLChatMessageDirection,
        sentAt: Date = Date(),
        attachments: [FCLAttachment] = [],
        sender: FCLChatMessageSender
    ) {
        self.id = id
        self.text = text
        self.direction = direction
        self.sentAt = sentAt
        self.attachments = attachments
        self.sender = sender
    }
}
