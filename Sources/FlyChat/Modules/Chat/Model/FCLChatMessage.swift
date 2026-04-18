import Foundation

/// Indicates whether a chat message is received from another user or sent by the current user.
public enum FCLChatMessageDirection: String, Sendable, Hashable {
    /// A message received from another participant.
    case incoming
    /// A message sent by the current user.
    case outgoing
}

/// Delivery status of a chat message, used to render a compact status indicator inside the bubble.
///
/// Assign this value to ``FCLChatMessage/status`` to show a status glyph next to the timestamp.
/// A `nil` status hides the indicator entirely.
public enum FCLChatMessageStatus: String, Sendable, Hashable {
    /// The message has been created locally but not yet confirmed by the server.
    case created
    /// The message has been sent and confirmed by the server.
    case sent
    /// The message has been read by the recipient.
    case read
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
    /// Optional delivery status shown as a compact glyph next to the timestamp.
    ///
    /// When `nil`, no status indicator is rendered and no additional width is reserved.
    /// The status indicator is only rendered for outgoing messages (subject to
    /// `FCLLayoutDelegate.showsStatusForOutgoing`); it is always hidden for incoming messages.
    public let status: FCLChatMessageStatus?

    /// Creates a new chat message.
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - text: The plain-text body of the message.
    ///   - direction: Whether the message is incoming or outgoing.
    ///   - sentAt: The timestamp when the message was sent. Defaults to the current date.
    ///   - attachments: Media or file attachments. Defaults to an empty array.
    ///   - sender: The user who authored this message.
    ///   - status: Optional delivery status indicator. Defaults to `nil` (hidden).
    public init(
        id: UUID = UUID(),
        text: String,
        direction: FCLChatMessageDirection,
        sentAt: Date = Date(),
        attachments: [FCLAttachment] = [],
        sender: FCLChatMessageSender,
        status: FCLChatMessageStatus? = nil
    ) {
        self.id = id
        self.text = text
        self.direction = direction
        self.sentAt = sentAt
        self.attachments = attachments
        self.sender = sender
        self.status = status
    }
}
