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
    /// Resolved custom icons for the three status states.
    private var statusIcons: FCLChatStatusIcons { delegate?.appearance?.statusIcons ?? FCLAppearanceDefaults.statusIcons }
    /// Resolved color tokens for the three status states.
    private var statusColors: FCLChatStatusColors { delegate?.appearance?.statusColors ?? FCLAppearanceDefaults.statusColors }
    /// Resolved flag: show status on outgoing messages.
    private var showsStatusForOutgoing: Bool { delegate?.layout?.showsStatusForOutgoing ?? FCLLayoutDefaults.showsStatusForOutgoing }

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
    /// Reads the deprecated ``FCLInputDelegate/liquidGlass`` flag for backward compatibility
    /// only. New hosts should use ``FCLChatDelegate/visualStyle`` instead.
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

    /// Tracks the current screen height for dynamic input bar row calculations.
    @State private var screenHeight: CGFloat = 700
    /// Tracks the current container width for dynamic max-bubble-width calculations.
    @State private var screenWidth: CGFloat = 375
    /// One-shot guard preventing the global `UITableView.appearance()` configuration from
    /// re-running on every `onAppear` (which also fires on `fullScreenCover` dismissals and
    /// scene-phase transitions). The appearance proxy only needs to be set once per process
    /// lifetime; repeated toggling causes visible relayout churn of the list on foreground.
    @State private var didConfigureListAppearance = false
    /// Tracks the current scene phase so size-preference updates dispatched during the
    /// `.background → .active` transition can be wrapped in a non-animating transaction.
    /// Without this flag SwiftUI's implicit animations fire on the first layout pass after
    /// foregrounding, producing a visible relayout of the input bar and message rows.
    @Environment(\.scenePhase) private var scenePhase
    /// True while the scene is returning from background to active. Any size-preference
    /// emissions that fire during this window are applied with `disablesAnimations = true`
    /// so the chat restores its last visual state without a re-layout animation.
    @State private var isReturningFromBackground = false

    #if canImport(UIKit)
    /// The ID of the attachment currently being previewed in full-screen, or `nil` when no preview is active.
    @State private var previewAttachmentID: UUID?
    /// Relay that bridges per-cell window-space frames from the visible attachment grids
    /// into ``FCLMediaPreviewView`` so it can animate the dismiss back into the source cell.
    /// SwiftUI view structs cannot be `AnyObject`, so the screen owns this small relay
    /// reference-type instead of adopting ``FCLMediaPreviewSource`` directly.
    @State private var previewRelay = FCLChatMediaPreviewRelay()
    /// Router bridging the chat screen to the ChatMediaPreviewer module. Threaded
    /// through in scope 16 without changing the current presentation pipeline;
    /// the router's `source` is kept in sync with ``previewRelay`` so downstream
    /// scopes can migrate callers off the local `previewAttachmentID` state
    /// without a further refactor.
    @State private var previewRouter = FCLChatMediaPreviewRouter()
    #endif
    /// Namespace used for hero-style matched geometry transitions between grid thumbnails and the full-screen preview.
    @Namespace private var mediaHeroNamespace

    public var body: some View {
        VStack(spacing: 0) {
            messagesList(availableWidth: screenWidth)
            inputBarSection
        }
        .fclInstallVisualStyleDelegate(delegate?.visualStyle)
        .background(Color(red: 0.96, green: 0.97, blue: 0.99))
        // Read container size via a background GeometryReader + PreferenceKey.
        // Unlike wrapping the entire hierarchy in a `GeometryReader`, this pattern
        // does not cause the `VStack`/`List` subtree to rebuild when the container
        // momentarily re-emits its size on scene reactivation (background → foreground).
        // The size is propagated only through a stable `@State` and an equality-guarded
        // `onChange`, so transient identical-value emissions are ignored by SwiftUI.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: FCLChatScreenSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(FCLChatScreenSizeKey.self) { newSize in
            // On the `.background → .active` transition SwiftUI re-evaluates this
            // view's body and the backing `GeometryReader` re-emits its size. Even
            // when the value is unchanged above the 0.5pt threshold, any state write
            // that happens inside the first active-tick carries the enclosing scope's
            // animation. Disable animations explicitly during the return-from-background
            // window so the size restoration never drives a visible relayout.
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
            // Keep the router's source aligned with the chat screen's relay so
            // downstream scopes can drive presentation through the router without
            // changing this wiring. Behavior stays identical: the transparent
            // full-screen cover below still reads `previewAttachmentID`.
            previewRouter.source = previewRelay
            // Wire the presenter's frame provider to the relay so `currentFrame(for:)`
            // on FCLChatMediaPreviewDataSource returns real window-space frames from
            // the visible attachment grid. The closure captures the relay by reference
            // so frame updates that arrive after onAppear are reflected immediately.
            let relay = previewRelay
            presenter.frameProvider = { id in relay.mediaPreviewFrame(forAssetID: id.uuidString) }
            #endif
            // Only configure the global `UITableView.appearance()` proxy while the
            // app is actually in the foreground. An `onAppear` that fires with the
            // application still in `.background` (e.g. when the chat screen is
            // rebuilt while a UIScene is resuming) would mutate the proxy at a
            // moment where UIKit commits the change as an animatable layout update,
            // producing the phantom relayout we are eliminating.
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
            // Flip the returning-from-background flag around the first active tick
            // so the next size-preference emission is applied without animation.
            // The flag is cleared on a subsequent async hop so genuinely user-driven
            // layout updates that happen after the scene stabilises keep their
            // intended implicit animations.
            switch newPhase {
            case .active:
                if isReturningFromBackground == false {
                    isReturningFromBackground = true
                    DispatchQueue.main.async {
                        isReturningFromBackground = false
                    }
                }
                // Late-configure the appearance proxy if the very first `onAppear`
                // ran while the scene was still backgrounded.
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
        // Note: we intentionally do NOT restore `UITableView.appearance()` in `onDisappear`.
        // The previous implementation toggled the proxy on every disappear (including when a
        // `fullScreenCover` or sheet was presented on top of the chat, and when the app
        // backgrounded), causing the list to relayout separators and insets on reappear.
        // Leaving the configured appearance in place avoids that visible jump; the proxy
        // values are scoped by `UITableView.appearance()` which only affects table views
        // created while the package's chat screen is in use.
        #if canImport(UIKit)
        .fclTransparentFullScreenCover(
            isPresented: Binding(
                get: { previewAttachmentID != nil },
                set: { if !$0 { withTransaction(Transaction(animation: nil)) { previewAttachmentID = nil } } }
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
                        }
                    },
                    source: previewRelay
                )
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
                            // Prune stale keys so the preview dismiss never
                            // animates back to a cell that has scrolled off
                            // or whose row left the list.
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

}

// MARK: - Size Preference Key

/// Propagates the container size of `FCLChatScreen` from a background `GeometryReader`
/// to the enclosing view hierarchy without wrapping the entire view tree in a
/// `GeometryReader` (which would cause subtree relayout on scene reactivation).
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
    /// Spacing between adjacent cells in the in-bubble attachment image grid.
    var attachmentItemSpacing: CGFloat = FCLAppearanceDefaults.attachmentItemSpacing
    /// Custom icon set for the three delivery status states.
    var statusIcons: FCLChatStatusIcons = FCLAppearanceDefaults.statusIcons
    /// Color tokens for the three delivery status states.
    var statusColors: FCLChatStatusColors = FCLAppearanceDefaults.statusColors
    /// Whether to render the delivery status glyph on outgoing messages.
    var showsStatusForOutgoing: Bool = FCLLayoutDefaults.showsStatusForOutgoing
    /// The list of context menu actions available on long-press.
    let contextMenuActions: [FCLContextMenuAction]
    /// Namespace for hero-style matched geometry transitions from grid thumbnails to full-screen preview.
    let heroNamespace: Namespace.ID
    /// Called when a media attachment is tapped, passing the tapped attachment to the parent.
    var onMediaTap: ((FCLAttachment) -> Void)?
    /// Forwards the attachment grid's per-cell window-space frames up to the chat screen,
    /// which stores them in ``FCLChatMediaPreviewRelay`` for the preview dismiss animation.
    var onAttachmentCellFramesChange: (([String: CGRect]) -> Void)?
    /// Forwards the attachment grid's disappear-invalidation event up to the
    /// chat screen so it can prune stale keys from the preview relay.
    var onAttachmentCellFramesInvalidate: ((Set<String>) -> Void)?

    /// Shared date formatter for rendering short time strings (e.g., "2:30 PM").
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Whether the status glyph should be rendered for this message.
    ///
    /// `true` only when the message is outgoing, has a non-nil status, and
    /// `showsStatusForOutgoing` is enabled. Always `false` for incoming messages.
    private var shouldShowStatus: Bool {
        guard message.direction == .outgoing, showsStatusForOutgoing else { return false }
        return message.status != nil
    }

    /// Invisible spacer that reserves space for the timestamp (and optional status glyph) overlay.
    /// Uses the same caption2 font as the visible timestamp. Placeholder is wide enough
    /// for the widest locale time (e.g., "00:00 AM" + padding), plus extra room for the
    /// status glyph when applicable.
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

    /// Renders the context menu action buttons for long-press interactions.
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
    @ViewBuilder
    private func bubbleContent(tailStyle: FCLBubbleTailStyle) -> some View {
        let textColor: Color = isSender ? senderTextColor.color : receiverTextColor.color
        let timeColor: Color = textColor.opacity(0.6)
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
            // When text follows below the grid, the mask flattens the grid's bottom edge.
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
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
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
                        .offset(y: 3)
                        .padding(.trailing, 8)
                        .padding(.bottom, 4),
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
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
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
                    .offset(y: 3)
                    .padding(.trailing, 8)
                    .padding(.bottom, 4),
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

    /// Whether this message was sent by the current user (outgoing direction).
    private var isSender: Bool {
        message.direction == .outgoing
    }

    /// Returns the resolved color token for a given status, reading from `statusColors`.
    private func colorForStatus(_ status: FCLChatMessageStatus) -> FCLChatColorToken {
        switch status {
        case .created: return statusColors.created
        case .sent: return statusColors.sent
        case .read: return statusColors.read
        }
    }

    /// Returns the custom icon for a given status if one has been provided via the delegate,
    /// or `nil` to fall back to the built-in glyph in `FCLChatMessageStatusView`.
    private func iconForStatus(_ status: FCLChatMessageStatus) -> Image? {
        switch status {
        case .created: return statusIcons.created
        case .sent: return statusIcons.sent
        case .read: return statusIcons.read
        }
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

/// A wrapper view used in previews to provide a `Namespace.ID` to `FCLChatMessageRow`.
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
