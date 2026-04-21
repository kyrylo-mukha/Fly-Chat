#if os(iOS)
import SwiftUI

// MARK: - FCLPickerInputBar

/// A caption input bar shown at the bottom of the attachment picker sheet when the user
/// has selected one or more gallery assets.
///
/// Matches the prototype CaptionSendBar spec:
/// - ``FCLGlassTextField`` for the caption field (cornerRadius 22, placeholder "Caption").
/// - Send button: 44 × 44 pt blue-filled circle, always enabled when `hasSelection` is true.
/// - Container: transparent background so the bar floats over grid content (no divider).
/// - Horizontal insets: 10 pt (matching the prototype's `left: 10, right: 10` absolute bar).
///
/// Caption focus is owned by the enclosing sheet (``FCLAttachmentPickerSheet``) via a
/// hoisted `@FocusState` binding so the sheet can dismiss the keyboard synchronously
/// alongside the send animation.
struct FCLPickerInputBar: View {
    /// Two-way binding to the caption string typed by the user.
    @Binding var captionText: String
    /// Whether the user has selected at least one asset. Controls send button availability.
    let hasSelection: Bool
    /// Background color for the text field container — kept for API compatibility but
    /// no longer applied; the glass field manages its own surface.
    let fieldBackgroundColor: Color
    /// Corner radius applied to the text field container — kept for API compatibility but
    /// no longer applied; ``FCLGlassTextField`` uses 22 per prototype spec.
    let fieldCornerRadius: CGFloat
    /// Focus binding hoisted from the enclosing sheet so the sheet can drop
    /// caption focus immediately before invoking send.
    let captionFocusBinding: FocusState<Bool>.Binding
    /// Callback invoked when the user taps the send button.
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            captionField
            sendButton
        }
        // Horizontal insets match prototype's absolute bar: left:10, right:10.
        // Vertical padding: 8pt top, 10pt bottom — gives the bar breathing room
        // against the safe-area inset while staying flush with the sheet edge.
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        // Transparent: the bar floats over the gallery grid.
    }

    // MARK: - Private

    /// Caption input field matching the CaptionSendBar FCLGlassTextField spec:
    /// cornerRadius 22, placeholder "Caption", 17pt text, min 44pt hit height.
    ///
    /// The `TextField` is wrapped inside ``FCLGlassContainer`` so the hoisted
    /// focus binding from the sheet can be applied directly to the `TextField` —
    /// ``FCLGlassTextField`` manages focus internally and cannot accept an
    /// external binding, which the sheet needs to dismiss the keyboard at send time.
    private var captionField: some View {
        FCLGlassContainer(cornerRadius: 22) {
            TextField("Caption", text: $captionText)
                .focused(captionFocusBinding)
                .font(.system(size: 17))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
        }
    }

    /// Prototype send button: 44 × 44 solid blue circle, always enabled while
    /// `hasSelection` is true. Fades to systemGray3 when no selection exists.
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(hasSelection ? Color.blue : FCLPalette.systemGray3)
                        .shadow(color: Color.blue.opacity(hasSelection ? 0.45 : 0), radius: 8, y: 2)
                )
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
        // Simulate the floating bar over a gallery background.
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                FCLPickerInputBarPreviewWrapper(captionText: "", hasSelection: true)
            }
        }
        .previewDisplayName("Empty Caption — Send Enabled")
        .previewLayout(.fixed(width: 390, height: 120))

        ZStack {
            LinearGradient(
                colors: [Color.teal.opacity(0.3), Color.green.opacity(0.3)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                FCLPickerInputBarPreviewWrapper(
                    captionText: "Here's an interesting photo from today!",
                    hasSelection: true
                )
            }
        }
        .previewDisplayName("With Caption Text")
        .previewLayout(.fixed(width: 390, height: 120))

        ZStack {
            FCLPalette.systemGroupedBackground.ignoresSafeArea()
            VStack {
                Spacer()
                FCLPickerInputBarPreviewWrapper(captionText: "", hasSelection: false)
            }
        }
        .previewDisplayName("No Selection — Send Disabled")
        .previewLayout(.fixed(width: 390, height: 120))
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
            fieldCornerRadius: 22,
            captionFocusBinding: $captionFocused,
            onSend: {}
        )
    }
}
#endif
#endif
