import SwiftUI

// MARK: - FCLPickerCloseButton

/// A 44 × 44 pt glass close button placed top-trailing inside the attachment
/// picker.
///
/// Tapping the button dismisses the enclosing sheet through SwiftUI's
/// `DismissAction`, routing through the same path used by swipe-down,
/// tap-outside, and accessibility escape — which on iOS 18+ drives the system
/// zoom-collapse back into the source view, and on iOS 17 runs the standard
/// sheet slide-down.
///
/// Built on ``FCLGlassIconButton`` so it inherits the visual style environment
/// (glass fallback, opaque, iOS 26 native glass) without extra wiring.
struct FCLPickerCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FCLGlassIconButton(systemImage: "xmark", size: 44) {
            dismiss()
        }
        .accessibilityLabel("Close")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CloseButton — liquidGlass (default)") {
    ZStack(alignment: .topTrailing) {
        FCLPalette.secondarySystemBackground.ignoresSafeArea()
        FCLPickerCloseButton()
            .padding(12)
    }
}

#Preview("CloseButton — opaque (.default style)") {
    ZStack(alignment: .topTrailing) {
        Color.gray.ignoresSafeArea()
        FCLPickerCloseButton()
            .fclVisualStyle(.default)
            .padding(12)
    }
}
#endif
