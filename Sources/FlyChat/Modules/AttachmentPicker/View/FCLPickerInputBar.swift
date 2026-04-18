#if os(iOS)
import SwiftUI

// MARK: - FCLPickerInputBar

/// A caption input bar shown at the bottom of the attachment picker sheet when the user
/// has selected one or more gallery assets.
///
/// It renders a rounded text field with the placeholder "Add a caption…" alongside a
/// circular send button. The send button is enabled only when `hasSelection` is `true`
/// (i.e. at least one asset is selected). This view does not include an attachment button —
/// attachment selection is handled by the gallery tab above.
///
/// Caption focus is owned by the enclosing sheet (``FCLAttachmentPickerSheet``) via a
/// hoisted `@FocusState` binding so the sheet can dismiss the keyboard synchronously
/// alongside the send animation.
struct FCLPickerInputBar: View {
    /// Two-way binding to the caption string typed by the user.
    @Binding var captionText: String
    /// Whether the user has selected at least one asset. Controls send button availability.
    let hasSelection: Bool
    /// Background color for the text field container.
    let fieldBackgroundColor: Color
    /// Corner radius applied to the text field container.
    let fieldCornerRadius: CGFloat
    /// Focus binding hoisted from the enclosing sheet so the sheet can drop
    /// caption focus immediately before invoking send.
    let captionFocusBinding: FocusState<Bool>.Binding
    /// Callback invoked when the user taps the send button.
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            captionField
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(FCLPalette.secondarySystemBackground)
    }

    // MARK: - Private

    private var captionField: some View {
        TextField("Add a caption...", text: $captionText)
            .focused(captionFocusBinding)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(fieldBackgroundColor)
            .cornerRadius(fieldCornerRadius)
            .font(.system(size: 15))
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "paperplane.fill")
                .foregroundColor(.white)
                .padding(9)
                .background(hasSelection ? Color.blue : FCLPalette.systemGray3)
                .clipShape(Circle())
        }
        .disabled(!hasSelection)
        .animation(.easeInOut(duration: 0.2), value: hasSelection)
        .accessibilityLabel("Send attachments")
    }
}

// MARK: - Previews

#if DEBUG
struct FCLPickerInputBar_Previews: PreviewProvider {
    static var previews: some View {
        FCLPickerInputBarPreviewWrapper(
            captionText: "",
            hasSelection: true
        )
        .previewDisplayName("Empty Caption — Send Enabled")
        .previewLayout(.fixed(width: 390, height: 60))

        FCLPickerInputBarPreviewWrapper(
            captionText: "Here's an interesting photo from today!",
            hasSelection: true
        )
        .previewDisplayName("With Caption Text")
        .previewLayout(.fixed(width: 390, height: 60))

        FCLPickerInputBarPreviewWrapper(
            captionText: "",
            hasSelection: false
        )
        .previewDisplayName("No Selection — Send Disabled")
        .previewLayout(.fixed(width: 390, height: 60))
    }
}

private struct FCLPickerInputBarPreviewWrapper: View {
    @State var captionText: String
    let hasSelection: Bool
    @FocusState private var captionFocused: Bool

    var body: some View {
        FCLPickerInputBar(
            captionText: $captionText,
            hasSelection: hasSelection,
            fieldBackgroundColor: FCLPalette.tertiarySystemFill,
            fieldCornerRadius: 18,
            captionFocusBinding: $captionFocused,
            onSend: {}
        )
    }
}
#endif
#endif
