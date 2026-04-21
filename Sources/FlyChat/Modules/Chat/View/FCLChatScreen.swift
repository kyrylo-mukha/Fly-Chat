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
    @ObservedObject private var presenter: FCLChatPresenter
    private let delegate: (any FCLChatDelegate)?
    private let customInputBar: AnyView?

    // MARK: - Resolved Appearance

    private var senderBubbleColor: FCLChatColorToken { delegate?.appearance?.senderBubbleColor ?? FCLAppearanceDefaults.senderBubbleColor }
    private var receiverBubbleColor: FCLChatColorToken { delegate?.appearance?.receiverBubbleColor ?? FCLAppearanceDefaults.receiverBubbleColor }
    private var senderTextColor: FCLChatColorToken { delegate?.appearance?.senderTextColor ?? FCLAppearanceDefaults.senderTextColor }
    private var receiverTextColor: FCLChatColorToken { delegate?.appearance?.receiverTextColor ?? FCLAppearanceDefaults.receiverTextColor }
    private var messageFont: FCLChatMessageFontConfiguration { delegate?.appearance?.messageFont ?? FCLAppearanceDefaults.messageFont }
    private var tailStyle: FCLBubbleTailStyle { delegate?.appearance?.tailStyle ?? FCLAppearanceDefaults.tailStyle }
    private var minimumBubbleHeight: CGFloat { delegate?.appearance?.minimumBubbleHeight ?? FCLAppearanceDefaults.minimumBubbleHeight }
    private var statusIcons: FCLChatStatusIcons { delegate?.appearance?.statusIcons ?? FCLAppearanceDefaults.statusIcons }
    private var statusColors: FCLChatStatusColors { delegate?.appearance?.statusColors ?? FCLAppearanceDefaults.statusColors }
    private var showsStatusForOutgoing: Bool { delegate?.layout?.showsStatusForOutgoing ?? FCLLayoutDefaults.showsStatusForOutgoing }

    // MARK: - Resolved Input

    private var inputPlaceholderText: String { delegate?.input?.placeholderText ?? FCLInputDefaults.placeholderText }
    private var inputMinimumTextLength: Int { delegate?.input?.minimumTextLength ?? FCLInputDefaults.minimumTextLength }
    private var inputMaxRows: Int? { delegate?.input?.maxRows ?? FCLInputDefaults.maxRows }
    private var inputLineHeight: CGFloat? { delegate?.input?.lineHeight ?? FCLInputDefaults.lineHeight }
    private var inputReturnKeySends: Bool { delegate?.input?.returnKeySends ?? FCLInputDefaults.returnKeySends }
    private var inputShowAttachButton: Bool { delegate?.input?.showAttachButton ?? FCLInputDefaults.showAttachButton }
    private var inputAttachmentThumbnailSize: CGFloat { delegate?.input?.attachmentThumbnailSize ?? FCLInputDefaults.attachmentThumbnailSize }
    private var inputContainerMode: FCLInputBarContainerMode { delegate?.input?.containerMode ?? FCLInputDefaults.containerMode }
    /// Reads the deprecated ``FCLInputDelegate/liquidGlass`` flag for backward compatibility only.
    /// New hosts should use ``FCLChatDelegate/visualStyle`` instead.
    private var inputLiquidGlass: Bool { delegate?.input?.liquidGlass ?? FCLInputDefaults.liquidGlass }
    private var inputBackgroundColor: FCLChatColorToken { delegate?.input?.backgroundColor ?? FCLInputDefaults.backgroundColor }
    private var inputFieldBackgroundColor: FCLChatColorToken { delegate?.input?.fieldBackgroundColor ?? FCLInputDefaults.fieldBackgroundColor }
    private var inputFieldCornerRadius: CGFloat { delegate?.input?.fieldCornerRadius ?? FCLInputDefaults.fieldCornerRadius }
    private var inputContentInsets: FCLEdgeInsets { delegate?.input?.contentInsets ?? FCLInputDefaults.contentInsets }
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

    @State private var screenHeight: CGFloat = 700
    @State private var screenWidth: CGFloat = 375
    /// Hoisted composer focus state. Timeline tap and drag handlers set this to `false` to
    /// dismiss the keyboard via `@FocusState` instead of a UIKit `resignFirstResponder` call.
    @FocusState private var isComposerFocused: Bool
    /// Guards against re-running `UITableView.appearance()` on every `onAppear`.
    /// Repeated mutations cause visible relayout churn on foreground transitions.
    @State private var didConfigureListAppearance = false
    @Environment(\.scenePhase) private var scenePhase
    /// True during the ~0.3 s window after `.background → .active`. Size-preference writes
    /// arriving in this window are applied with `disablesAnimations = true` to suppress
    /// the visible input-bar relayout regression.
    @State private var isReturningFromBackground = false

    #if canImport(UIKit)
    @State private var previewAttachmentID: UUID?
    @State private var previewRelay = FCLChatMediaPreviewRelay()
    @State private var previewRouter = FCLChatMediaPreviewRouter()
    #endif
    @Namespace private var mediaHeroNamespace

    public var body: some View {
        VStack(spacing: 0) {
            messagesList(availableWidth: screenWidth)
            inputBarSection
        }
        .transaction { transaction in
            if isReturningFromBackground {
                transaction.disablesAnimations = true
            }
        }
        .fclInstallVisualStyleDelegate(delegate?.visualStyle)
        .background(FCLPalette.systemBackground)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: FCLChatScreenSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(FCLChatScreenSizeKey.self) { newSize in
            var transaction = Transaction()
            if isReturningFromBackground {
                transaction.disablesAnimations = true
            }
            withTransaction(transaction) {
                if abs(newSize.width - screenWidth) > 0.5 {
                    screenWidth = newSize.width
                }
                if abs(newSize.height - screenHeight) > 0.5 {
                    screenHeight = newSize.height
                }
            }
        }
        .onAppear {
            #if canImport(UIKit)
            previewRouter.source = previewRelay
            let relay = previewRelay
            presenter.frameProvider = { id in relay.mediaPreviewFrame(forAssetID: id.uuidString) }
            #endif
            guard !didConfigureListAppearance else { return }
            #if canImport(UIKit)
            if UIApplication.shared.applicationState != .background {
                configureListAppearance()
                didConfigureListAppearance = true
            }
            #else
            configureListAppearance()
            didConfigureListAppearance = true
            #endif
        }
        .onChange(of: scenePhase, initial: false) { _, newPhase in
            switch newPhase {
            case .active:
                if isReturningFromBackground == false {
                    isReturningFromBackground = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isReturningFromBackground = false
                    }
                }
                if !didConfigureListAppearance {
                    configureListAppearance()
                    didConfigureListAppearance = true
                }
            case .background, .inactive:
                break
            @unknown default:
                break
            }
        }
        #if canImport(UIKit)
        .fclTransparentFullScreenCover(
            isPresented: Binding(
                get: { previewAttachmentID != nil },
                set: { if !$0 {
                    withTransaction(Transaction(animation: nil)) {
                        previewAttachmentID = nil
                        previewRouter.presenter.activeAttachmentID = nil
                    }
                } }
            )
        ) {
            if let attachmentID = previewAttachmentID {
                FCLMediaPreviewView(
                    presenter: presenter,
                    initialAttachmentID: attachmentID,
                    namespace: mediaHeroNamespace,
                    onDismiss: {
                        withTransaction(Transaction(animation: nil)) {
                            previewAttachmentID = nil
                            previewRouter.presenter.activeAttachmentID = nil
                        }
                    },
                    source: previewRelay
                )
            }
        }
        .onChange(of: previewRouter.presenter.activeAttachmentID) { _, newID in
            if let id = newID, previewAttachmentID == nil {
                previewAttachmentID = id
            } else if newID == nil {
                withTransaction(Transaction(animation: nil)) {
                    previewAttachmentID = nil
                }
            }
        }
        #endif
        .overlay(alignment: .top) {
            if let errorMessage = presenter.lastSendError {
                FCLChatSendErrorToast(message: errorMessage) {
                    presenter.lastSendError = nil
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: presenter.lastSendError)
            }
        }
    }

    private func messagesList(availableWidth: CGFloat) -> some View {
        let maxBubbleWidth = max(180, availableWidth * presenter.resolvedMaxBubbleWidthRatio)
        let avatarDelegate = delegate?.avatar
        let avatarSize = avatarDelegate?.avatarSize ?? FCLAvatarDefaults.avatarSize
        let showIncoming = avatarDelegate?.showIncomingAvatar ?? FCLAvatarDefaults.showIncomingAvatar
        let showOutgoing = avatarDelegate?.showOutgoingAvatar ?? FCLAvatarDefaults.showOutgoingAvatar

        let minHeight = minimumBubbleHeight
        let attachmentItemSpacing = presenter.resolvedAttachmentItemSpacing

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
                        attachmentItemSpacing: attachmentItemSpacing,
                        statusIcons: statusIcons,
                        statusColors: statusColors,
                        showsStatusForOutgoing: showsStatusForOutgoing,
                        contextMenuActions: presenter.contextMenuActions(for: message),
                        heroNamespace: mediaHeroNamespace,
                        onMediaTap: { attachment in
                            #if canImport(UIKit)
                            let item = FCLChatMediaPreviewItem(
                                asset: attachment,
                                sourceFrame: previewRelay.mediaPreviewFrame(forAssetID: attachment.id.uuidString)
                            )
                            previewRouter.present(item: item)
                            previewAttachmentID = attachment.id
                            #endif
                        },
                        onAttachmentCellFramesChange: { frames in
                            #if canImport(UIKit)
                            previewRelay.frames.merge(frames) { _, new in new }
                            #endif
                        },
                        onAttachmentCellFramesInvalidate: { keys in
                            #if canImport(UIKit)
                            for key in keys {
                                previewRelay.frames.removeValue(forKey: key)
                            }
                            #endif
                        }
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

    @ViewBuilder
    private var inputBarSection: some View {
        if let custom = customInputBar {
            custom
        } else {
            #if canImport(UIKit)
            FCLInputBar(
                draftText: $presenter.draftText,
                delegate: delegate,
                presenter: presenter,
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
                composerFocusBinding: $isComposerFocused,
                onSend: presenter.sendDraft
            )
            #else
            macOSComposer
            #endif
        }
    }

    #if canImport(AppKit)
    private var macOSComposer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $presenter.draftText)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(FCLPalette.systemBackground)
                .cornerRadius(22)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FCLPalette.secondarySystemBackground)
    }
    #endif

    private func dismissKeyboard() {
        #if canImport(UIKit)
        isComposerFocused = false
        #elseif canImport(AppKit)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    /// Configures `UITableView` global appearance to remove separators and enable drag-to-dismiss keyboard.
    ///
    /// Wrapped in `CATransaction.setDisableActions(true)` and `UIView.performWithoutAnimation`
    /// to prevent UIKit from animating the proxy mutation when it arrives during a live scene
    /// reactivation tick, which would produce visible input-bar relayout.
    private func configureListAppearance() {
        #if canImport(UIKit)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            UITableView.appearance().separatorStyle = .none
            UITableView.appearance().separatorColor = .clear
            UITableView.appearance().tableFooterView = UIView(frame: .zero)
            UITableView.appearance().keyboardDismissMode = .onDrag
        }
        CATransaction.commit()
        #endif
    }

}

// MARK: - Size Preference Key

private struct FCLChatScreenSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

// MARK: - Message Row

/// Renders a single chat message: bubble, avatar, timestamp overlay, and long-press context menu.
private struct FCLChatMessageRow: View {
    let message: FCLChatMessage
    let side: FCLChatBubbleSide
    let tailStyle: FCLBubbleTailStyle
    let maxBubbleWidth: CGFloat
    let minimumBubbleHeight: CGFloat
    let showAvatar: Bool
    let isLastInGroup: Bool
    let avatarSize: CGFloat
    let avatarDelegate: (any FCLAvatarDelegate)?
    let senderBubbleColor: FCLChatColorToken
    let receiverBubbleColor: FCLChatColorToken
    let senderTextColor: FCLChatColorToken
    let receiverTextColor: FCLChatColorToken
    let messageFont: FCLChatMessageFontConfiguration
    var attachmentItemSpacing: CGFloat = FCLAppearanceDefaults.attachmentItemSpacing
    var statusIcons: FCLChatStatusIcons = FCLAppearanceDefaults.statusIcons
    var statusColors: FCLChatStatusColors = FCLAppearanceDefaults.statusColors
    var showsStatusForOutgoing: Bool = FCLLayoutDefaults.showsStatusForOutgoing
    let contextMenuActions: [FCLContextMenuAction]
    let heroNamespace: Namespace.ID
    var onMediaTap: ((FCLAttachment) -> Void)?
    var onAttachmentCellFramesChange: (([String: CGRect]) -> Void)?
    var onAttachmentCellFramesInvalidate: ((Set<String>) -> Void)?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private var shouldShowStatus: Bool {
        guard message.direction == .outgoing, showsStatusForOutgoing else { return false }
        return message.status != nil
    }

    /// Invisible spacer text that reserves width for the timestamp overlay. Sized for the
    /// widest locale time string, with additional room for the status glyph when applicable.
    private var timestampSpacer: String {
        shouldShowStatus ? "  00:00 xx" : " 00:00"
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

    @ViewBuilder
    private var bubbleWithContextMenu: some View {
        if contextMenuActions.isEmpty {
            bubble
        } else {
            if #available(macOS 13.0, *) {
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

    @ViewBuilder
    private var contextMenuButtons: some View {
        ForEach(Array(contextMenuActions.enumerated()), id: \.offset) { _, action in
            if #available(macOS 12.0, *) {
                Button(role: action.role == .destructive ? .destructive : nil, action: {
                    action.handler(message)
                }) {
                    Label(action.title, systemImage: action.systemImage ?? "")
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

    private var bubble: some View {
        bubbleContent(tailStyle: tailStyle)
    }

    private var bubblePreview: some View {
        bubbleContent(tailStyle: .none)
    }

    @ViewBuilder
    private func bubbleContent(tailStyle: FCLBubbleTailStyle) -> some View {
        let textColor: Color = isSender ? senderTextColor.color : receiverTextColor.color
        let timeColor: Color = textColor.opacity(isSender ? 0.85 : 0.55)
        let timeString = Self.timeFormatter.string(from: message.sentAt)
        let timestampFont: Font = .caption2
        let mediaAttachments = message.attachments.filter { $0.type == .image || $0.type == .video }
        let fileAttachments = message.attachments.filter { $0.type == .file }
        let hasAttachments = !message.attachments.isEmpty

        #if canImport(UIKit)
        // Media-only message: grid fills the bubble, timestamp pill overlaid at bottom-trailing.
        if message.text.isEmpty && !mediaAttachments.isEmpty && fileAttachments.isEmpty {
            let fixedInset = FCLChatLayout.attachmentInset
            let fixedInsets = FCLEdgeInsets(top: fixedInset, leading: fixedInset, bottom: fixedInset, trailing: fixedInset)
            FCLAttachmentGridView(
                attachments: mediaAttachments,
                maxWidth: maxBubbleWidth,
                insets: fixedInsets,
                itemSpacing: attachmentItemSpacing,
                heroNamespace: heroNamespace,
                onAttachmentTap: { attachment in
                    onMediaTap?(attachment)
                },
                onCellFramesChange: { frames in
                    onAttachmentCellFramesChange?(frames)
                },
                onCellFramesInvalidate: { keys in
                    onAttachmentCellFramesInvalidate?(keys)
                },
                maskShape: FCLAttachmentMaskShape(.bubble(
                    topRadius: FCLChatBubbleShape.standardRadius,
                    bottomRadius: FCLChatBubbleShape.standardRadius,
                    side: side,
                    tailStyle: tailStyle
                ))
            )
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 3) {
                    if shouldShowStatus, let status = message.status {
                        FCLChatMessageStatusView(
                            status: status,
                            color: colorForStatus(status),
                            customIcon: iconForStatus(status)
                        )
                    }
                    Text(timeString)
                        .font(timestampFont)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.4))
                .cornerRadius(8)
                .padding(4)
            }
            .clipShape(FCLChatBubbleShape(side: side, tailStyle: tailStyle))
            .background(
                FCLChatBubbleShape(side: side, tailStyle: tailStyle)
                    .fill(isSender ? senderBubbleColor.color : receiverBubbleColor.color)
                    .animation(.easeInOut(duration: 0.25), value: tailStyle)
            )
            .frame(minWidth: minimumBubbleHeight, idealWidth: maxBubbleWidth, alignment: side == .right ? .trailing : .leading)
        } else {
            let hasContentBelowGrid = !message.text.isEmpty || !fileAttachments.isEmpty
            let fixedInset = FCLChatLayout.attachmentInset
            let fixedInsets = FCLEdgeInsets(top: fixedInset, leading: fixedInset, bottom: fixedInset, trailing: fixedInset)
            VStack(alignment: side == .right ? .trailing : .leading, spacing: 0) {
                if !mediaAttachments.isEmpty {
                    let gridMask: FCLAttachmentMaskShape = hasContentBelowGrid
                        ? FCLAttachmentMaskShape(.topRoundedBottomFlat(topRadius: FCLChatBubbleShape.standardRadius))
                        : FCLAttachmentMaskShape(.bubble(
                            topRadius: FCLChatBubbleShape.standardRadius,
                            bottomRadius: FCLChatBubbleShape.standardRadius,
                            side: side,
                            tailStyle: tailStyle
                          ))
                    FCLAttachmentGridView(
                        attachments: mediaAttachments,
                        maxWidth: maxBubbleWidth,
                        insets: fixedInsets,
                        itemSpacing: attachmentItemSpacing,
                        heroNamespace: heroNamespace,
                        onAttachmentTap: { attachment in
                            onMediaTap?(attachment)
                        },
                        onCellFramesChange: { frames in
                            onAttachmentCellFramesChange?(frames)
                        },
                        onCellFramesInvalidate: { keys in
                            onAttachmentCellFramesInvalidate?(keys)
                        },
                        maskShape: gridMask
                    )
                }

                #if os(iOS)
                ForEach(fileAttachments) { attachment in
                    FCLFileRowView(attachment: attachment)
                }
                #endif

                if !message.text.isEmpty {
                    let textTopPadding: CGFloat = mediaAttachments.isEmpty ? 7 : 6
                    let textBottomPadding: CGFloat = mediaAttachments.isEmpty ? 6 : 7
                    (
                        Text(message.text)
                            .font(messageFont.font)
                            .foregroundColor(textColor)
                        + Text(timestampSpacer)
                            .font(timestampFont)
                            .foregroundColor(.clear)
                    )
                    .multilineTextAlignment(side == .right ? .trailing : .leading)
                    .lineLimit(nil)
                    .padding(.horizontal, 12)
                    .padding(.top, textTopPadding)
                    .padding(.bottom, textBottomPadding)
                    .overlay(
                        HStack(spacing: 3) {
                            if shouldShowStatus, let status = message.status {
                                FCLChatMessageStatusView(
                                    status: status,
                                    color: colorForStatus(status),
                                    customIcon: iconForStatus(status)
                                )
                            }
                            Text(timeString)
                                .font(timestampFont)
                                .foregroundColor(timeColor)
                        }
                        .padding(.trailing, 10)
                        .padding(.bottom, 5),
                        alignment: .bottomTrailing
                    )
                } else if hasAttachments {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            if shouldShowStatus, let status = message.status {
                                FCLChatMessageStatusView(
                                    status: status,
                                    color: FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.8),
                                    customIcon: iconForStatus(status)
                                )
                            }
                            Text(timeString)
                                .font(timestampFont)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                        .padding(4)
                    }
                }
            }
            .frame(minHeight: minimumBubbleHeight)
            .frame(minWidth: minimumBubbleHeight, idealWidth: maxBubbleWidth, alignment: side == .right ? .trailing : .leading)
            .clipShape(FCLChatBubbleShape(side: side, tailStyle: tailStyle))
            .background(
                FCLChatBubbleShape(side: side, tailStyle: tailStyle)
                    .fill(isSender ? senderBubbleColor.color : receiverBubbleColor.color)
                    .animation(.easeInOut(duration: 0.25), value: tailStyle)
            )
        }
        #else
        VStack(alignment: side == .right ? .trailing : .leading, spacing: 0) {
            if !message.text.isEmpty {
                (
                    Text(message.text)
                        .font(messageFont.font)
                        .foregroundColor(textColor)
                    + Text(timestampSpacer)
                        .font(timestampFont)
                        .foregroundColor(.clear)
                )
                .multilineTextAlignment(side == .right ? .trailing : .leading)
                .lineLimit(nil)
                .padding(.horizontal, 12)
                .padding(.top, 7)
                .padding(.bottom, 6)
                .overlay(
                    HStack(spacing: 3) {
                        if shouldShowStatus, let status = message.status {
                            FCLChatMessageStatusView(
                                status: status,
                                color: colorForStatus(status),
                                customIcon: iconForStatus(status)
                            )
                        }
                        Text(timeString)
                            .font(timestampFont)
                            .foregroundColor(timeColor)
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, 5),
                    alignment: .bottomTrailing
                )
            } else if hasAttachments {
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        if shouldShowStatus, let status = message.status {
                            FCLChatMessageStatusView(
                                status: status,
                                color: FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.8),
                                customIcon: iconForStatus(status)
                            )
                        }
                        Text(timeString)
                            .font(timestampFont)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
                    .padding(4)
                }
            }
        }
        .frame(minHeight: minimumBubbleHeight)
        .frame(minWidth: minimumBubbleHeight, idealWidth: maxBubbleWidth, alignment: side == .right ? .trailing : .leading)
        .background(
            FCLChatBubbleShape(side: side, tailStyle: tailStyle)
                .fill(isSender ? senderBubbleColor.color : receiverBubbleColor.color)
                .animation(.easeInOut(duration: 0.25), value: tailStyle)
        )
        #endif
    }

    private var isSender: Bool {
        message.direction == .outgoing
    }

    private func colorForStatus(_ status: FCLChatMessageStatus) -> FCLChatColorToken {
        switch status {
        case .created: return statusColors.created
        case .sent: return statusColors.sent
        case .read: return statusColors.read
        }
    }

    private func iconForStatus(_ status: FCLChatMessageStatus) -> Image? {
        switch status {
        case .created: return statusIcons.created
        case .sent: return statusIcons.sent
        case .read: return statusIcons.read
        }
    }
}

// MARK: - Bottom Anchored Modifier

/// Flips and mirrors content to achieve a bottom-anchored scroll effect on a `List`.
private struct FCLBottomAnchoredChatModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(180))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}

// MARK: - Separator Helpers

private extension View {
    #if os(iOS)
    func hideFCLChatRowSeparatorsIfAvailable() -> some View {
        self.listRowSeparator(.hidden, edges: .all)
    }

    func hideFCLChatSectionSeparatorsIfAvailable() -> some View {
        self.listSectionSeparator(.hidden, edges: .all)
    }
    #else
    func hideFCLChatRowSeparatorsIfAvailable() -> some View { self }
    func hideFCLChatSectionSeparatorsIfAvailable() -> some View { self }
    #endif
}

// MARK: - FCLChatSendErrorToast

/// Lightweight top-anchored toast used by ``FCLChatScreen`` to surface send-path
/// errors reported via ``FCLChatPresenter/reportSendError(_:)``.
///
/// The toast auto-dismisses after a short interval by invoking ``onDismiss``.
/// Consumers can tap the toast to dismiss it immediately.
@MainActor
private struct FCLChatSendErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .onTapGesture { onDismiss() }
        .task(id: message) {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Send error: \(message)")
    }
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

private struct FCLChatMessageRowPreviewWrapper: View {
    let message: FCLChatMessage
    let side: FCLChatBubbleSide
    let tailStyle: FCLBubbleTailStyle
    let showAvatar: Bool
    let isLastInGroup: Bool
    @Namespace private var ns

    var body: some View {
        FCLChatMessageRow(
            message: message,
            side: side,
            tailStyle: tailStyle,
            maxBubbleWidth: 280,
            minimumBubbleHeight: FCLAppearanceDefaults.minimumBubbleHeight,
            showAvatar: showAvatar,
            isLastInGroup: isLastInGroup,
            avatarSize: FCLAvatarDefaults.avatarSize,
            avatarDelegate: nil,
            senderBubbleColor: FCLAppearanceDefaults.senderBubbleColor,
            receiverBubbleColor: FCLAppearanceDefaults.receiverBubbleColor,
            senderTextColor: FCLAppearanceDefaults.senderTextColor,
            receiverTextColor: FCLAppearanceDefaults.receiverTextColor,
            messageFont: FCLAppearanceDefaults.messageFont,
            attachmentItemSpacing: FCLAppearanceDefaults.attachmentItemSpacing,
            contextMenuActions: [],
            heroNamespace: ns
        )
    }
}

private struct FCLChatMessageRow_Previews: PreviewProvider {
    static var previews: some View {
        previewContent
    }

    @ViewBuilder
    private static var previewContent: some View {
        FCLChatMessageRowPreviewWrapper(
            message: FCLChatMessage(text: "Incoming sample", direction: .incoming, sender: previewIncomingSender),
            side: .left,
            tailStyle: .edged(.bottom),
            showAvatar: true,
            isLastInGroup: true
        )
        .previewDisplayName("Incoming with Avatar")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLChatMessageRowPreviewWrapper(
            message: FCLChatMessage(text: "Incoming mid-group", direction: .incoming, sender: previewIncomingSender),
            side: .left,
            tailStyle: .none,
            showAvatar: true,
            isLastInGroup: false
        )
        .previewDisplayName("Incoming Mid-Group (Spacer)")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLChatMessageRowPreviewWrapper(
            message: FCLChatMessage(text: "Outgoing sample", direction: .outgoing, sender: previewOutgoingSender),
            side: .right,
            tailStyle: .edged(.bottom),
            showAvatar: false,
            isLastInGroup: true
        )
        .previewDisplayName("Outgoing (No Avatar)")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLChatMessageRowPreviewWrapper(
            message: FCLChatMessage(text: "Short", direction: .outgoing, sender: previewOutgoingSender),
            side: .right,
            tailStyle: .edged(.bottom),
            showAvatar: false,
            isLastInGroup: true
        )
        .previewDisplayName("Short Dynamic Width")
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
