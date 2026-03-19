import Foundation

/// Identifies a chat participant with a unique identifier and a human-readable display name.
public struct FCLChatMessageSender: Sendable, Hashable {
    /// A unique, stable identifier for the sender (e.g. a user ID from the backend).
    public let id: String
    /// The human-readable name shown in the chat UI for this sender.
    public let displayName: String

    /// Creates a new message sender.
    /// - Parameters:
    ///   - id: A unique, stable identifier for the sender.
    ///   - displayName: The human-readable name shown in the chat UI.
    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
