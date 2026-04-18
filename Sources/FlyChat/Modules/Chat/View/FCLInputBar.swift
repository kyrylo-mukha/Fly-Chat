#if canImport(UIKit)
import SwiftUI

/// The built-in message input bar displayed at the bottom of the chat screen on iOS.
///
/// `FCLInputBar` renders an expanding text field, an optional attachment button,
/// a send button, and an attachment preview strip. It supports multiple container
/// modes (`.allInRounded`, `.fieldOnlyRounded`, `.custom`) and optional liquid glass
/// background effects on iOS 26+.
///
/// This view is used internally by ``FCLChatScreen`` when no custom input bar is provided.
struct FCLInputBar: View {
    /// Two-way binding to the current draft message text.
    @Binding private var draftText: String
    /// Placeholder string shown when the text field is empty.
    private let placeholderText: String
    /// Optional maximum number of visible text rows. When `nil`, auto-calculated from available height.
    private let maxRows: Int?
    /// Optional explicit line height for the text view. When `nil`, the font's native line height is used.
    private let lineHeight: CGFloat?
    /// Whether pressing the Return key triggers a send instead of inserting a newline.
    private let returnKeySends: Bool
    /// Whether the paperclip attachment button is shown.
    private let showAttachButton: Bool
    /// The size (in points) for attachment thumbnail previews in the strip above the input row.
    private let attachmentThumbnailSize: CGFloat
    /// The container mode controlling how input bar elements are grouped visually.
    private let containerMode: FCLInputBarContainerMode
    /// Whether the input bar background uses a liquid glass / blur material effect.
    private let liquidGlass: Bool
    /// The background color for the entire input bar container.
    private let backgroundColor: FCLChatColorToken
    /// The background color for the text input field.
    private let fieldBackgroundColor: FCLChatColorToken
    /// The corner radius of the text input field.
    private let fieldCornerRadius: CGFloat
    /// Padding insets around the input bar content.
    private let contentInsets: FCLEdgeInsets
    /// Spacing between the attach button, text field, and send button.
    private let elementSpacing: CGFloat
    /// Font configuration for the input text, matching the message bubble font.
    private let font: FCLChatMessageFontConfiguration
    /// Minimum trimmed character count required before the send button enables.
    private let minimumTextLength: Int
    /// Callback invoked when the user taps the send button or presses Return (if `returnKeySends` is true).
    private let onSend: () -> Void
    /// Whether the attachment picker sheet is presented.
    @State private var showAttachmentPicker = false
    /// Current detent of the presented attachment picker sheet. The sheet starts
    /// at `.medium`; the user can drag up to `.large` and back, or drag below
    /// `.medium` to dismiss.
    @State private var pickerDetent: PresentationDetent = .medium
    /// Focus binding for the composer text field, hoisted from
    /// ``FCLChatScreen`` so the chat timeline tap and drag handlers can
    /// dismiss the keyboard declaratively via SwiftUI's `@FocusState` instead
    /// of a UIKit `resignFirstResponder` call.
    private let composerFocusBinding: FocusState<Bool>.Binding
    /// Shared namespace for the source-anchored zoom transition (iOS 18+).
    /// Pairs the attach button (source) with the picker sheet (destination)
    /// through the matching `sourceID`. On iOS 17 the namespace is unused —
    /// the modifiers no-op and the sheet uses a plain slide-up.
    @Namespace private var pickerNamespace
    /// Optional delegate providing tab configuration and compression settings for the attachment picker.
    private let delegate: (any FCLChatDelegate)?
    /// The chat presenter used to route attachment sends.
    @ObservedObject private var presenter: FCLChatPresenter

    /// The total available screen height, used to auto-calculate max rows when not explicitly set.
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
    ///   - liquidGlass: Whether to use liquid glass / blur background.
    ///   - backgroundColor: Background color of the input bar container.
    ///   - fieldBackgroundColor: Background color of the text field.
    ///   - fieldCornerRadius: Corner radius of the text field.
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
        liquidGlass: Bool = FCLInputDefaults.liquidGlass,
        backgroundColor: FCLChatColorToken = FCLInputDefaults.backgroundColor,
        fieldBackgroundColor: FCLChatColorToken = FCLInputDefaults.fieldBackgroundColor,
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
        self.liquidGlass = liquidGlass
        self.backgroundColor = backgroundColor
        self.fieldBackgroundColor = fieldBackgroundColor
        self.fieldCornerRadius = fieldCornerRadius
        self.contentInsets = contentInsets
        self.elementSpacing = elementSpacing
        self.font = font
        self.minimumTextLength = minimumTextLength
        self.availableHeight = availableHeight
        self.composerFocusBinding = composerFocusBinding
        self.onSend = onSend
    }

    public var body: some View {
        let resolvedMaxRows = resolveMaxRows(forAvailableHeight: availableHeight)
        inputBarContent(resolvedMaxRows: resolvedMaxRows)
    }

    /// Auto-calculate max rows from available screen height.
    /// Formula: clamp(4, floor(height / 160), 10)
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

    /// Builds the full input bar content with the input row and the attachment
    /// picker sheet.
    ///
    /// Glass resolution: the container inherits the library-wide style from the
    /// `FCLVisualStyleDelegate` installed on ``FCLChatScreen``. The deprecated
    /// `liquidGlass` init flag is honored only when the host explicitly set it
    /// to `true` — passing `false` is treated as "no opinion" so new installs
    /// take the library default (`.liquidGlass`) instead of being forced onto
    /// the opaque path. Tint is intentionally not routed from the delegate's
    /// `backgroundColor` when glass is active: painting the light-gray fallback
    /// color on top of glass desaturates it into a gray rectangle, which is
    /// what the pre-fix build produced. Opaque style (explicit `.default` or
    /// reduce-transparency) falls back to the delegate-provided background
    /// through ``FCLGlassContainer``'s own opaque branch.
    @ViewBuilder
    private func inputBarContent(resolvedMaxRows: Int) -> some View {
        FCLGlassContainer(cornerRadius: 0, tint: nil) {
            VStack(spacing: 0) {
                inputRow(resolvedMaxRows: resolvedMaxRows)
                    .padding(contentInsets.edgeInsets)
            }
        }
        .modifier(FCLInputBarLegacyLiquidGlassOverride(optedIn: liquidGlass))
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

    /// Lays out the attach button, expanding text field, and send button according to the container mode.
    @ViewBuilder
    private func inputRow(resolvedMaxRows: Int) -> some View {
        switch containerMode {
        case .allInRounded(let insets):
            HStack(alignment: .bottom, spacing: elementSpacing) {
                attachButtonIfNeeded
                composerField(resolvedMaxRows: resolvedMaxRows)
                sendButton
            }
            .padding(insets.edgeInsets)
            .background(fieldBackgroundColor.color)
            .cornerRadius(fieldCornerRadius)

        case .fieldOnlyRounded:
            HStack(alignment: .bottom, spacing: elementSpacing) {
                attachButtonIfNeeded
                composerField(resolvedMaxRows: resolvedMaxRows)
                    .background(fieldBackgroundColor.color)
                    .cornerRadius(fieldCornerRadius)
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

    /// Native SwiftUI multi-line composer that grows vertically with content
    /// and clamps at `resolvedMaxRows`. Replaces the prior `UITextView`
    /// wrapper. Focus is bound to the hoisted ``composerFocusBinding`` so the
    /// keyboard can be dismissed declaratively from anywhere on the chat
    /// screen (timeline tap, drag, picker open).
    @ViewBuilder
    private func composerField(resolvedMaxRows: Int) -> some View {
        TextField(placeholderText, text: $draftText, axis: .vertical)
            .lineLimit(1...resolvedMaxRows)
            .font(font.font)
            .focused(composerFocusBinding)
            .submitLabel(returnKeySends ? .send : .return)
            .onSubmit { if returnKeySends { onSend() } }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    /// Conditionally renders the paperclip attachment button.
    @ViewBuilder
    private var attachButtonIfNeeded: some View {
        if showAttachButton {
            FCLGlassIconButton(
                systemImage: "paperclip",
                size: 36,
                action: { presentAttachmentPicker() }
            )
            .accessibilityLabel("Attach file")
            // Attach the matched-transition source to an invisible 36×36 Circle
            // so the zoom originates from the paperclip's visual bounds rather
            // than from `.buttonStyle(.glass)`'s padded outer frame on iOS 26.
            // See docs/superpowers/knowledge/2026-04-17-picker-chrome-overhaul.md (Q1).
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

    /// Opens the attachment picker sheet: dismisses the composer keyboard
    /// declaratively via the hoisted focus binding, then flips the
    /// presentation state. On iOS 18+ the matched-source zoom morph is driven
    /// by the system once the sheet presents; on iOS 17 the sheet uses a
    /// plain slide-up.
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

    /// The circular send button that is visually disabled when send conditions are not met.
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

// MARK: - Legacy Liquid Glass Override

/// Applies `.fclVisualStyle(.liquidGlass)` only when the host explicitly opted
/// into the deprecated `FCLInputDelegate.liquidGlass` flag. Passing `false` is
/// a no-op, preserving whatever style the installed
/// ``FCLVisualStyleDelegate`` provides. The legacy flag's `false` default used
/// to force an opaque fallback, which painted the input bar as a solid gray
/// rectangle on every new install; dropping that override is what restores
/// glass rendering by default.
private struct FCLInputBarLegacyLiquidGlassOverride: ViewModifier {
    let optedIn: Bool

    func body(content: Content) -> some View {
        if optedIn {
            content.fclVisualStyle(.liquidGlass)
        } else {
            content
        }
    }
}

// MARK: - Attachment Picker Host

/// A private wrapper that owns the attachment picker's presenter and gallery data source
/// as `@StateObject` so their identity persists across `FCLInputBar` body re-evaluations.
/// Without this, the picker presenter would be re-instantiated on every parent render,
/// losing `selectedAssets` state after the first selection.
///
/// The host applies the `FCLPickerZoomDestination` modifier to its body so the iOS 18+
/// system-driven zoom transition can morph from the matching attach-button source.
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
                // Append the outgoing bubble synchronously. The picker sheet's
                // synchronized dismiss animation runs in parallel; both the
                // modal collapse and the bubble slide-in share the same UI
                // tick instead of being chained through a sleep-based delay.
                chatPresenter?.handleAttachmentsDeferred(
                    attachments,
                    caption: caption
                )
            },
            onSendError: { [weak chatPresenter] message in
                // Send-path errors must surface on the chat screen, not the
                // already-dismissed picker sheet. See FCLChatPresenter.reportSendError.
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
