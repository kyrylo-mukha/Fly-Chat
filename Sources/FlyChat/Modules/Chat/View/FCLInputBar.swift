#if canImport(UIKit)
import SwiftUI

/// The built-in message input bar displayed at the bottom of the chat screen on iOS.
///
/// Each element (attach button, text field, send button) carries its own independent
/// glass surface so chat content scrolls visibly behind the bar.
struct FCLInputBar: View {
    @Binding private var draftText: String
    private let placeholderText: String
    private let maxRows: Int?
    private let lineHeight: CGFloat?
    private let returnKeySends: Bool
    private let showAttachButton: Bool
    private let attachmentThumbnailSize: CGFloat
    private let containerMode: FCLInputBarContainerMode
    private let fieldCornerRadius: CGFloat
    private let contentInsets: FCLEdgeInsets
    private let elementSpacing: CGFloat
    private let font: FCLChatMessageFontConfiguration
    private let minimumTextLength: Int
    private let onSend: () -> Void
    @State private var showAttachmentPicker = false
    @State private var pickerDetent: PresentationDetent = .medium
    private let composerFocusBinding: FocusState<Bool>.Binding
    @Namespace private var pickerNamespace
    private let delegate: (any FCLChatDelegate)?
    @ObservedObject private var presenter: FCLChatPresenter
    private let availableHeight: CGFloat

    /// Creates an input bar with the given configuration.
    ///
    /// - Parameters:
    ///   - draftText: Binding to the current draft message text.
    ///   - delegate: Optional delegate providing attachment picker configuration.
    ///   - presenter: The chat presenter used to route attachment sends.
    ///   - placeholderText: Placeholder text shown when the field is empty.
    ///   - maxRows: Maximum visible text rows before scrolling. `nil` for auto-calculation.
    ///   - lineHeight: Explicit line height override. `nil` uses the font's native line height.
    ///   - returnKeySends: Whether Return key sends the message.
    ///   - showAttachButton: Whether to show the attachment button.
    ///   - attachmentThumbnailSize: Thumbnail size for attachment previews.
    ///   - containerMode: Visual grouping mode for the input bar elements.
    ///   - fieldCornerRadius: Corner radius of the text field glass container.
    ///   - contentInsets: Padding insets around the input bar content.
    ///   - elementSpacing: Spacing between input bar elements.
    ///   - font: Font configuration for the input text.
    ///   - minimumTextLength: Minimum character count to enable the send button.
    ///   - availableHeight: Total screen height for auto row calculation.
    ///   - composerFocusBinding: Focus binding hoisted from ``FCLChatScreen`` so
    ///     timeline tap and drag handlers can dismiss the composer keyboard
    ///     declaratively via SwiftUI's `@FocusState`.
    ///   - onSend: Callback invoked on send action.
    init(
        draftText: Binding<String>,
        delegate: (any FCLChatDelegate)?,
        presenter: FCLChatPresenter,
        placeholderText: String = FCLInputDefaults.placeholderText,
        maxRows: Int? = FCLInputDefaults.maxRows,
        lineHeight: CGFloat? = FCLInputDefaults.lineHeight,
        returnKeySends: Bool = FCLInputDefaults.returnKeySends,
        showAttachButton: Bool = FCLInputDefaults.showAttachButton,
        attachmentThumbnailSize: CGFloat = FCLInputDefaults.attachmentThumbnailSize,
        containerMode: FCLInputBarContainerMode = FCLInputDefaults.containerMode,
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
        self.lineHeight = lineHeight
        self.returnKeySends = returnKeySends
        self.showAttachButton = showAttachButton
        self.attachmentThumbnailSize = attachmentThumbnailSize
        self.containerMode = containerMode
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

    /// - Parameters:
    ///   - height: Available container height in points.
    ///   - explicitMaxRows: An optional host-supplied override. When non-nil, it
    ///     is returned directly; when `nil`, the formula is applied.
    /// - Returns: The clamped maximum row count in `[4, 10]`.
    static func resolveMaxRows(forAvailableHeight height: CGFloat, explicitMaxRows: Int? = nil) -> Int {
        if let maxRows = explicitMaxRows { return maxRows }
        return min(max(Int(height / 160), 4), 10)
    }

    // MARK: - Content

    @ViewBuilder
    private func inputBarContent(resolvedMaxRows: Int) -> some View {
        inputRow(resolvedMaxRows: resolvedMaxRows)
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

    // MARK: - Layout Modes

    @ViewBuilder
    private func inputRow(resolvedMaxRows: Int) -> some View {
        switch containerMode {
        case .allInRounded(let insets):
            FCLGlassContainer(cornerRadius: fieldCornerRadius) {
                HStack(alignment: .bottom, spacing: elementSpacing) {
                    attachButtonIfNeeded
                    composerField(resolvedMaxRows: resolvedMaxRows)
                    sendButton
                }
                .padding(insets.edgeInsets)
            }

        case .fieldOnlyRounded:
            HStack(alignment: .bottom, spacing: elementSpacing) {
                attachButtonIfNeeded
                FCLGlassContainer(cornerRadius: fieldCornerRadius) {
                    composerField(resolvedMaxRows: resolvedMaxRows)
                }
                sendButton
            }

        case .custom:
            HStack(alignment: .bottom, spacing: elementSpacing) {
                attachButtonIfNeeded
                composerField(resolvedMaxRows: resolvedMaxRows)
                sendButton
            }
        }
    }

    // MARK: - Elements

    @ViewBuilder
    private func composerField(resolvedMaxRows: Int) -> some View {
        TextField(placeholderText, text: $draftText, axis: .vertical)
            .lineLimit(1...resolvedMaxRows)
            .font(font.font)
            .focused(composerFocusBinding)
            .submitLabel(returnKeySends ? .send : .return)
            .onSubmit { if returnKeySends { onSend() } }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
    }

    @ViewBuilder
    private var attachButtonIfNeeded: some View {
        if showAttachButton {
            FCLGlassIconButton(
                systemImage: "paperclip",
                size: 36,
                action: { presentAttachmentPicker() }
            )
            .accessibilityLabel("Attach file")
            .background(
                Circle()
                    .fill(Color.clear)
                    .frame(width: 36, height: 36)
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

    private var sendButton: some View {
        let enabled = Self.isSendEnabled(
            text: draftText,
            minimumLength: minimumTextLength,
            hasAttachments: false
        )
        return FCLGlassIconButton(
            systemImage: "paperplane.fill",
            size: 36,
            tint: FCLAppearanceDefaults.senderBubbleColor,
            action: onSend
        )
        .opacity(enabled ? 1.0 : 0.4)
        .allowsHitTesting(enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .accessibilityLabel("Send message")
    }
}

// MARK: - Attachment Picker Host

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
    }
}
#endif

#endif
