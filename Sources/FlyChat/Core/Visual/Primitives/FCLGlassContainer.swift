import SwiftUI

/// Rectangular glass surface with configurable corner radius.
///
/// On iOS 26+ uses UIKit's native `UIGlassEffect` inside `UIVisualEffectView`.
/// On older iOS versions it falls back to a `UIBlurEffect`-backed
/// `UIVisualEffectView`, keeping the same shape without painting an opaque
/// backing behind the content.
public struct FCLGlassContainer<Content: View>: View {
    private let cornerRadius: CGFloat
    private let tintOverride: FCLChatColorToken?
    private let surfaceStyle: FCLGlassSurfaceStyle
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
        surfaceStyle: FCLGlassSurfaceStyle = .regular,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tintOverride = tint
        self.surfaceStyle = surfaceStyle
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
        case .liquidGlassNative, .liquidGlassFallback:
            content
                .background(
                    FCLLiquidGlassSurface(
                        shape: shape,
                        tint: tint,
                        isInteractive: false,
                        surfaceStyle: surfaceStyle,
                        resolvedStyle: resolved,
                        reduceTransparency: reduceTransparency,
                        reducedTransparencyBackground: reducedBackground,
                        colorScheme: colorScheme,
                        legibilityWeight: legibilityWeight
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                )
        case .opaque:
            content
                .background(
                    shape.fill((tint ?? reducedBackground).color)
                )
        }
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
