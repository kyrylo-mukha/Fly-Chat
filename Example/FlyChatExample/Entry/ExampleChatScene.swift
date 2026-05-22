import FlyChat
import UIKit

/// `ExampleChatScene` — builds a fully-chromed chat controller from a chat summary.
///
/// Centralizes the bridge call and the host glass navigation chrome so the entry flow and the
/// deep-link path produce an identical Liquid Glass chat screen.
enum ExampleChatScene {

    /// Builds a chat controller for the given summary, themed by `delegate` and wrapped in the
    /// host glass navigation chrome (transparent bar, centered title, floating glass back button).
    /// - Parameters:
    ///   - summary: The conversation to open.
    ///   - delegate: The style preset that themes bubbles, layout, and input chrome.
    ///   - onBack: The action invoked when the floating glass back button is tapped.
    /// - Returns: A pushable `UIViewController` hosting the chat with host-owned navigation chrome.
    @MainActor
    static func makeChatViewController(
        for summary: FCLChatSummary,
        delegate: ExampleChatDelegate,
        onBack: @escaping () -> Void
    ) -> UIViewController {
        let chatVC = FCLUIKitBridge.makeChatViewController(
            messages: ExampleSampleData.messages(for: summary),
            title: summary.title,
            currentUser: ExampleSampleData.currentUser,
            onSendMessage: { print("Sent:", $0.text) },
            onDeleteMessage: { print("Deleted:", $0.id) },
            delegate: delegate,
            contextMenuDelegate: nil
        )
        ExampleGlassNavigation.applyChatChrome(to: chatVC, title: summary.title, onBack: onBack)
        return chatVC
    }
}
