import SwiftUI

/// Rectangular glass surface with configurable corner radius.
///
/// On iOS 26+ uses `.glassEffect(.regular, in:)`. On iOS 17/18 composites the
/// shared fallback "glass stack" (material + tint overlay + inner highlight +
/// edge stroke + outer shadow). When `\.accessibilityReduceTransparency` is
/// `true`, the material is replaced with an opaque fill taken from
/// ``FCLVisualStyleDelegate/reducedTransparencyBackground``.
public struct FCLGlassContainer<Content: View>: View {
    private let cornerRadius: CGFloat
    private let tintOverride: FCLChatColorToken?
    private let content: Content

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.fclDelegateVisualTint) private var delegateTint
    @Environment(\.fclReducedTransparencyBackground) private var reducedBackground
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.fclPreviewReduceTransparency) private var previewReduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight

    private var reduceTransparency: Bool { previewReduceTransparency ?? systemReduceTransparency }

    public init(
        cornerRadius: CGFloat = 16,
        tint: FCLChatColorToken? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tintOverride = tint
        self.content = content()
    }

    public var body: some View {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: explicitStyle,
            delegate: delegateStyle,
            reduceTransparency: reduceTransparency
        )
        let tint = tintOverride ?? delegateTint
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        switch resolved {
        case .liquidGlassNative:
            #if os(iOS)
            if #available(iOS 26, *) {
                content
                    .glassEffect(.regular, in: shape)
            } else {
                fallback(shape: shape, tint: tint)
            }
            #else
            fallback(shape: shape, tint: tint)
            #endif
        case .liquidGlassFallback:
            fallback(shape: shape, tint: tint)
        case .opaque:
            content
                .background(
                    shape.fill((tint ?? reducedBackground).color)
                )
        }
    }

    @ViewBuilder
    private func fallback(shape: RoundedRectangle, tint: FCLChatColorToken?) -> some View {
        content
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
    }
}

#if DEBUG
#Preview("Container — Default (liquidGlass)") {
    VStack(spacing: 16) {
        FCLGlassContainer {
            Text("Default glass")
                .padding()
        }
        FCLGlassContainer(cornerRadius: 28, tint: FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0)) {
            Text("Tinted glass")
                .padding()
        }
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Container — Opaque (.default)") {
    FCLGlassContainer {
        Text("Opaque")
            .padding()
    }
    .fclVisualStyle(.default)
    .padding()
}

#Preview("Container — Tinted") {
    FCLGlassContainer(tint: FCLChatColorToken(red: 0.2, green: 0.6, blue: 1)) {
        Text("Tinted glass")
            .padding()
    }
    .padding()
}

@available(iOS 26, *)
#Preview("Container — Native (iOS 26)") {
    FCLGlassContainer(cornerRadius: 20) {
        Text("Native iOS 26 glass")
            .padding()
    }
    .padding()
    .background(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
}

#Preview("Container — Reduced Transparency") {
    FCLGlassContainer {
        Text("Reduced transparency")
            .padding()
    }
    .padding()
    .background(Color.gray.opacity(0.2))
    .fclPreviewReduceTransparency()
}

#Preview("Container — Reduced Motion") {
    FCLGlassContainer {
        Text("Reduced motion")
            .padding()
    }
    .padding()
    .background(Color.gray.opacity(0.2))
    .fclPreviewReduceMotion()
}
#endif
