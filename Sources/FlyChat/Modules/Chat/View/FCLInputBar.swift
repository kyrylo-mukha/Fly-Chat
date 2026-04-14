#if canImport(UIKit)
import SwiftUI
import UIKit

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
    /// The current measured height of the expanding text view.
    @State private var textViewHeight: CGFloat = 40
    /// Whether the attachment picker sheet is presented.
    @State private var showAttachmentPicker = false
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
        self.onSend = onSend
    }

    public var body: some View {
        let resolvedMaxRows = resolveMaxRows(forAvailableHeight: availableHeight)
        let uiFont = resolvedUIFont
        let rowHeight = lineHeight ?? uiFont.lineHeight
        let maxTextHeight = rowHeight * CGFloat(resolvedMaxRows) + 20 // 20 = textContainerInset top+bottom

        inputBarContent(maxTextHeight: maxTextHeight, uiFont: uiFont)
    }

    /// Auto-calculate max rows from available screen height.
    /// Formula: clamp(4, floor(height / 160), 10)
    private func resolveMaxRows(forAvailableHeight height: CGFloat) -> Int {
        if let maxRows { return maxRows }
        return min(max(Int(height / 160), 4), 10)
    }

    /// Builds the full input bar content with the input row and attachment picker sheet.
    @ViewBuilder
    private func inputBarContent(maxTextHeight: CGFloat, uiFont: UIFont) -> some View {
        VStack(spacing: 0) {
            inputRow(maxTextHeight: maxTextHeight, uiFont: uiFont)
                .padding(contentInsets.edgeInsets)
        }
        .background(
            FCLInputBarBackground(
                liquidGlass: liquidGlass,
                backgroundColor: backgroundColor
            )
        )
        .sheet(isPresented: $showAttachmentPicker) {
            FCLAttachmentPickerHost(
                chatPresenter: presenter,
                delegate: delegate?.attachment,
                onDismiss: { showAttachmentPicker = false }
            )
        }
    }

    /// Lays out the attach button, expanding text field, and send button according to the container mode.
    @ViewBuilder
    private func inputRow(maxTextHeight: CGFloat, uiFont: UIFont) -> some View {
        switch containerMode {
        case .allInRounded(let insets):
            HStack(alignment: .bottom, spacing: elementSpacing) {
                attachButtonIfNeeded
                expandingField(maxTextHeight: maxTextHeight, uiFont: uiFont)
                sendButton
            }
            .padding(insets.edgeInsets)
            .background(fieldBackgroundColor.color)
            .cornerRadius(fieldCornerRadius)

        case .fieldOnlyRounded:
            HStack(alignment: .bottom, spacing: elementSpacing) {
                attachButtonIfNeeded
                expandingField(maxTextHeight: maxTextHeight, uiFont: uiFont)
                    .background(fieldBackgroundColor.color)
                    .cornerRadius(fieldCornerRadius)
                sendButton
            }

        case .custom:
            HStack(alignment: .bottom, spacing: elementSpacing) {
                attachButtonIfNeeded
                expandingField(maxTextHeight: maxTextHeight, uiFont: uiFont)
                sendButton
            }
        }
    }

    /// Creates the expanding text view with the resolved font and max height.
    private func expandingField(maxTextHeight: CGFloat, uiFont: UIFont) -> some View {
        FCLExpandingTextView(
            text: $draftText,
            font: uiFont,
            maxHeight: maxTextHeight,
            placeholder: placeholderText,
            fieldBackgroundColor: UIColor(fieldBackgroundColor.color),
            cornerRadius: fieldCornerRadius,
            returnKeySends: returnKeySends,
            onSend: onSend,
            height: $textViewHeight
        )
        .frame(height: textViewHeight)
    }

    /// Conditionally renders the paperclip attachment button.
    @ViewBuilder
    private var attachButtonIfNeeded: some View {
        if showAttachButton {
            Button(action: { showAttachmentPicker = true }) {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Attach file")
        }
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
        return Button(action: onSend) {
            Image(systemName: "paperplane.fill")
                .foregroundColor(.white)
                .padding(8)
                .background(Color.blue)
                .clipShape(Circle())
        }
        .opacity(enabled ? 1.0 : 0.4)
        .allowsHitTesting(enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .accessibilityLabel("Send message")
    }

    /// Resolves the `UIFont` from the font configuration, falling back to system font.
    private var resolvedUIFont: UIFont {
        if let family = font.familyName, !family.isEmpty {
            return UIFont(name: family, size: font.size) ?? UIFont.systemFont(ofSize: font.size)
        }
        return UIFont.systemFont(ofSize: font.size, weight: font.weight.uiFontWeight)
    }
}

// MARK: - Attachment Picker Host

/// A private wrapper that owns the attachment picker's presenter and gallery data source
/// as `@StateObject` so their identity persists across `FCLInputBar` body re-evaluations.
/// Without this, the picker presenter would be re-instantiated on every parent render,
/// losing `selectedAssets` state after the first selection.
private struct FCLAttachmentPickerHost: View {
    @StateObject private var presenter: FCLAttachmentPickerPresenter
    @StateObject private var galleryDataSource: FCLGalleryDataSource
    private let delegate: (any FCLAttachmentDelegate)?
    private let onDismiss: () -> Void

    init(
        chatPresenter: FCLChatPresenter,
        delegate: (any FCLAttachmentDelegate)?,
        onDismiss: @escaping () -> Void
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
    }

    var body: some View {
        FCLAttachmentPickerSheet(
            presenter: presenter,
            galleryDataSource: galleryDataSource,
            delegate: delegate,
            onDismiss: onDismiss
        )
    }
}

// MARK: - UIFont Weight Bridge

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

    var body: some View {
        FCLInputBar(
            draftText: $text,
            delegate: nil,
            presenter: presenter,
            availableHeight: 700,
            onSend: {}
        )
    }
}
#endif

/// Bridge from ``FCLChatFontWeight`` to `UIFont.Weight` for UIKit text view usage.
extension FCLChatFontWeight {
    /// The corresponding `UIFont.Weight` value.
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}
#endif
