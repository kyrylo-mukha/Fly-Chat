#if canImport(UIKit)
import SwiftUI
import UIKit

/// A `UIViewRepresentable` that wraps a `UITextView` to provide an auto-expanding,
/// multi-line text input field for the chat input bar.
///
/// The text view grows vertically as the user types, up to a configurable maximum height,
/// then enables scrolling. It displays a placeholder label when the text is empty and
/// optionally intercepts the Return key to trigger a send action.
struct FCLExpandingTextView: UIViewRepresentable {
    /// Two-way binding to the current text content.
    @Binding var text: String
    /// The UIKit font applied to the text view.
    let font: UIFont
    /// The maximum height (in points) the text view can grow to before enabling scrolling.
    let maxHeight: CGFloat
    /// Placeholder string displayed when the text view is empty.
    let placeholder: String
    /// The background color of the text field (applied by the parent, not the text view itself).
    let fieldBackgroundColor: UIColor
    /// Corner radius applied to the field container by the parent.
    let cornerRadius: CGFloat
    /// Whether pressing the Return key triggers a send action instead of inserting a newline.
    let returnKeySends: Bool
    /// Callback invoked when the Return key is pressed and `returnKeySends` is `true`.
    let onSend: () -> Void
    /// Two-way binding to the current measured height of the text view.
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.returnKeyType = returnKeySends ? .send : .default

        textView.text = text
        textView.textColor = UIColor.label

        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = font
        placeholderLabel.textColor = UIColor.placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top)
        ])

        placeholderLabel.isHidden = !text.isEmpty
        context.coordinator.placeholderLabel = placeholderLabel

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        textView.font = font
        recalculateHeight(textView)
    }

    /// Measures the text view's intrinsic content size and updates the bound height,
    /// clamping between a single-line minimum and the configured maximum.
    private func recalculateHeight(_ textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude))
        let newHeight = min(size.height, maxHeight)
        let singleLineHeight = font.lineHeight + textView.textContainerInset.top + textView.textContainerInset.bottom
        let clampedHeight = max(newHeight, singleLineHeight)

        if abs(clampedHeight - height) > 0.5 {
            DispatchQueue.main.async {
                self.height = clampedHeight
                textView.isScrollEnabled = size.height > maxHeight
            }
        }
    }

    /// Coordinator that acts as the `UITextViewDelegate`, forwarding text changes
    /// back to the SwiftUI binding and managing placeholder visibility.
    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        /// Reference to the parent representable for accessing bindings and callbacks.
        var parent: FCLExpandingTextView
        /// The placeholder label added as a subview of the text view.
        var placeholderLabel: UILabel?

        /// Creates a coordinator for the given expanding text view.
        ///
        /// - Parameter parent: The parent `FCLExpandingTextView` instance.
        init(_ parent: FCLExpandingTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Placeholder is handled by the overlay label; no text manipulation needed.
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }

        func textViewDidChange(_ textView: UITextView) {
            placeholderLabel?.isHidden = !textView.text.isEmpty
            parent.text = textView.text
            parent.recalculateHeight(textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if parent.returnKeySends && text == "\n" {
                parent.onSend()
                return false
            }
            return true
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FCLExpandingTextView_Previews: PreviewProvider {
    static var previews: some View {
        FCLExpandingTextViewPreviewWrapper()
            .previewDisplayName("Expanding Text View")
            .previewLayout(.sizeThatFits)
            .padding()
    }
}

private struct FCLExpandingTextViewPreviewWrapper: View {
    @State private var text = ""
    @State private var height: CGFloat = 40

    var body: some View {
        VStack(spacing: 12) {
            FCLExpandingTextView(
                text: $text,
                font: .systemFont(ofSize: 17),
                maxHeight: 120,
                placeholder: "Type a message...",
                fieldBackgroundColor: UIColor.secondarySystemBackground,
                cornerRadius: 18,
                returnKeySends: false,
                onSend: {},
                height: $height
            )
            .frame(height: height)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(18)

            Text("Height: \(Int(height))pt")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
#endif
#endif
