#if canImport(UIKit)
import SwiftUI

/// The built-in message input bar displayed at the bottom of the chat screen on iOS.
///
/// `FCLInputBar` renders a floating, Telegram-style composer: a circular glass
/// attachment button, a rounded glass text capsule that grows with the draft, and a
/// circular glass send button. The elements float over the timeline with no background
/// plate, so chat content shows through and scrolls beneath the glass. Glass rendering
/// is driven by the library-wide ``FCLVisualStyleDelegate`` — native Liquid Glass on
/// iOS 26+, a `UIVisualEffectView` fallback on iOS 17/18.
///
/// This view is used internally by ``FCLChatScreen`` when no custom input bar is provided.
struct FCLInputBar: View {
    @Binding private var draftText: String
    private let placeholderText: String
    private let maxRows: Int?
    private let returnKeySends: Bool
    private let showAttachButton: Bool
    private let fieldCornerRadius: CGFloat
    private let contentInsets: FCLEdgeInsets
    private let elementSpacing: CGFloat
    private let font: FCLChatMessageFontConfiguration
    private let minimumTextLength: Int
    private let onSend: () -> Void
    @State private var showAttachmentPicker = false
    @State private var pickerDetent: PresentationDetent = .medium
    /// Hoisted from ``FCLChatScreen`` so timeline tap and drag handlers can dismiss the keyboard
    /// via `@FocusState` instead of a UIKit `resignFirstResponder` call.
    private let composerFocusBinding: FocusState<Bool>.Binding
    /// Namespace for the source-anchored zoom transition (iOS 18+). Unused on iOS 17 — the sheet falls back to a slide-up.
    @Namespace private var pickerNamespace
    private let delegate: (any FCLChatDelegate)?
    @ObservedObject private var presenter: FCLChatPresenter
    private let availableHeight: CGFloat

    /// Creates an input bar with the given configuration.
    ///
    /// - Parameters:
    ///   - draftText: Binding to the current draft message text.
    ///   - delegate: Optional delegate providing appearance and attachment configuration.
    ///   - presenter: The chat presenter used to route attachment sends.
    ///   - placeholderText: Placeholder text shown when the field is empty.
    ///   - maxRows: Maximum visible text rows before scrolling. `nil` for auto-calculation.
    ///   - returnKeySends: Whether the Return key sends the message.
    ///   - showAttachButton: Whether to show the attachment button.
    ///   - fieldCornerRadius: Corner radius of the glass text capsule.
    ///   - contentInsets: Padding around the floating composer row.
    ///   - elementSpacing: Spacing between the composer elements.
    ///   - font: Font configuration for the input text.
    ///   - minimumTextLength: Minimum character count to enable the send button.
    ///   - availableHeight: Total screen height for auto row calculation.
    ///   - composerFocusBinding: Focus binding hoisted from ``FCLChatScreen`` so
    ///     timeline tap and drag handlers can dismiss the composer keyboard
    ///     declaratively via SwiftUI's `@FocusState`.
    ///   - onSend: Callback invoked on the send action.
    init(
        draftText: Binding<String>,
        delegate: (any FCLChatDelegate)?,
        presenter: FCLChatPresenter,
        placeholderText: String = FCLInputDefaults.placeholderText,
        maxRows: Int? = FCLInputDefaults.maxRows,
        returnKeySends: Bool = FCLInputDefaults.returnKeySends,
        showAttachButton: Bool = FCLInputDefaults.showAttachButton,
        fieldCornerRadius: CGFloat = FCLInputDefaults.fieldCornerRadius,
        contentInsets: FCLEdgeInsets = FCLInputDefaults.contentInsets,
        elementSpacing: CGFloat = FCLInputDefaults.elementSpacing,
        font: FCLChatMessageFontConfiguration = FCLAppearanceDefaults.messageFont,
        minimumTextLength: Int = FCLInputDefaults.minimumTextLength,
        availableHeight: CGFloat,
        composerFocusBinding: FocusState<Bool>.Binding,
        onSend: @escaping () -> Void
    ) {
        self._draftText = draftText
        self.delegate = delegate
        self.presenter = presenter
        self.placeholderText = placeholderText
        self.maxRows = maxRows
        self.returnKeySends = returnKeySends
        self.showAttachButton = showAttachButton
        self.fieldCornerRadius = fieldCornerRadius
        self.contentInsets = contentInsets
        self.elementSpacing = elementSpacing
        self.font = font
        self.minimumTextLength = minimumTextLength
        self.availableHeight = availableHeight
        self.composerFocusBinding = composerFocusBinding
        self.onSend = onSend
    }

    var body: some View {
        let resolvedMaxRows = resolveMaxRows(forAvailableHeight: availableHeight)
        inputBarContent(resolvedMaxRows: resolvedMaxRows)
    }

    private func resolveMaxRows(forAvailableHeight height: CGFloat) -> Int {
        FCLInputBar.resolveMaxRows(forAvailableHeight: height, explicitMaxRows: maxRows)
    }

    /// Static entry point for the same row-count formula, usable in unit tests
    /// and in the pure body expression without a live `maxRows` capture.
    ///
    /// - Parameters:
    ///   - height: Available container height in points.
    ///   - explicitMaxRows: An optional host-supplied override. When non-nil, it
    ///     is returned directly; when `nil`, the formula is applied.
    /// - Returns: The clamped maximum row count in `[4, 10]`.
    static func resolveMaxRows(forAvailableHeight height: CGFloat, explicitMaxRows: Int? = nil) -> Int {
        if let maxRows = explicitMaxRows { return maxRows }
        return min(max(Int(height / 160), 4), 10)
    }

    @ViewBuilder
    private func inputBarContent(resolvedMaxRows: Int) -> some View {
        HStack(alignment: .bottom, spacing: elementSpacing) {
            attachButtonIfNeeded
            composerField(resolvedMaxRows: resolvedMaxRows)
            sendButton
        }
        .padding(contentInsets.edgeInsets)
        .sheet(isPresented: $showAttachmentPicker) {
            FCLAttachmentPickerHost(
                chatPresenter: presenter,
                delegate: delegate?.attachment,
                onDismiss: { showAttachmentPicker = false },
                zoomNamespace: pickerNamespace
            )
            .presentationDetents([.medium, .large], selection: $pickerDetent)
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(16)
            .presentationBackgroundInteraction(.disabled)
            .interactiveDismissDisabled(false)
        }
    }

    @ViewBuilder
    private func composerField(resolvedMaxRows: Int) -> some View {
        FCLGlassContainer(cornerRadius: fieldCornerRadius, interactive: true) {
            TextField(placeholderText, text: $draftText, axis: .vertical)
                .lineLimit(1...resolvedMaxRows)
                .font(font.font)
                .focused(composerFocusBinding)
                .submitLabel(returnKeySends ? .send : .return)
                .onSubmit { if returnKeySends { onSend() } }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
        }
    }

    @ViewBuilder
    private var attachButtonIfNeeded: some View {
        if showAttachButton {
            FCLGlassIconButton(
                systemImage: "paperclip",
                size: 44,
                action: { presentAttachmentPicker() }
            )
            .accessibilityLabel("Attach file")
            // Zoom source on an invisible 44pt circle so the picker zoom originates from the
            // paperclip's visual bounds, not from the glass button's padded frame.
            .background(
                Circle()
                    .fill(Color.clear)
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .modifier(FCLPickerZoomSource(
                        sourceID: "FCLAttachmentPicker",
                        namespace: pickerNamespace
                    ))
            )
        }
    }

    private func presentAttachmentPicker() {
        composerFocusBinding.wrappedValue = false
        showAttachmentPicker = true
    }

    /// Determines whether the send button should be enabled based on text length and attachments.
    ///
    /// - Parameters:
    ///   - text: The current draft text.
    ///   - minimumLength: The minimum trimmed character count required.
    ///   - hasAttachments: Whether any attachments are queued.
    /// - Returns: `true` if the send action should be allowed.
    static func isSendEnabled(text: String, minimumLength: Int, hasAttachments: Bool) -> Bool {
        hasAttachments || text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumLength
    }

    /// Send-button tint: the host's outgoing-bubble color, so the prominent glass
    /// send circle matches the conversation's accent.
    private var sendTint: FCLChatColorToken {
        delegate?.appearance?.senderBubbleColor ?? FCLAppearanceDefaults.senderBubbleColor
    }

    private var sendButton: some View {
        let enabled = Self.isSendEnabled(
            text: draftText,
            minimumLength: minimumTextLength,
            hasAttachments: false
        )
        return FCLGlassIconButton(
            systemImage: "paperplane.fill",
            size: 44,
            tint: sendTint,
            action: onSend
        )
        .opacity(enabled ? 1.0 : 0.4)
        .allowsHitTesting(enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .accessibilityLabel("Send message")
    }
}

// MARK: - Attachment Picker Host

/// Owns the attachment picker's presenter and gallery data source as `@StateObject` so their
/// identity persists across `FCLInputBar` body re-evaluations.
private struct FCLAttachmentPickerHost: View {
    @StateObject private var presenter: FCLAttachmentPickerPresenter
    @StateObject private var galleryDataSource: FCLGalleryDataSource
    private let delegate: (any FCLAttachmentDelegate)?
    private let onDismiss: () -> Void
    private let zoomNamespace: Namespace.ID

    init(
        chatPresenter: FCLChatPresenter,
        delegate: (any FCLAttachmentDelegate)?,
        onDismiss: @escaping () -> Void,
        zoomNamespace: Namespace.ID
    ) {
        _presenter = StateObject(wrappedValue: FCLAttachmentPickerPresenter(
            delegate: delegate,
            onSend: { [weak chatPresenter] attachments, caption in
                chatPresenter?.handleAttachmentsDeferred(attachments, caption: caption)
            },
            onSendError: { [weak chatPresenter] message in
                chatPresenter?.reportSendError(message)
            }
        ))
        _galleryDataSource = StateObject(wrappedValue: FCLGalleryDataSource(
            isVideoEnabled: delegate?.isVideoEnabled ?? true
        ))
        self.delegate = delegate
        self.onDismiss = onDismiss
        self.zoomNamespace = zoomNamespace
    }

    var body: some View {
        FCLAttachmentPickerSheet(
            presenter: presenter,
            galleryDataSource: galleryDataSource,
            delegate: delegate,
            onDismiss: onDismiss
        )
        .modifier(FCLPickerZoomDestination(
            sourceID: "FCLAttachmentPicker",
            namespace: zoomNamespace
        ))
    }
}

// MARK: - Previews

#if DEBUG
struct FCLInputBar_Previews: PreviewProvider {
    static var previews: some View {
        FCLInputBarPreviewWrapper(text: "")
            .previewDisplayName("Empty (Placeholder Visible)")
            .previewLayout(.fixed(width: 390, height: 120))

        FCLInputBarPreviewWrapper(text: "Hello, how are you?")
            .previewDisplayName("With Draft Text")
            .previewLayout(.fixed(width: 390, height: 120))

        FCLInputBarPreviewWrapper(text: "A")
            .previewDisplayName("Short Text (Below Min Length)")
            .previewLayout(.fixed(width: 390, height: 120))
    }
}

private struct FCLInputBarPreviewWrapper: View {
    @State var text: String
    @StateObject private var presenter = FCLChatPresenter(
        messages: [],
        currentUser: FCLChatMessageSender(id: "preview", displayName: "Preview")
    )
    @FocusState private var composerFocused: Bool

    var body: some View {
        FCLInputBar(
            draftText: $text,
            delegate: nil,
            presenter: presenter,
            availableHeight: 700,
            composerFocusBinding: $composerFocused,
            onSend: {}
        )
        .background(
            LinearGradient(colors: [.blue.opacity(0.25), .purple.opacity(0.25)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}
#endif

#endif
