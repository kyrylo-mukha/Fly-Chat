import FlyChat
import Foundation

/// `ExampleSampleData` — static mock content shared by both style presets.
enum ExampleSampleData {
    static let currentUser = FCLChatMessageSender(id: "me", displayName: "You")

    private static let alice = FCLChatMessageSender(id: "alice", displayName: "Alice Doe")
    private static let bob = FCLChatMessageSender(id: "bob", displayName: "Bob Smith")
    private static let carol = FCLChatMessageSender(id: "carol", displayName: "Carol King")
    private static let dave = FCLChatMessageSender(id: "dave", displayName: "Dave Lee")

    private static let participants: [String: FCLChatMessageSender] = [
        alice.id: alice, bob.id: bob, carol.id: carol, dave.id: dave,
    ]

    /// The one-to-one "Alice Doe" conversation used by the auto-chat deep link.
    static let aliceChat = FCLChatSummary(
        senderID: alice.id, title: alice.displayName,
        lastMessage: "See you at 6 then!",
        updatedAt: Date().addingTimeInterval(-60 * 4), unreadCount: 2
    )

    static let chats: [FCLChatSummary] = [
        aliceChat,
        FCLChatSummary(
            senderID: bob.id, title: bob.displayName,
            lastMessage: "Pushed the fix, can you review?",
            updatedAt: Date().addingTimeInterval(-60 * 52), unreadCount: 0
        ),
        FCLChatSummary(
            senderID: carol.id, title: carol.displayName,
            lastMessage: "The photos look amazing 😍",
            updatedAt: Date().addingTimeInterval(-60 * 60 * 5), unreadCount: 1
        ),
        FCLChatSummary(
            senderID: dave.id, title: dave.displayName,
            lastMessage: "Thanks, that worked.",
            updatedAt: Date().addingTimeInterval(-60 * 60 * 26), unreadCount: 0
        ),
    ]

    static func messages(for chat: FCLChatSummary) -> [FCLChatMessage] {
        let other = participants[chat.senderID] ?? FCLChatMessageSender(
            id: chat.senderID, displayName: chat.title
        )
        return [
            FCLChatMessage(text: "Morning! Did you get a chance to look at the deck?", direction: .incoming, sender: other),
            FCLChatMessage(text: "Yeah, went through it last night. Slide 7 is 🔥", direction: .outgoing, sender: currentUser, status: .read),
            FCLChatMessage(text: "Right? I reworked the whole flow section.", direction: .incoming, sender: other),
            FCLChatMessage(text: "It reads so much cleaner now.", direction: .outgoing, sender: currentUser, status: .read),
            FCLChatMessage(text: "Hey! Are we still on for today?", direction: .incoming, sender: other),
            FCLChatMessage(text: "Absolutely. I just wrapped up the last task on my end.", direction: .outgoing, sender: currentUser, status: .read),
            FCLChatMessage(text: "Perfect. I was a little worried the deadline would slip, but this is great news.", direction: .incoming, sender: other),
            FCLChatMessage(text: "No slip. Want to grab a coffee and go over the details before the call?", direction: .outgoing, sender: currentUser, status: .read),
            FCLChatMessage(text: "Sounds good — the place on 5th?", direction: .incoming, sender: other),
            FCLChatMessage(text: "Perfect. I'll grab a table by the window.", direction: .outgoing, sender: currentUser, status: .read),
            FCLChatMessage(text: chat.lastMessage, direction: .incoming, sender: other),
        ]
    }
}
