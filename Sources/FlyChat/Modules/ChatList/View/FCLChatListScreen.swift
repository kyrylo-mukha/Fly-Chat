import Foundation
import SwiftUI

/// The main chat list screen that displays a scrollable list of conversation summaries.
///
/// `FCLChatListScreen` observes an ``FCLChatListPresenter`` and renders each chat summary
/// as a tappable row. When the chat list is empty, an informational empty-state placeholder
/// is shown instead.
///
/// The screen delegates user interactions (e.g., row taps) to the presenter, which in turn
/// routes them through the configured ``FCLChatListRouting`` implementation.
public struct FCLChatListScreen: View {
    /// The presenter that provides the chat data and handles user interactions.
    @ObservedObject private var presenter: FCLChatListPresenter

    /// An optional delegate for customizing chat UI elements such as avatars.
    private let delegate: (any FCLChatDelegate)?

    /// Creates a new chat list screen.
    ///
    /// - Parameters:
    ///   - presenter: The presenter that owns the chat list data and handles tap events.
    ///   - delegate: An optional delegate for customizing visual elements like avatars.
    ///     Defaults to `nil`.
    public init(presenter: FCLChatListPresenter, delegate: (any FCLChatDelegate)? = nil) {
        self.presenter = presenter
        self.delegate = delegate
    }

    public var body: some View {
        Group {
            if presenter.chats.isEmpty {
                emptyState
            } else {
                chatList
            }
        }
    }

    private var chatList: some View {
        List(presenter.chats) { chat in
            Button(action: { presenter.didTapChat(chat) }) {
                FCLChatRow(chat: chat, avatarDelegate: delegate?.avatar)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .listStyle(PlainListStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No chats yet")
                .font(.headline)
            Text("Start a conversation to see it here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
    }
}

private struct FCLChatRow: View {
    let chat: FCLChatSummary
    let avatarDelegate: (any FCLAvatarDelegate)?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            #if canImport(UIKit)
            FCLAvatarView(
                senderID: chat.senderID,
                displayName: chat.title,
                size: 44,
                delegate: avatarDelegate
            )
            #else
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(chat.title.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.blue)
                )
            #endif

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(Self.timeFormatter.string(from: chat.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(chat.lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

#if DEBUG
struct FCLChatListScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FCLChatListScreen(
                presenter: FCLChatListPresenter(
                    chats: [
                        FCLChatSummary(
                            senderID: "preview-sender",
                            title: "General",
                            lastMessage: "Hello team",
                            updatedAt: Date(),
                            unreadCount: 2
                        ),
                        FCLChatSummary(
                            senderID: "preview-sender",
                            title: "Support",
                            lastMessage: "How can we help?",
                            updatedAt: Date().addingTimeInterval(-300),
                            unreadCount: 0
                        ),
                    ],
                    onChatTap: nil
                )
            )
            .previewDisplayName("List")

            FCLChatListScreen(presenter: FCLChatListPresenter(chats: [], onChatTap: nil))
                .previewDisplayName("Empty")
        }
    }
}

private struct FCLChatRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FCLChatRow(
                chat: FCLChatSummary(
                    senderID: "preview-sender",
                    title: "Product",
                    lastMessage: "Let's ship this release today.",
                    updatedAt: Date(),
                    unreadCount: 4
                ),
                avatarDelegate: nil
            )
            .previewDisplayName("Unread")

            FCLChatRow(
                chat: FCLChatSummary(
                    senderID: "preview-sender",
                    title: "Design",
                    lastMessage: "Updated mocks are ready.",
                    updatedAt: Date().addingTimeInterval(-900),
                    unreadCount: 0
                ),
                avatarDelegate: nil
            )
            .previewDisplayName("Read")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
