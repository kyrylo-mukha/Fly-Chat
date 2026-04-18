import SwiftUI

/// Rounded-rectangle text field with a glass surface and focus ring.
///
/// On iOS 26+ wraps the field in a container with `.glassEffect(.regular.interactive(true), in:)`.
/// On iOS 17/18 composites the shared fallback glass stack and renders an
/// animated focus stroke when the field is focused. A nil-op
/// `\.accessibilityReduceMotion` is still safe — the focus ring animation
/// collapses to `.linear(0.12)`.
public struct FCLGlassTextField: View {
    @Binding private var text: String
    private let placeholder: String
    private let cornerRadius: CGFloat
    private let tintOverride: FCLChatColorToken?

    @FocusState private var focused: Bool

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.fclDelegateVisualTint) private var delegateTint
    @Environment(\.fclReducedTransparencyBackground) private var reducedBackground
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.fclPreviewReduceTransparency) private var previewReduceTransparency
    @Environment(\.fclPreviewReduceMotion) private var previewReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight

    private var reduceTransparency: Bool { previewReduceTransparency ?? systemReduceTransparency }
    private var reduceMotion: Bool { previewReduceMotion ?? systemReduceMotion }

    public init(
        text: Binding<String>,
        placeholder: String,
        cornerRadius: CGFloat = 18,
        tint: FCLChatColorToken? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.cornerRadius = cornerRadius
        self.tintOverride = tint
    }

    public var body: some View {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: explicitStyle,
            delegate: delegateStyle,
            reduceTransparency: reduceTransparency
        )
        let tint = tintOverride ?? delegateTint
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let field = TextField(placeholder, text: $text)
            .focused($focused)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

        switch resolved {
        case .liquidGlassNative:
            #if os(iOS)
            if #available(iOS 26, *) {
                field
                    .background(
                        shape.fill(Color.clear)
                            .glassEffect(.regular.interactive(true), in: shape)
                    )
                    .overlay(focusStroke(shape: shape, tint: tint))
            } else {
                fallback(shape: shape, tint: tint, field: field)
            }
            #else
            fallback(shape: shape, tint: tint, field: field)
            #endif
        case .liquidGlassFallback:
            fallback(shape: shape, tint: tint, field: field)
        case .opaque:
            field
                .background(shape.fill((tint ?? reducedBackground).color))
                .overlay(focusStroke(shape: shape, tint: tint))
        }
    }

    @ViewBuilder
    private func fallback(shape: RoundedRectangle, tint: FCLChatColorToken?, field: some View) -> some View {
        field
            .background(
                FCLGlassFallbackBackground(
                    shape: shape,
                    tint: tint,
                    reduceTransparency: reduceTransparency,
                    reducedTransparencyBackground: reducedBackground,
                    colorScheme: colorScheme,
                    legibilityWeight: legibilityWeight
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .overlay(focusStroke(shape: shape, tint: tint))
    }

    @ViewBuilder
    private func focusStroke(shape: RoundedRectangle, tint: FCLChatColorToken?) -> some View {
        shape
            .strokeBorder((tint?.color ?? .accentColor).opacity(focused ? 0.2 : 0), lineWidth: 1)
            .animation(
                reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.2),
                value: focused
            )
    }
}

#if DEBUG
private struct FCLGlassTextFieldPreviewHost: View {
    @State var text: String = ""
    var body: some View {
        FCLGlassTextField(text: $text, placeholder: "Message")
            .padding()
    }
}

#Preview("TextField — Default (liquidGlass)") {
    FCLGlassTextFieldPreviewHost()
        .background(Color.gray.opacity(0.2))
}

#Preview("TextField — Opaque (.default)") {
    FCLGlassTextFieldPreviewHost()
        .fclVisualStyle(.default)
}

#Preview("TextField — Custom Radius") {
    FCLGlassTextFieldPreviewHost()
        .background(Color.black.opacity(0.1))
}

@available(iOS 26, *)
#Preview("TextField — Native (iOS 26)") {
    FCLGlassTextFieldPreviewHost()
        .background(LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom))
}

#Preview("TextField — Reduced Transparency") {
    FCLGlassTextFieldPreviewHost()
        .background(Color.gray.opacity(0.2))
        .fclPreviewReduceTransparency()
}

#Preview("TextField — Reduced Motion") {
    FCLGlassTextFieldPreviewHost()
        .background(Color.gray.opacity(0.2))
        .fclPreviewReduceMotion()
}
#endif
