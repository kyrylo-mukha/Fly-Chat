import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The main chat screen view that renders a scrollable message timeline and an input bar.
///
/// `FCLChatScreen` is the primary entry point for embedding a chat conversation UI.
/// It observes an ``FCLChatPresenter`` for message data and draft state, and reads
/// appearance/input configuration from an optional ``FCLChatDelegate``.
///
/// The message list renders bottom-anchored (latest messages at the bottom) and supports
/// tap-to-dismiss-keyboard, drag-to-dismiss-keyboard, and long-press context menus on bubbles.
/// A built-in input bar is provided on iOS; on macOS a lightweight text field fallback is used.
/// Host apps may supply a completely custom input bar via the `customInputBar` initializer.
public struct FCLChatScreen: View {
    /// The presenter that drives message data, draft text, and bubble layout decisions.
    @ObservedObject private var presenter: FCLChatPresenter
    /// Optional delegate providing appearance, input, and avatar configuration overrides.
    private let delegate: (any FCLChatDelegate)?
    /// An optional host-provided input bar that replaces the built-in one when non-nil.
    private let customInputBar: AnyView?

    // MARK: - Resolved Appearance

    /// Resolved bubble background color for outgoing (sender) messages.
    private var senderBubbleColor: FCLChatColorToken { delegate?.appearance?.senderBubbleColor ?? FCLAppearanceDefaults.senderBubbleColor }
    /// Resolved bubble background color for incoming (receiver) messages.
    private var receiverBubbleColor: FCLChatColorToken { delegate?.appearance?.receiverBubbleColor ?? FCLAppearanceDefaults.receiverBubbleColor }
    /// Resolved text color for outgoing (sender) messages.
    private var senderTextColor: FCLChatColorToken { delegate?.appearance?.senderTextColor ?? FCLAppearanceDefaults.senderTextColor }
    /// Resolved text color for incoming (receiver) messages.
    private var receiverTextColor: FCLChatColorToken { delegate?.appearance?.receiverTextColor ?? FCLAppearanceDefaults.receiverTextColor }
    /// Resolved font configuration for message body text.
    private var messageFont: FCLChatMessageFontConfiguration { delegate?.appearance?.messageFont ?? FCLAppearanceDefaults.messageFont }
    /// Resolved bubble tail style (e.g., `.none`, `.edged(.bottom)`).
    private var tailStyle: FCLBubbleTailStyle { delegate?.appearance?.tailStyle ?? FCLAppearanceDefaults.tailStyle }
    /// Resolved minimum height for a message bubble.
    private var minimumBubbleHeight: CGFloat { delegate?.appearance?.minimumBubbleHeight ?? FCLAppearanceDefaults.minimumBubbleHeight }

    // MARK: - Resolved Input

    /// Resolved placeholder string shown in the text input field when empty.
    private var inputPlaceholderText: String { delegate?.input?.placeholderText ?? FCLInputDefaults.placeholderText }
    /// Resolved minimum character count required before the send button activates.
    private var inputMinimumTextLength: Int { delegate?.input?.minimumTextLength ?? FCLInputDefaults.minimumTextLength }
    /// Resolved maximum number of visible text rows before the input field scrolls.
    private var inputMaxRows: Int? { delegate?.input?.maxRows ?? FCLInputDefaults.maxRows }
    /// Resolved line height for the input text view.
    private var inputLineHeight: CGFloat? { delegate?.input?.lineHeight ?? FCLInputDefaults.lineHeight }
    /// Whether pressing the Return key sends the message instead of inserting a newline.
    private var inputReturnKeySends: Bool { delegate?.input?.returnKeySends ?? FCLInputDefaults.returnKeySends }
    /// Whether the paperclip attachment button is visible in the input bar.
    private var inputShowAttachButton: Bool { delegate?.input?.showAttachButton ?? FCLInputDefaults.showAttachButton }
    /// The thumbnail size (in points) used for attachment previews in the input bar strip.
    private var inputAttachmentThumbnailSize: CGFloat { delegate?.input?.attachmentThumbnailSize ?? FCLInputDefaults.attachmentThumbnailSize }
    /// Resolved container mode controlling how the input bar elements are grouped visually.
    private var inputContainerMode: FCLInputBarContainerMode { delegate?.input?.containerMode ?? FCLInputDefaults.containerMode }
    /// Whether the input bar background uses a liquid glass / blur material effect.
    private var inputLiquidGlass: Bool { delegate?.input?.liquidGlass ?? FCLInputDefaults.liquidGlass }
    /// Resolved background color of the input bar container.
    private var inputBackgroundColor: FCLChatColorToken { delegate?.input?.backgroundColor ?? FCLInputDefaults.backgroundColor }
    /// Resolved background color of the text input field itself.
    private var inputFieldBackgroundColor: FCLChatColorToken { delegate?.input?.fieldBackgroundColor ?? FCLInputDefaults.fieldBackgroundColor }
    /// Resolved corner radius for the text input field.
    private var inputFieldCornerRadius: CGFloat { delegate?.input?.fieldCornerRadius ?? FCLInputDefaults.fieldCornerRadius }
    /// Resolved content insets around the input bar elements.
    private var inputContentInsets: FCLEdgeInsets { delegate?.input?.contentInsets ?? FCLInputDefaults.contentInsets }
    /// Resolved spacing between elements (attach button, text field, send button) in the input bar.
    private var inputElementSpacing: CGFloat { delegate?.input?.elementSpacing ?? FCLInputDefaults.elementSpacing }

    /// Creates a chat screen with the default built-in input bar.
    ///
    /// - Parameters:
    ///   - presenter: The chat presenter that supplies messages, draft text, and layout logic.
    ///   - delegate: An optional delegate providing appearance and behavior customization.
    public init(
        presenter: FCLChatPresenter,
        delegate: (any FCLChatDelegate)? = nil
    ) {
        self.presenter = presenter
        self.delegate = delegate
        self.customInputBar = nil
    }

    #if canImport(UIKit)
    /// Creates a chat screen with a custom input bar replacing the built-in one.
    ///
    /// - Parameters:
    ///   - presenter: The chat presenter that supplies messages, draft text, and layout logic.
    ///   - delegate: An optional delegate providing appearance and behavior customization.
    ///   - customInputBar: A view builder returning the custom input bar to display.
    public init<InputBar: View>(
        presenter: FCLChatPresenter,
        delegate: (any FCLChatDelegate)? = nil,
        @ViewBuilder customInputBar: @escaping () -> InputBar
    ) {
        self.presenter = presenter
        self.delegate = delegate
        self.customInputBar = AnyView(customInputBar())
    }
    #endif

    /// Tracks the current screen height for dynamic input bar row calculations.
    @State private var screenHeight: CGFloat = 700

    public var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                messagesList(availableWidth: proxy.size.width)
                inputBarSection
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.99))
            .onAppear {
                screenHeight = proxy.size.height
                configureListAppearance()
            }
            .onDisappear(perform: restoreListAppearance)
            .onChangeOfHeightIfAvailable(proxy.size.height) { newHeight in
                screenHeight = newHeight
            }
        }
    }

    /// Builds the scrollable, bottom-anchored message list.
    ///
    /// - Parameter availableWidth: The full width of the container, used to compute maximum bubble width.
    /// - Returns: A `List` view containing all rendered messages as ``FCLChatMessageRow`` instances.
    private func messagesList(availableWidth: CGFloat) -> some View {
        let maxBubbleWidth = max(180, availableWidth * presenter.resolvedMaxBubbleWidthRatio)
        let avatarDelegate = delegate?.avatar
        let avatarSize = avatarDelegate?.avatarSize ?? FCLAvatarDefaults.avatarSize
        let showIncoming = avatarDelegate?.showIncomingAvatar ?? FCLAvatarDefaults.showIncomingAvatar
        let showOutgoing = avatarDelegate?.showOutgoingAvatar ?? FCLAvatarDefaults.showOutgoingAvatar

        let minHeight = minimumBubbleHeight

        return List {
            Section {
                ForEach(presenter.renderedMessagesFromBottom) { message in
                    let spacing = presenter.spacing(after: message)
                    FCLChatMessageRow(
                        message: message,
                        side: presenter.side(for: message),
                        tailStyle: presenter.tailStyle(for: message, configStyle: tailStyle),
                        maxBubbleWidth: maxBubbleWidth,
                        minimumBubbleHeight: minHeight,
                        showAvatar: message.direction == .incoming ? showIncoming : showOutgoing,
                        isLastInGroup: presenter.isLastInGroup(for: message),
                        avatarSize: avatarSize,
                        avatarDelegate: avatarDelegate,
                        senderBubbleColor: senderBubbleColor,
                        receiverBubbleColor: receiverBubbleColor,
                        senderTextColor: senderTextColor,
                        receiverTextColor: receiverTextColor,
                        messageFont: messageFont,
                        contextMenuActions: presenter.contextMenuActions(for: message)
                    )
                    .modifier(FCLBottomAnchoredChatModifier())
                    .listRowInsets(EdgeInsets(top: spacing / 2, leading: 10, bottom: spacing / 2, trailing: 10))
                    .listRowBackground(Color.clear)
                    .hideFCLChatRowSeparatorsIfAvailable()
                    .onTapGesture(perform: dismissKeyboard)
                }
            }
            .hideFCLChatSectionSeparatorsIfAvailable()
        }
        .listStyle(PlainListStyle())
        .modifier(FCLBottomAnchoredChatModifier())
        .onTapGesture(perform: dismissKeyboard)
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { _ in dismissKeyboard() }
        )
    }

    /// The input bar section, which renders either the host-provided custom input bar
    /// or the built-in ``FCLInputBar`` (iOS) / macOS text field fallback.
    @ViewBuilder
    private var inputBarSection: some View {
        if let custom = customInputBar {
            custom
        } else {
            #if canImport(UIKit)
            FCLInputBar(
                draftText: $presenter.draftText,
                attachmentManager: presenter.attachmentManager,
                placeholderText: inputPlaceholderText,
                maxRows: inputMaxRows,
                lineHeight: inputLineHeight,
                returnKeySends: inputReturnKeySends,
                showAttachButton: inputShowAttachButton,
                attachmentThumbnailSize: inputAttachmentThumbnailSize,
                containerMode: inputContainerMode,
                liquidGlass: inputLiquidGlass,
                backgroundColor: inputBackgroundColor,
                fieldBackgroundColor: inputFieldBackgroundColor,
                fieldCornerRadius: inputFieldCornerRadius,
                contentInsets: inputContentInsets,
                elementSpacing: inputElementSpacing,
                font: messageFont,
                minimumTextLength: inputMinimumTextLength,
                availableHeight: screenHeight,
                onSend: presenter.sendDraft
            )
            #else
            macOSComposer
            #endif
        }
    }

    #if canImport(AppKit)
    /// A minimal macOS-only message composer fallback using a standard `TextField` and Send button.
    private var macOSComposer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $presenter.draftText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white)
                .cornerRadius(18)

            Button(action: presenter.sendDraft) {
                Text("Send")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
    }
    #endif

    /// Dismisses the keyboard (iOS) or resigns first responder (macOS).
    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #elseif canImport(AppKit)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    /// Configures `UITableView` global appearance to remove separators and enable drag-to-dismiss keyboard.
    /// Called when the chat screen appears.
    private func configureListAppearance() {
        #if canImport(UIKit)
        UITableView.appearance().separatorStyle = .none
        UITableView.appearance().separatorColor = .clear
        UITableView.appearance().tableFooterView = UIView(frame: .zero)
        UITableView.appearance().keyboardDismissMode = .onDrag
        #endif
    }

    /// Restores `UITableView` global appearance to system defaults.
    /// Called when the chat screen disappears.
    private func restoreListAppearance() {
        #if canImport(UIKit)
        UITableView.appearance().separatorStyle = .singleLine
        UITableView.appearance().separatorColor = nil
        UITableView.appearance().tableFooterView = nil
        UITableView.appearance().keyboardDismissMode = .none
        #endif
    }
}

// MARK: - Message Row

/// A single chat message row that lays out the bubble, avatar, timestamp, and context menu.
///
/// This private view is used by ``FCLChatScreen`` to render each message inside the list.
/// It handles bubble placement (left/right), avatar visibility, attachment rendering,
/// inline timestamp overlay, and long-press context menus (copy, delete, etc.).
private struct FCLChatMessageRow: View {
    /// The chat message model to render.
    let message: FCLChatMessage
    /// Which side of the screen the bubble appears on.
    let side: FCLChatBubbleSide
    /// The tail style applied to this bubble (may vary based on grouping).
    let tailStyle: FCLBubbleTailStyle
    /// Maximum width (in points) the bubble may occupy.
    let maxBubbleWidth: CGFloat
    /// Minimum height (in points) for the bubble, even for very short messages.
    let minimumBubbleHeight: CGFloat
    /// Whether the avatar circle is shown next to this message.
    let showAvatar: Bool
    /// Whether this message is the last in its sender group (controls avatar visibility vs. spacer).
    let isLastInGroup: Bool
    /// The diameter of the avatar circle in points.
    let avatarSize: CGFloat
    /// Optional avatar delegate for custom avatar loading and caching.
    let avatarDelegate: (any FCLAvatarDelegate)?
    /// Bubble background color for outgoing messages.
    let senderBubbleColor: FCLChatColorToken
    /// Bubble background color for incoming messages.
    let receiverBubbleColor: FCLChatColorToken
    /// Text color for outgoing messages.
    let senderTextColor: FCLChatColorToken
    /// Text color for incoming messages.
    let receiverTextColor: FCLChatColorToken
    /// Font configuration for message body text.
    let messageFont: FCLChatMessageFontConfiguration
    /// The list of context menu actions available on long-press.
    let contextMenuActions: [FCLContextMenuAction]

    /// Shared date formatter for rendering short time strings (e.g., "2:30 PM").
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Invisible spacer that reserves space for the timestamp overlay.
    /// Uses the same caption2 font as the visible timestamp. Placeholder is wide enough
    /// for the widest locale time (e.g., "00:00 AM" + padding).
    private var timestampSpacer: String {
        "     00:00 AM"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: showAvatar ? 8 : 0) {
            if side == .right {
                Spacer()
            }

            if showAvatar && side == .left {
                avatarOrSpacer
            }

            bubbleWithContextMenu

            if showAvatar && side == .right {
                avatarOrSpacer
            }

            if side == .left {
                Spacer()
            }
        }
    }

    /// Renders the avatar image for the last message in a group, or a clear spacer for mid-group messages.
    @ViewBuilder
    private var avatarOrSpacer: some View {
        if isLastInGroup {
            #if canImport(UIKit)
            FCLAvatarView(
                senderID: message.sender.id,
                displayName: message.sender.displayName,
                size: avatarSize,
                delegate: avatarDelegate
            )
            #else
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: avatarSize, height: avatarSize)
            #endif
        } else {
            Color.clear
                .frame(width: avatarSize, height: avatarSize)
        }
    }

    /// Wraps the bubble with a context menu when actions are available.
    @ViewBuilder
    private var bubbleWithContextMenu: some View {
        if contextMenuActions.isEmpty {
            bubble
        } else {
            if #available(iOS 16.0, macOS 13.0, *) {
                bubble.contextMenu {
                    contextMenuButtons
                } preview: {
                    bubblePreview
                }
            } else {
                bubble.contextMenu {
                    contextMenuButtons
                }
            }
        }
    }

    /// Renders the context menu action buttons for long-press interactions.
    @ViewBuilder
    private var contextMenuButtons: some View {
        ForEach(Array(contextMenuActions.enumerated()), id: \.offset) { _, action in
            if #available(iOS 15.0, macOS 12.0, *) {
                Button(role: action.role == .destructive ? .destructive : nil, action: {
                    action.handler(message)
                }) {
                    Label(action.title, systemImage: action.systemImage ?? "")
                }
            } else if #available(macOS 11.0, *) {
                Button(action: {
                    action.handler(message)
                }) {
                    if let systemImage = action.systemImage {
                        Label(action.title, systemImage: systemImage)
                    } else {
                        Text(action.title)
                    }
                }
            } else {
                Button(action: {
                    action.handler(message)
                }) {
                    Text(action.title)
                }
            }
        }
    }

    /// The message bubble with the configured tail style.
    private var bubble: some View {
        bubbleContent(tailStyle: tailStyle)
    }

    /// A bubble preview shown during the context menu interaction, rendered without a tail.
    private var bubblePreview: some View {
        bubbleContent(tailStyle: .none)
    }

    /// Builds the full bubble content including attachments, message text, and timestamp overlay.
    ///
    /// - Parameter tailStyle: The tail style to apply to the bubble shape background.
    /// - Returns: A view representing the complete bubble with all its content layers.
    private func bubbleContent(tailStyle: FCLBubbleTailStyle) -> some View {
        let textColor: Color = isSender ? senderTextColor.color : receiverTextColor.color
        let timeColor: Color = textColor.opacity(0.6)
        let timeString = Self.timeFormatter.string(from: message.sentAt)

        let timestampFont: Font = {
            if #available(iOS 14.0, macOS 11.0, *) {
                return .caption2
            } else {
                return .caption
            }
        }()

        let mediaAttachments = message.attachments.filter { $0.type == .image || $0.type == .video }
        let fileAttachments = message.attachments.filter { $0.type == .file }
        let hasAttachments = !message.attachments.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            #if canImport(UIKit)
            if !mediaAttachments.isEmpty {
                FCLAttachmentGridView(attachments: mediaAttachments, maxWidth: maxBubbleWidth)
            }

            ForEach(fileAttachments) { attachment in
                FCLFileRowView(attachment: attachment)
            }
            #endif

            if !message.text.isEmpty {
                (
                    Text(message.text)
                        .font(messageFont.font)
                        .foregroundColor(textColor)
                    + Text(timestampSpacer)
                        .font(timestampFont)
                        .foregroundColor(.clear)
                )
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .overlay(
                    Text(timeString)
                        .font(timestampFont)
                        .foregroundColor(timeColor)
                        .offset(y: 3)
                        .padding(.trailing, 8)
                        .padding(.bottom, 4),
                    alignment: .bottomTrailing
                )
            } else if hasAttachments {
                HStack {
                    Spacer()
                    Text(timeString)
                        .font(timestampFont)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                        .padding(4)
                }
            }
        }
        .frame(minHeight: minimumBubbleHeight)
        .frame(maxWidth: maxBubbleWidth, alignment: side == .right ? .trailing : .leading)
        .background(
            FCLChatBubbleShape(side: side, tailStyle: tailStyle)
                .fill(isSender ? senderBubbleColor.color : receiverBubbleColor.color)
                .animation(.easeInOut(duration: 0.25), value: tailStyle)
        )
    }

    /// Whether this message was sent by the current user (outgoing direction).
    private var isSender: Bool {
        message.direction == .outgoing
    }
}

// MARK: - Bottom Anchored Modifier

/// A view modifier that flips content 180 degrees and mirrors it horizontally to achieve
/// a bottom-anchored scroll effect. Applied to both the `List` and each row so the list
/// renders from the bottom while keeping row content visually correct.
private struct FCLBottomAnchoredChatModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(180))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}

// MARK: - Height Change Helpers

private extension View {
    /// Observes changes to the given height value when running on iOS 14+ / macOS 11+.
    /// On earlier OS versions this is a no-op (the screen height simply keeps its initial value).
    @ViewBuilder
    func onChangeOfHeightIfAvailable(_ height: CGFloat, perform action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 14.0, macOS 11.0, *) {
            self.onChange(of: height, perform: action)
        } else {
            self
        }
    }
}

// MARK: - Separator Helpers

private extension View {
    #if os(iOS)
    /// Hides list row separators on iOS 15+. On earlier versions this is a no-op.
    @ViewBuilder
    func hideFCLChatRowSeparatorsIfAvailable() -> some View {
        if #available(iOS 15.0, *) {
            self.listRowSeparator(.hidden, edges: .all)
        } else {
            self
        }
    }

    /// Hides list section separators on iOS 15+. On earlier versions this is a no-op.
    @ViewBuilder
    func hideFCLChatSectionSeparatorsIfAvailable() -> some View {
        if #available(iOS 15.0, *) {
            self.listSectionSeparator(.hidden, edges: .all)
        } else {
            self
        }
    }
    #else
    func hideFCLChatRowSeparatorsIfAvailable() -> some View { self }
    func hideFCLChatSectionSeparatorsIfAvailable() -> some View { self }
    #endif
}

// MARK: - Previews

#if DEBUG
private let previewOutgoingSender = FCLChatMessageSender(id: "preview-outgoing", displayName: "Me")
private let previewIncomingSender = FCLChatMessageSender(id: "preview-incoming", displayName: "Other")

struct FCLChatScreen_Previews: PreviewProvider {
    static var previews: some View {
        previewContent
    }

    @ViewBuilder
    private static var previewContent: some View {
        FCLChatScreen(presenter: samplePresenterSameSide)
            .previewDisplayName("Default: Both Right")

        FCLChatScreen(presenter: samplePresenterSplitSides)
            .previewDisplayName("Incoming Left / Outgoing Right")

        FCLChatScreen(presenter: FCLChatPresenter(messages: [], currentUser: previewOutgoingSender))
            .previewDisplayName("Empty")

        FCLChatScreen(presenter: samplePresenterGrouped)
            .previewDisplayName("Edged Bottom Grouping")
    }

    private static var samplePresenterGrouped: FCLChatPresenter {
        FCLChatPresenter(
            messages: [
                FCLChatMessage(text: "Hey!", direction: .outgoing, sentAt: Date().addingTimeInterval(-500), sender: previewOutgoingSender),
                FCLChatMessage(text: "How are you?", direction: .outgoing, sentAt: Date().addingTimeInterval(-480), sender: previewOutgoingSender),
                FCLChatMessage(text: "Check this out", direction: .outgoing, sentAt: Date().addingTimeInterval(-460), sender: previewOutgoingSender),
                FCLChatMessage(text: "Hi there!", direction: .incoming, sentAt: Date().addingTimeInterval(-400), sender: previewIncomingSender),
                FCLChatMessage(text: "I'm good thanks", direction: .incoming, sentAt: Date().addingTimeInterval(-380), sender: previewIncomingSender),
                FCLChatMessage(text: "Cool!", direction: .outgoing, sentAt: Date().addingTimeInterval(-300), sender: previewOutgoingSender),
            ],
            currentUser: previewOutgoingSender
        )
    }

    private static var samplePresenterSameSide: FCLChatPresenter {
        FCLChatPresenter(
            messages: [
                FCLChatMessage(text: "Hi!", direction: .incoming, sentAt: Date().addingTimeInterval(-360), sender: previewIncomingSender),
                FCLChatMessage(text: "Hello! This is a dynamic-width bubble.", direction: .outgoing, sentAt: Date().addingTimeInterval(-300), sender: previewOutgoingSender),
                FCLChatMessage(text: "Short", direction: .incoming, sentAt: Date().addingTimeInterval(-240), sender: previewIncomingSender),
                FCLChatMessage(text: "Long press any bubble for copy/delete. This message should wrap nicely and the timestamp flows inline.", direction: .incoming, sentAt: Date().addingTimeInterval(-120), sender: previewIncomingSender),
            ],
            currentUser: previewOutgoingSender
        )
    }

    private static var samplePresenterSplitSides: FCLChatPresenter {
        FCLChatPresenter(
            messages: [
                FCLChatMessage(text: "Now incoming is left.", direction: .incoming, sentAt: Date().addingTimeInterval(-220), sender: previewIncomingSender),
                FCLChatMessage(text: "Outgoing stays right.", direction: .outgoing, sentAt: Date().addingTimeInterval(-180), sender: previewOutgoingSender),
            ],
            currentUser: previewOutgoingSender
        )
    }
}

private struct FCLChatMessageRow_Previews: PreviewProvider {
    static var previews: some View {
        previewContent
    }

    @ViewBuilder
    private static var previewContent: some View {
        FCLChatMessageRow(
            message: FCLChatMessage(text: "Incoming sample", direction: .incoming, sender: previewIncomingSender),
            side: .left,
            tailStyle: .edged(.bottom),
            maxBubbleWidth: 280,
            minimumBubbleHeight: FCLAppearanceDefaults.minimumBubbleHeight,
            showAvatar: true,
            isLastInGroup: true,
            avatarSize: FCLAvatarDefaults.avatarSize,
            avatarDelegate: nil,
            senderBubbleColor: FCLAppearanceDefaults.senderBubbleColor,
            receiverBubbleColor: FCLAppearanceDefaults.receiverBubbleColor,
            senderTextColor: FCLAppearanceDefaults.senderTextColor,
            receiverTextColor: FCLAppearanceDefaults.receiverTextColor,
            messageFont: FCLAppearanceDefaults.messageFont,
            contextMenuActions: []
        )
        .previewDisplayName("Incoming with Avatar")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLChatMessageRow(
            message: FCLChatMessage(text: "Incoming mid-group", direction: .incoming, sender: previewIncomingSender),
            side: .left,
            tailStyle: .none,
            maxBubbleWidth: 280,
            minimumBubbleHeight: FCLAppearanceDefaults.minimumBubbleHeight,
            showAvatar: true,
            isLastInGroup: false,
            avatarSize: FCLAvatarDefaults.avatarSize,
            avatarDelegate: nil,
            senderBubbleColor: FCLAppearanceDefaults.senderBubbleColor,
            receiverBubbleColor: FCLAppearanceDefaults.receiverBubbleColor,
            senderTextColor: FCLAppearanceDefaults.senderTextColor,
            receiverTextColor: FCLAppearanceDefaults.receiverTextColor,
            messageFont: FCLAppearanceDefaults.messageFont,
            contextMenuActions: []
        )
        .previewDisplayName("Incoming Mid-Group (Spacer)")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLChatMessageRow(
            message: FCLChatMessage(text: "Outgoing sample", direction: .outgoing, sender: previewOutgoingSender),
            side: .right,
            tailStyle: .edged(.bottom),
            maxBubbleWidth: 280,
            minimumBubbleHeight: FCLAppearanceDefaults.minimumBubbleHeight,
            showAvatar: false,
            isLastInGroup: true,
            avatarSize: FCLAvatarDefaults.avatarSize,
            avatarDelegate: nil,
            senderBubbleColor: FCLAppearanceDefaults.senderBubbleColor,
            receiverBubbleColor: FCLAppearanceDefaults.receiverBubbleColor,
            senderTextColor: FCLAppearanceDefaults.senderTextColor,
            receiverTextColor: FCLAppearanceDefaults.receiverTextColor,
            messageFont: FCLAppearanceDefaults.messageFont,
            contextMenuActions: []
        )
        .previewDisplayName("Outgoing (No Avatar)")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLChatMessageRow(
            message: FCLChatMessage(text: "Short", direction: .outgoing, sender: previewOutgoingSender),
            side: .right,
            tailStyle: .edged(.bottom),
            maxBubbleWidth: 280,
            minimumBubbleHeight: FCLAppearanceDefaults.minimumBubbleHeight,
            showAvatar: false,
            isLastInGroup: true,
            avatarSize: FCLAvatarDefaults.avatarSize,
            avatarDelegate: nil,
            senderBubbleColor: FCLAppearanceDefaults.senderBubbleColor,
            receiverBubbleColor: FCLAppearanceDefaults.receiverBubbleColor,
            senderTextColor: FCLAppearanceDefaults.senderTextColor,
            receiverTextColor: FCLAppearanceDefaults.receiverTextColor,
            messageFont: FCLAppearanceDefaults.messageFont,
            contextMenuActions: []
        )
        .previewDisplayName("Short Dynamic Width")
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
