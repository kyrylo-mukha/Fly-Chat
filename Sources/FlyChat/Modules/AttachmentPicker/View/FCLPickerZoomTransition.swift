import SwiftUI

// MARK: - FCLPickerZoomSource

/// Marks a view as the source anchor of the attachment picker's source-anchored
/// zoom transition.
///
/// On iOS 18+ (and macOS 15+) applies `matchedTransitionSource(id:in:)` so the
/// system-driven `.navigationTransition(.zoom(...))` on the destination view can
/// morph out of (and back into) this source view. On earlier OS versions the
/// modifier is a no-op — the picker presents through a plain `.sheet()` slide-up
/// with no source-anchored animation.
///
/// Pair with ``FCLPickerZoomDestination`` carrying the same `sourceID` and
/// `namespace` on the sheet root.
struct FCLPickerZoomSource: ViewModifier {
    /// Stable identifier for the transition source. Must match the `sourceID`
    /// on the destination modifier.
    let sourceID: String

    /// Shared namespace declared with `@Namespace` on the presenting view.
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content.matchedTransitionSource(id: sourceID, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - FCLPickerZoomDestination

/// Installs the system-driven zoom navigation transition on the attachment
/// picker sheet root.
///
/// On iOS 18+ applies `navigationTransition(.zoom(sourceID:in:))` so the sheet
/// expands out of the matching ``FCLPickerZoomSource`` view and collapses back
/// into it on dismiss (swipe-down, tap-outside, close button). On iOS 17 and
/// on macOS the modifier is a no-op — the sheet uses the standard slide-up
/// presentation. macOS is excluded because `NavigationTransition.zoom` is
/// unavailable there even on macOS 15+ (Apple ships it for iOS / iPadOS /
/// Mac Catalyst / tvOS / visionOS / watchOS only).
///
/// Apply to the topmost view inside the sheet content closure (outside any
/// containers such as `VStack`), as required by the system API.
struct FCLPickerZoomDestination: ViewModifier {
    /// Stable identifier matching the source modifier's `sourceID`.
    let sourceID: String

    /// Shared namespace matching the source modifier's `namespace`.
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        #if !os(macOS)
        if #available(iOS 18, *) {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Previews

#if DEBUG

#Preview("ZoomSource — fallback no-op") {
    FCLPickerZoomTransitionPreviewHost { namespace in
        Image(systemName: "paperclip")
            .font(.system(size: 24, weight: .regular))
            .frame(width: 44, height: 44)
            .background(Color.blue.opacity(0.15), in: Circle())
            .modifier(FCLPickerZoomSource(
                sourceID: "FCLAttachmentPicker",
                namespace: namespace
            ))
    }
}

#Preview("ZoomDestination — fallback no-op") {
    FCLPickerZoomTransitionPreviewHost { namespace in
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
            Text("Attachment Picker (preview)")
                .font(.headline)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .background(FCLPalette.systemBackground)
        .modifier(FCLPickerZoomDestination(
            sourceID: "FCLAttachmentPicker",
            namespace: namespace
        ))
    }
}

/// Lightweight preview host that supplies a `Namespace.ID` to the modifier
/// being demonstrated. Both modifiers no-op on iOS 17 / macOS 14, so the
/// preview content renders unchanged regardless of OS version.
private struct FCLPickerZoomTransitionPreviewHost<Content: View>: View {
    @Namespace private var namespace
    let content: (Namespace.ID) -> Content

    init(@ViewBuilder content: @escaping (Namespace.ID) -> Content) {
        self.content = content
    }

    var body: some View {
        content(namespace)
            .padding()
    }
}
#endif
