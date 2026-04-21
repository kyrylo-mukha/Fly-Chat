#if os(iOS)
import SwiftUI

// MARK: - FCLPickerInputBar

/// Caption input bar shown at the bottom of the picker sheet when gallery assets are selected.
/// Hosts a glass caption field and a send button; caption focus is hoisted from the sheet.
struct FCLPickerInputBar: View {
    @Binding var captionText: String
    let hasSelection: Bool
    let fieldBackgroundColor: Color
    let fieldCornerRadius: CGFloat
    /// Focus binding hoisted from the enclosing sheet so the sheet can drop
    /// caption focus immediately before invoking send.
    let captionFocusBinding: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            captionField
            sendButton
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Private

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
