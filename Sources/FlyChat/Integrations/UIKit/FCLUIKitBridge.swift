#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

/// A namespace providing factory and embedding methods that bridge FlyChat's SwiftUI screens
/// into UIKit-based host applications.
///
/// Use `FCLUIKitBridge` when your host app is built with UIKit and you need to present
/// FlyChat screens as `UIViewController` instances -- either pushed onto a navigation stack
/// or embedded as a child view controller inside a container view.
///
/// All methods are `@MainActor`-isolated and must be called from the main thread.
public enum FCLUIKitBridge {
    /// Creates a standalone `UIViewController` that displays the chat list screen.
    ///
    /// The returned controller wraps an ``FCLChatListScreen`` in a `UIHostingController`
    /// and is ready to be pushed onto a `UINavigationController` or presented modally.
    ///
    /// - Parameters:
    ///   - chats: The initial array of chat summaries to display.
    ///   - title: The navigation bar title for the view controller. Defaults to `"Chats"`.
    ///   - onChatTap: An optional closure invoked when the user taps a chat row,
    ///     receiving the selected ``FCLChatSummary``.
    ///   - delegate: An optional delegate for customizing visual elements such as avatars.
    /// - Returns: A `UIViewController` hosting the chat list SwiftUI screen.
    @MainActor
    public static func makeChatListViewController(
        chats: [FCLChatSummary],
        title: String = "Chats",
        onChatTap: ((FCLChatSummary) -> Void)? = nil,
        delegate: (any FCLChatDelegate)? = nil
    ) -> UIViewController {
        let presenter = FCLChatListPresenter(chats: chats, onChatTap: onChatTap)
        let rootView = FCLChatListScreen(presenter: presenter, delegate: delegate)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.title = title
        return hostingController
    }

    /// Creates a standalone `UIViewController` that displays a single chat conversation screen.
    ///
    /// The returned controller wraps an ``FCLChatScreen`` in a `UIHostingController`
    /// and is ready to be pushed onto a `UINavigationController` or presented modally.
    ///
    /// - Parameters:
    ///   - messages: The initial array of chat messages to display.
    ///   - title: The navigation bar title for the view controller. Defaults to `"Chat"`.
    ///   - currentUser: The sender identity representing the current (local) user.
    ///   - onSendMessage: An optional closure invoked when the user sends a new message.
    ///   - onDeleteMessage: An optional closure invoked when the user deletes a message.
    ///   - attachmentPickerDelegate: An optional delegate for handling attachment selection.
    ///   - delegate: An optional delegate for customizing visual elements such as avatars.
    ///   - contextMenuDelegate: An optional delegate for customizing long-press context menu actions.
    /// - Returns: A `UIViewController` hosting the chat conversation SwiftUI screen.
    @MainActor
    public static func makeChatViewController(
        messages: [FCLChatMessage],
        title: String = "Chat",
        currentUser: FCLChatMessageSender,
        onSendMessage: ((FCLChatMessage) -> Void)? = nil,
        onDeleteMessage: ((FCLChatMessage) -> Void)? = nil,
        attachmentPickerDelegate: (any FCLAttachmentPickerDelegate)? = nil,
        delegate: (any FCLChatDelegate)? = nil,
        contextMenuDelegate: (any FCLContextMenuDelegate)? = nil
    ) -> UIViewController {
        let presenter = FCLChatPresenter(
            messages: messages,
            currentUser: currentUser,
            onSendMessage: onSendMessage,
            onDeleteMessage: onDeleteMessage,
            attachmentPickerDelegate: attachmentPickerDelegate,
            delegate: delegate,
            contextMenuDelegate: contextMenuDelegate
        )
        let rootView = FCLChatScreen(presenter: presenter, delegate: delegate)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.title = title
        return hostingController
    }

    /// Embeds the chat list screen as a child view controller inside an existing UIKit container.
    ///
    /// This method performs full child-controller containment: it adds the hosting controller
    /// as a child of `parentViewController`, pins its view to the edges of `containerView`
    /// using Auto Layout constraints, and calls `didMove(toParent:)`.
    ///
    /// - Parameters:
    ///   - chats: The initial array of chat summaries to display.
    ///   - parentViewController: The UIKit view controller that will host the chat list
    ///     as a child.
    ///   - containerView: The view whose bounds define the layout area for the embedded
    ///     chat list.
    ///   - onChatTap: An optional closure invoked when the user taps a chat row.
    ///   - delegate: An optional delegate for customizing visual elements such as avatars.
    /// - Returns: The child `UIViewController` that was embedded, allowing the caller to
    ///   retain a reference for later removal or updates.
    @MainActor
    @discardableResult
    public static func embedChatList(
        chats: [FCLChatSummary],
        in parentViewController: UIViewController,
        containerView: UIView,
        onChatTap: ((FCLChatSummary) -> Void)? = nil,
        delegate: (any FCLChatDelegate)? = nil
    ) -> UIViewController {
        let presenter = FCLChatListPresenter(chats: chats, onChatTap: onChatTap)
        let rootView = FCLChatListScreen(presenter: presenter, delegate: delegate)
        let hostingController = UIHostingController(rootView: rootView)

        parentViewController.addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        hostingController.didMove(toParent: parentViewController)
        return hostingController
    }

    /// Embeds a chat conversation screen as a child view controller inside an existing UIKit container.
    ///
    /// This method performs full child-controller containment: it adds the hosting controller
    /// as a child of `parentViewController`, pins its view to the edges of `containerView`
    /// using Auto Layout constraints, and calls `didMove(toParent:)`.
    ///
    /// - Parameters:
    ///   - messages: The initial array of chat messages to display.
    ///   - parentViewController: The UIKit view controller that will host the chat screen
    ///     as a child.
    ///   - containerView: The view whose bounds define the layout area for the embedded
    ///     chat screen.
    ///   - currentUser: The sender identity representing the current (local) user.
    ///   - onSendMessage: An optional closure invoked when the user sends a new message.
    ///   - onDeleteMessage: An optional closure invoked when the user deletes a message.
    ///   - attachmentPickerDelegate: An optional delegate for handling attachment selection.
    ///   - delegate: An optional delegate for customizing visual elements such as avatars.
    ///   - contextMenuDelegate: An optional delegate for customizing long-press context menu actions.
    /// - Returns: The child `UIViewController` that was embedded, allowing the caller to
    ///   retain a reference for later removal or updates.
    @MainActor
    @discardableResult
    public static func embedChat(
        messages: [FCLChatMessage],
        in parentViewController: UIViewController,
        containerView: UIView,
        currentUser: FCLChatMessageSender,
        onSendMessage: ((FCLChatMessage) -> Void)? = nil,
        onDeleteMessage: ((FCLChatMessage) -> Void)? = nil,
        attachmentPickerDelegate: (any FCLAttachmentPickerDelegate)? = nil,
        delegate: (any FCLChatDelegate)? = nil,
        contextMenuDelegate: (any FCLContextMenuDelegate)? = nil
    ) -> UIViewController {
        let presenter = FCLChatPresenter(
            messages: messages,
            currentUser: currentUser,
            onSendMessage: onSendMessage,
            onDeleteMessage: onDeleteMessage,
            attachmentPickerDelegate: attachmentPickerDelegate,
            delegate: delegate,
            contextMenuDelegate: contextMenuDelegate
        )
        let rootView = FCLChatScreen(presenter: presenter, delegate: delegate)
        let hostingController = UIHostingController(rootView: rootView)

        parentViewController.addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        hostingController.didMove(toParent: parentViewController)
        return hostingController
    }
}
#endif
