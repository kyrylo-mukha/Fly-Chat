#if canImport(UIKit)
import SwiftUI

// MARK: - FCLPickerCloseButton

/// A 44 × 44 pt glass close button placed top-trailing inside the attachment picker.
///
/// Tapping the button triggers the scope-10 collapse transition by calling
/// ``FCLPickerSourceRelay/requestDismiss()``, routing through the same morph
/// animator used by all other dismiss paths (swipe-down, tap-outside,
/// accessibility escape).
///
/// Built on ``FCLGlassIconButton`` so it inherits the visual style environment
/// (glass fallback, opaque, iOS 26 native glass) without extra wiring.
struct FCLPickerCloseButton: View {
    /// The relay that owns the dismiss hook for the picker's morph animator.
    let sourceRelay: FCLPickerSourceRelay

    var body: some View {
        FCLGlassIconButton(systemImage: "xmark", size: 44) {
            sourceRelay.requestDismiss()
        }
        .accessibilityLabel("Close")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CloseButton — liquidGlass (default)") {
    ZStack(alignment: .topTrailing) {
        Color(.secondarySystemBackground).ignoresSafeArea()
        FCLPickerCloseButton(sourceRelay: FCLPickerSourceRelay())
            .padding(12)
    }
    .previewDisplayName("Close Button — liquidGlass")
}

#Preview("CloseButton — opaque (.default style)") {
    ZStack(alignment: .topTrailing) {
        Color.gray.ignoresSafeArea()
        FCLPickerCloseButton(sourceRelay: FCLPickerSourceRelay())
            .fclVisualStyle(.default)
            .padding(12)
    }
    .previewDisplayName("Close Button — opaque")
}
#endif
#endif
