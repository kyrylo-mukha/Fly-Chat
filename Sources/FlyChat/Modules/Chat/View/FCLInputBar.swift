#if canImport(UIKit)
import SwiftUI

/// The built-in message input bar displayed at the bottom of the chat screen on iOS.
///
/// `FCLInputBar` renders an expanding text field, an optional attachment button,
/// a send button, and an attachment preview strip. It supports multiple container
/// modes (`.allInRounded`, `.fieldOnlyRounded`, `.custom`) and liquid glass
/// surfaces on iOS 26+ with UIKit blur fallback below iOS 26.
///
/// This view is used internally by ``FCLChatScreen`` when no custom input bar is provided.
struct FCLInputBar: View {
    @Binding private var draftText: String
    private let placeholderText: String
    private let maxRows: Int?
    private let lineHeight: CGFloat?
    private let returnKeySends: Bool
    private let showAttachButton: Bool
    private let attachmentThumbnailSize: CGFloat
    private let containerMode: FCLInputBarContainerMode
    private let liquidGlass: Bool
    private let backgroundColor: FCLChatColorToken
    private let fieldBackgroundColor: FCLChatColorToken
    private let fieldCornerRadius: CGFloat
    private let contentInsets: FCLEdgeInsets
    private let elementSpacing: CGFloat
    private let font: FCLChatMessageFontConfiguration
    private let minimumTextLength: Int
    private let onSend: () -> Void
    @State private var showAttachmentPicker = false
    @State private var pickerDetent: PresentationDetent = .medium
    @GestureState private var composerPressed = false
    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.fclReducedTransparencyBackground) private var reducedBackground
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.fclPreviewReduceTransparency) private var previewReduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight
    /// Hoisted from ``FCLChatScreen`` so timeline tap and drag handlers can dismiss the keyboard
    /// via `@FocusState` instead of a UIKit `resignFirstResponder` call.
    private let composerFocusBinding: FocusState<Bool>.Binding
    /// Namespace for the source-anchored zoom transition (iOS 18+). Unused on iOS 17 — the sheet falls back to a slide-up.
    @Namespace private var pickerNamespace
    private let delegate: (any FCLChatDelegate)?
    @ObservedObject private var presenter: FCLChatPresenter
    private let availableHeight: CGFloat
    private let glassControlHeight: CGFloat = 44

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

    private var reduceTransparency: Bool { previewReduceTransparency ?? systemReduceTransparency }

    private var nativeInputGlassTint: FCLChatColorToken {
        colorScheme == .dark
            ? FCLChatColorToken(red: 0.20, green: 0.21, blue: 0.23, alpha: 0.48)
            : FCLChatColorToken(red: 0.98, green: 0.99, blue: 1.00, alpha: 0.62)
    }

    private var nativeInputGlassOcclusion: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.28)
    }

    private var resolvedStyle: FCLResolvedVisualStyle {
        FCLVisualStyleResolver.resolve(
            explicit: explicitStyle,
            delegate: delegateStyle,
            reduceTransparency: reduceTransparency
        )
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
        VStack(spacing: 0) {
            inputRow(resolvedMaxRows: resolvedMaxRows)
                .padding(contentInsets.edgeInsets)
        }
        .background(inputBarBackground)
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

    @ViewBuilder
    private var inputBarBackground: some View {
        if resolvedStyle == .opaque {
            backgroundColor.color
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func inputRow(resolvedMaxRows: Int) -> some View {
        switch resolvedStyle {
        case .liquidGlassNative, .liquidGlassFallback:
            glassInputRow(resolvedMaxRows: resolvedMaxRows)
        case .opaque:
            opaqueInputRow(resolvedMaxRows: resolvedMaxRows)
        }
    }

    @ViewBuilder
    private func glassInputRow(resolvedMaxRows: Int) -> some View {
        #if os(iOS)
        if #available(iOS 26, *), resolvedStyle == .liquidGlassNative {
            nativeLiquidGlassInputRow(resolvedMaxRows: resolvedMaxRows)
        } else {
            fallbackGlassInputRow(resolvedMaxRows: resolvedMaxRows)
        }
        #else
        fallbackGlassInputRow(resolvedMaxRows: resolvedMaxRows)
        #endif
    }

    @available(iOS 26, *)
    @ViewBuilder
    private func nativeLiquidGlassInputRow(resolvedMaxRows: Int) -> some View {
        HStack(alignment: .bottom, spacing: elementSpacing) {
            if showAttachButton {
                nativeInputIconButton(
                    systemImage: "paperclip",
                    foregroundStyle: AnyShapeStyle(FCLPalette.label),
                    isEnabled: true,
                    action: { presentAttachmentPicker() }
                )
                .accessibilityLabel("Attach file")
                .background(
                    Circle()
                        .fill(Color.clear)
                        .frame(width: glassControlHeight, height: glassControlHeight)
                        .allowsHitTesting(false)
                        .modifier(FCLPickerZoomSource(
                            sourceID: "FCLAttachmentPicker",
                            namespace: pickerNamespace
                        ))
                )
            }

            let composerShape = RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous)
            composerField(resolvedMaxRows: resolvedMaxRows)
                .frame(minHeight: glassControlHeight, alignment: .center)
                .background(nativeInputGlassBackground(shape: composerShape, isInteractive: true))
                .clipShape(composerShape)
                .contentShape(composerShape)
                .scaleEffect(composerPressed ? 1.018 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.84), value: composerPressed)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($composerPressed) { _, state, _ in
                            state = true
                        }
                )

            nativeInputIconButton(
                systemImage: "paperplane.fill",
                foregroundStyle: AnyShapeStyle(isSendButtonEnabled ? FCLAppearanceDefaults.senderBubbleColor.color : FCLPalette.tertiaryLabel),
                isEnabled: isSendButtonEnabled,
                action: { sendIfEnabled() }
            )
            .animation(.easeInOut(duration: 0.2), value: isSendButtonEnabled)
            .accessibilityLabel("Send message")
        }
        .frame(minHeight: glassControlHeight, alignment: .bottom)
    }

    @available(iOS 26, *)
    private func nativeInputIconButton(
        systemImage: String,
        foregroundStyle: AnyShapeStyle,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            guard isEnabled else { return }
            action()
        }) {
            Image(systemName: systemImage)
                .foregroundStyle(foregroundStyle)
                .frame(width: glassControlHeight, height: glassControlHeight)
        }
        .buttonStyle(FCLNativeInputIconButtonStyle(
            size: glassControlHeight,
            tint: nativeInputGlassTint,
            occlusion: nativeInputGlassOcclusion,
            isEnabled: isEnabled,
            reduceTransparency: reduceTransparency,
            reducedTransparencyBackground: reducedBackground,
            colorScheme: colorScheme,
            legibilityWeight: legibilityWeight
        ))
        .contentShape(Circle())
        .disabled(!isEnabled)
        .frame(width: glassControlHeight, height: glassControlHeight, alignment: .bottom)
    }

    @available(iOS 26, *)
    private func nativeInputGlassBackground<S: InsettableShape>(
        shape: S,
        isInteractive: Bool
    ) -> some View {
        ZStack {
            FCLLiquidGlassSurface(
                shape: shape,
                tint: nativeInputGlassTint,
                isInteractive: isInteractive,
                surfaceStyle: .regular,
                resolvedStyle: .liquidGlassNative,
                reduceTransparency: reduceTransparency,
                reducedTransparencyBackground: reducedBackground,
                colorScheme: colorScheme,
                legibilityWeight: legibilityWeight
            )
            shape.fill(nativeInputGlassOcclusion)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    @ViewBuilder
    private func fallbackGlassInputRow(resolvedMaxRows: Int) -> some View {
        HStack(alignment: .bottom, spacing: elementSpacing) {
            attachButtonIfNeeded
            composerField(resolvedMaxRows: resolvedMaxRows)
                .frame(minHeight: glassControlHeight, alignment: .center)
                .background(
                    FCLLiquidGlassSurface(
                        shape: RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous),
                        tint: nil,
                        isInteractive: true,
                        surfaceStyle: .clear,
                        resolvedStyle: resolvedStyle,
                        reduceTransparency: reduceTransparency,
                        reducedTransparencyBackground: reducedBackground,
                        colorScheme: colorScheme,
                        legibilityWeight: legibilityWeight
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                )
            sendButton
        }
        .frame(minHeight: glassControlHeight, alignment: .bottom)
    }

    @ViewBuilder
    private func opaqueInputRow(resolvedMaxRows: Int) -> some View {
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

    @ViewBuilder
    private func composerField(resolvedMaxRows: Int) -> some View {
        TextField(placeholderText, text: $draftText, axis: .vertical)
            .lineLimit(1...resolvedMaxRows)
            .font(font.font)
            .focused(composerFocusBinding)
            .submitLabel(returnKeySends ? .send : .return)
            .onSubmit { if returnKeySends { sendIfEnabled() } }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
    }

    @ViewBuilder
    private var attachButtonIfNeeded: some View {
        if showAttachButton {
            FCLGlassIconButton(
                systemImage: "paperclip",
                size: glassControlHeight,
                action: { presentAttachmentPicker() }
            )
            .frame(width: glassControlHeight, height: glassControlHeight, alignment: .bottom)
            .accessibilityLabel("Attach file")
            /// The transition source is attached to an invisible `Circle` so the zoom originates
            /// from the paperclip's visual bounds.
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

    private var sendButton: some View {
        let enabled = isSendButtonEnabled
        return FCLGlassIconButton(
            systemImage: "paperplane.fill",
            size: glassControlHeight,
            tint: nil,
            action: { sendIfEnabled() }
        )
        .foregroundStyle(FCLAppearanceDefaults.senderBubbleColor.color)
        .frame(width: glassControlHeight, height: glassControlHeight, alignment: .bottom)
        .opacity(enabled ? 1.0 : 0.4)
        .allowsHitTesting(enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .accessibilityLabel("Send message")
    }

    private var isSendButtonEnabled: Bool {
        Self.isSendEnabled(
            text: draftText,
            minimumLength: minimumTextLength,
            hasAttachments: false
        )
    }

    private func sendIfEnabled() {
        guard isSendButtonEnabled else { return }
        onSend()
    }
}

// MARK: - Legacy Liquid Glass Override

/// Applies `.fclVisualStyle(.liquidGlass)` only when the host explicitly opted into the deprecated
/// `FCLInputDelegate.liquidGlass` flag; `false` is treated as "no opinion" so the installed
/// `FCLVisualStyleDelegate` takes precedence.
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

private struct FCLNativeInputIconButtonStyle: ButtonStyle {
    let size: CGFloat
    let tint: FCLChatColorToken
    let occlusion: Color
    let isEnabled: Bool
    let reduceTransparency: Bool
    let reducedTransparencyBackground: FCLChatColorToken
    let colorScheme: ColorScheme
    let legibilityWeight: LegibilityWeight?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                ZStack {
                    FCLLiquidGlassSurface(
                        shape: Circle(),
                        tint: tint,
                        isInteractive: isEnabled,
                        surfaceStyle: .regular,
                        resolvedStyle: .liquidGlassNative,
                        reduceTransparency: reduceTransparency,
                        reducedTransparencyBackground: reducedTransparencyBackground,
                        colorScheme: colorScheme,
                        legibilityWeight: legibilityWeight
                    )
                    Circle().fill(occlusion)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .clipShape(Circle())
            .opacity(isEnabled ? 1.0 : 0.42)
            .scaleEffect(configuration.isPressed && isEnabled ? 1.08 : 1.0)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.84),
                value: configuration.isPressed
            )
            .frame(width: size, height: size)
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
    }
}
#endif

#endif
