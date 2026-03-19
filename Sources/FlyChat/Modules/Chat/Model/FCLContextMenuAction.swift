import Foundation

/// Defines the visual role of a context menu action.
public enum FCLContextMenuActionRole: Sendable, Equatable {
    /// Standard appearance.
    case `default`
    /// Destructive appearance (typically red).
    case destructive
}

/// A single action shown in a message context menu.
public struct FCLContextMenuAction: Sendable {
    /// The localized title displayed for the action.
    public let title: String
    /// An optional SF Symbol name rendered alongside the title.
    public let systemImage: String?
    /// The visual role that determines styling (default or destructive).
    public let role: FCLContextMenuActionRole
    /// The closure invoked when the user selects this action, receiving the targeted message.
    public let handler: @Sendable (FCLChatMessage) -> Void

    /// Creates a new context menu action.
    /// - Parameters:
    ///   - title: The localized title displayed for the action.
    ///   - systemImage: An optional SF Symbol name to render alongside the title. Defaults to `nil`.
    ///   - role: The visual role (default or destructive). Defaults to `.default`.
    ///   - handler: A closure invoked when the user selects this action, receiving the targeted message.
    public init(
        title: String,
        systemImage: String? = nil,
        role: FCLContextMenuActionRole = .default,
        handler: @escaping @Sendable (FCLChatMessage) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.handler = handler
    }
}
