import Combine
import Foundation
import SwiftUI

/// The main presenter for the chat module, managing message state, draft composition,
/// layout resolution, and user actions (send, delete, copy).
///
/// Conforms to `ObservableObject` so SwiftUI views can subscribe to `messages` and `draftText` changes.
@MainActor
public final class FCLChatPresenter: ObservableObject {
    /// The current list of messages in chronological (oldest-first) order.
    @Published public private(set) var messages: [FCLChatMessage]
    /// The text currently being composed by the user.
    @Published public var draftText: String
    /// The most recent send-path error, or `nil` when no error is active. Observed by the
    /// chat screen to display a lightweight toast.
    @Published public var lastSendError: String?

    /// The sender identity representing the current (local) user.
    public let currentUser: FCLChatMessageSender
    /// Optional delegate providing layout and appearance customization.
    public let delegate: (any FCLChatDelegate)?

    private let clipboard: any FCLChatClipboard
    /// Optional delegate that supplies context menu actions for individual messages.
    public private(set) weak var contextMenuDelegate: (any FCLContextMenuDelegate)?
    private let router: (any FCLChatRouting)?

    // MARK: - Frame Provider (UIKit)

    #if canImport(UIKit)
    /// Backing storage for `frameProvider`.
    var _frameProvider: ((UUID) -> CGRect?)?
    #endif

    // MARK: - Resolved Layout Helpers

    /// The resolved bubble side for incoming messages, falling back to the layout default.
    public var resolvedIncomingSide: FCLChatBubbleSide {
        delegate?.layout?.incomingSide ?? FCLLayoutDefaults.incomingSide
    }

    /// The resolved bubble side for outgoing messages, falling back to the layout default.
    public var resolvedOutgoingSide: FCLChatBubbleSide {
        delegate?.layout?.outgoingSide ?? FCLLayoutDefaults.outgoingSide
    }

    /// The resolved maximum bubble width as a fraction of screen width, clamped to `[0.55, 0.9]`.
    public var resolvedMaxBubbleWidthRatio: CGFloat {
        let ratio = delegate?.layout?.maxBubbleWidthRatio ?? FCLLayoutDefaults.maxBubbleWidthRatio
        return min(max(ratio, 0.55), 0.9)
    }

    /// The resolved vertical spacing between consecutive messages from the same sender.
    public var resolvedIntraGroupSpacing: CGFloat {
        delegate?.layout?.intraGroupSpacing ?? FCLLayoutDefaults.intraGroupSpacing
    }

    /// The resolved vertical spacing between message groups from different senders.
    public var resolvedInterGroupSpacing: CGFloat {
        delegate?.layout?.interGroupSpacing ?? FCLLayoutDefaults.interGroupSpacing
    }

    /// The resolved edge insets for the in-bubble attachment image grid.
    ///
    /// - Important: Deprecated. The inset is now fixed at ``FCLChatLayout/attachmentInset`` (1pt).
    ///   This property is retained for source compatibility only; the library ignores its value.
    @available(*, deprecated, message: "Attachment inset is now fixed at 1pt (FCLChatLayout.attachmentInset). This property is no longer used by the library.")
    public var resolvedAttachmentInsets: FCLEdgeInsets {
        delegate?.appearance?.attachmentInsets ?? FCLAppearanceDefaults.attachmentInsets
    }

    /// The resolved inter-cell spacing for the in-bubble attachment image grid.
    public var resolvedAttachmentItemSpacing: CGFloat {
        delegate?.appearance?.attachmentItemSpacing ?? FCLAppearanceDefaults.attachmentItemSpacing
    }

    #if canImport(UIKit)
    /// Creates a chat presenter with full dependency injection (UIKit).
    /// - Parameters:
    ///   - messages: The initial list of messages to display.
    ///   - draftText: Pre-filled draft text. Defaults to an empty string.
    ///   - currentUser: The sender identity for the local user.
    ///   - clipboard: The clipboard implementation for copy actions. Defaults to the system clipboard.
    ///   - router: An optional router to receive send/delete callbacks.
    ///   - delegate: An optional delegate providing layout and appearance customization.
    ///   - contextMenuDelegate: An optional delegate supplying context menu actions.
    public init(
        messages: [FCLChatMessage],
        draftText: String = "",
        currentUser: FCLChatMessageSender,
        clipboard: any FCLChatClipboard = FCLSystemChatClipboard(),
        router: (any FCLChatRouting)? = nil,
        delegate: (any FCLChatDelegate)? = nil,
        contextMenuDelegate: (any FCLContextMenuDelegate)? = nil
    ) {
        self.messages = messages
        self.draftText = draftText
        self.currentUser = currentUser
        self.clipboard = clipboard
        self.contextMenuDelegate = contextMenuDelegate
        self.router = router
        self.delegate = delegate
    }

    /// Convenience initializer using closure-based callbacks instead of a router (UIKit).
    /// - Parameters:
    ///   - messages: The initial list of messages to display.
    ///   - currentUser: The sender identity for the local user.
    ///   - onSendMessage: Closure called when a message is sent. Defaults to `nil`.
    ///   - onDeleteMessage: Closure called when a message is deleted. Defaults to `nil`.
    ///   - delegate: An optional delegate providing layout and appearance customization.
    ///   - contextMenuDelegate: An optional delegate supplying context menu actions.
    public convenience init(
        messages: [FCLChatMessage],
        currentUser: FCLChatMessageSender,
        onSendMessage: ((FCLChatMessage) -> Void)? = nil,
        onDeleteMessage: ((FCLChatMessage) -> Void)? = nil,
        delegate: (any FCLChatDelegate)? = nil,
        contextMenuDelegate: (any FCLContextMenuDelegate)? = nil
    ) {
        self.init(
            messages: messages,
            currentUser: currentUser,
            clipboard: FCLSystemChatClipboard(),
            router: FCLChatActionRouter(onSendMessage: onSendMessage, onDeleteMessage: onDeleteMessage),
            delegate: delegate,
            contextMenuDelegate: contextMenuDelegate
        )
    }
    #else
    /// Creates a chat presenter with full dependency injection (non-UIKit).
    /// - Parameters:
    ///   - messages: The initial list of messages to display.
    ///   - draftText: Pre-filled draft text. Defaults to an empty string.
    ///   - currentUser: The sender identity for the local user.
    ///   - clipboard: The clipboard implementation for copy actions. Defaults to the system clipboard.
    ///   - router: An optional router to receive send/delete callbacks.
    ///   - delegate: An optional delegate providing layout and appearance customization.
    ///   - contextMenuDelegate: An optional delegate supplying context menu actions.
    public init(
        messages: [FCLChatMessage],
        draftText: String = "",
        currentUser: FCLChatMessageSender,
        clipboard: any FCLChatClipboard = FCLSystemChatClipboard(),
        router: (any FCLChatRouting)? = nil,
        delegate: (any FCLChatDelegate)? = nil,
        contextMenuDelegate: (any FCLContextMenuDelegate)? = nil
    ) {
        self.messages = messages
        self.draftText = draftText
        self.currentUser = currentUser
        self.clipboard = clipboard
        self.contextMenuDelegate = contextMenuDelegate
        self.router = router
        self.delegate = delegate
    }

    /// Convenience initializer using closure-based callbacks instead of a router (non-UIKit).
    /// - Parameters:
    ///   - messages: The initial list of messages to display.
    ///   - currentUser: The sender identity for the local user.
    ///   - onSendMessage: Closure called when a message is sent. Defaults to `nil`.
    ///   - onDeleteMessage: Closure called when a message is deleted. Defaults to `nil`.
    ///   - delegate: An optional delegate providing layout and appearance customization.
    ///   - contextMenuDelegate: An optional delegate supplying context menu actions.
    public convenience init(
        messages: [FCLChatMessage],
        currentUser: FCLChatMessageSender,
        onSendMessage: ((FCLChatMessage) -> Void)? = nil,
        onDeleteMessage: ((FCLChatMessage) -> Void)? = nil,
        delegate: (any FCLChatDelegate)? = nil,
        contextMenuDelegate: (any FCLContextMenuDelegate)? = nil
    ) {
        self.init(
            messages: messages,
            currentUser: currentUser,
            clipboard: FCLSystemChatClipboard(),
            router: FCLChatActionRouter(onSendMessage: onSendMessage, onDeleteMessage: onDeleteMessage),
            delegate: delegate,
            contextMenuDelegate: contextMenuDelegate
        )
    }
    #endif

    /// The messages in reverse chronological order (newest first), suitable for bottom-anchored list rendering.
    public var renderedMessagesFromBottom: [FCLChatMessage] {
        Array(messages.reversed())
    }

    /// Returns the bubble side (left or right) for the given message based on its direction and layout config.
    /// - Parameter message: The message to determine placement for.
    /// - Returns: The resolved bubble side.
    public func side(for message: FCLChatMessage) -> FCLChatBubbleSide {
        message.direction == .outgoing ? resolvedOutgoingSide : resolvedIncomingSide
    }

    /// Determines whether the given message is the last in its sender group.
    ///
    /// A message is considered last in its group when the next message (in chronological order)
    /// has a different direction or when the message is the most recent overall.
    /// - Parameter message: The message to evaluate.
    /// - Returns: `true` if the message is the last in its sender group.
    public func isLastInGroup(for message: FCLChatMessage) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return true }
        return index == messages.count - 1 || messages[index + 1].direction != message.direction
    }

    /// Resolves the tail style for a message based on its position within a sender group.
    ///
    /// When the configured style is `.edged(.bottom)`, only the last message in a group shows the tail.
    /// When `.edged(.top)`, only the first message in a group shows the tail.
    /// When `.none`, no tail is ever shown.
    /// - Parameters:
    ///   - message: The message to resolve the tail style for.
    ///   - configStyle: The tail style from the current chat configuration.
    /// - Returns: The resolved tail style for this specific message.
    public func tailStyle(for message: FCLChatMessage, configStyle: FCLBubbleTailStyle) -> FCLBubbleTailStyle {
        switch configStyle {
        case .none:
            return .none
        case .edged(let edge):
            guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
                return .none
            }
            switch edge {
            case .bottom:
                let isLastInGroup = index == messages.count - 1
                    || messages[index + 1].direction != message.direction
                return isLastInGroup ? .edged(.bottom) : .none
            case .top:
                let isFirstInGroup = index == 0
                    || messages[index - 1].direction != message.direction
                return isFirstInGroup ? .edged(.top) : .none
            }
        }
    }

    /// Copies the text content of a message to the clipboard.
    /// - Parameter message: The message whose text should be copied.
    public func copyMessage(_ message: FCLChatMessage) {
        clipboard.copy(message.text)
    }

    /// Returns the context menu actions available for the given message.
    ///
    /// Delegates to `contextMenuDelegate`; returns an empty array if no delegate is set.
    /// - Parameter message: The message to retrieve actions for.
    /// - Returns: An array of context menu actions.
    public func contextMenuActions(for message: FCLChatMessage) -> [FCLContextMenuAction] {
        contextMenuDelegate?.contextMenuActions(for: message, direction: message.direction) ?? []
    }

    /// Returns the vertical spacing following `message` in the timeline, based on sender-group transitions.
    public func spacing(after message: FCLChatMessage) -> CGFloat {
        guard let index = messages.firstIndex(where: { $0.id == message.id }),
              index < messages.count - 1 else {
            return 0
        }
        let next = messages[index + 1]
        if next.direction == message.direction {
            return resolvedIntraGroupSpacing
        }
        return resolvedInterGroupSpacing
    }

    /// Sends the current draft as an outgoing message, clears the draft, and notifies the router.
    /// Does nothing when the trimmed draft is empty.
    public func sendDraft() {
        let normalized = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        let message = FCLChatMessage(text: normalized, direction: .outgoing, sender: currentUser)
        messages.append(message)
        draftText = ""
        router?.didSendMessage(message)
    }

    /// Handles attachments sent from the attachment picker sheet.
    public func handleAttachments(_ attachments: [FCLAttachment], caption: String?) {
        let text = caption ?? ""
        let message = FCLChatMessage(
            text: text,
            direction: .outgoing,
            attachments: attachments,
            sender: currentUser
        )
        messages.append(message)
        router?.didSendMessage(message)
    }

    /// Appends an outgoing message with the given attachments, animating the bubble in on the
    /// same UI tick as the picker sheet dismissal so both transitions start simultaneously.
    ///
    /// - Parameters:
    ///   - attachments: Attachments to include in the outgoing message.
    ///   - caption: Optional caption text applied to the message body.
    public func handleAttachmentsDeferred(
        _ attachments: [FCLAttachment],
        caption: String?
    ) {
        let text = caption ?? ""
        let message = FCLChatMessage(
            text: text,
            direction: .outgoing,
            attachments: attachments,
            sender: currentUser
        )
        withAnimation(.easeOut(duration: 0.25)) {
            messages.append(message)
        }
        router?.didSendMessage(message)
    }

    /// Surfaces a send-path error to the chat screen's toast when the originating
    /// modal (e.g. picker sheet) has already been dismissed.
    /// - Parameter message: Localized description of the error.
    public func reportSendError(_ message: String) {
        lastSendError = message
    }

    /// Deletes a message from the conversation and notifies the router.
    /// - Parameter message: The message to remove.
    public func deleteMessage(_ message: FCLChatMessage) {
        messages.removeAll { $0.id == message.id }
        router?.didDeleteMessage(message)
    }

    #if canImport(UIKit)
    /// All image and video attachments across the conversation in chronological order.
    public var allConversationMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)] {
        var result: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)] = []
        for message in messages {
            let media = message.attachments.filter { $0.type == .image || $0.type == .video }
            for (index, attachment) in media.enumerated() {
                result.append((messageID: message.id, attachmentIndex: index, attachment: attachment))
            }
        }
        return result
    }

    /// Finds the global media index for a specific attachment in a specific message.
    public func globalMediaIndex(for attachment: FCLAttachment, in messageID: UUID) -> Int? {
        allConversationMedia.firstIndex { $0.messageID == messageID && $0.attachment.id == attachment.id }
    }
    #endif
}

#if canImport(UIKit)
// MARK: - FCLChatMediaPreviewSourceDelegate Conformance

extension FCLChatPresenter: FCLChatMediaPreviewSourceDelegate {
    public func currentFrame(forItemID id: UUID) -> CGRect? {
        frameProvider?(id)
    }
}

// MARK: - Frame Provider

public extension FCLChatPresenter {
    /// Closure installed by the chat screen to map attachment IDs to window-space frames.
    /// Keeps the presenter free of a direct dependency on `FCLChatMediaPreviewRelay`.
    var frameProvider: ((UUID) -> CGRect?)? {
        get { _frameProvider }
        set { _frameProvider = newValue }
    }
}
#endif
