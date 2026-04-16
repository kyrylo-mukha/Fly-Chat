import SwiftUI

/// Horizontal toolbar-like surface that groups ``FCLGlass`` primitives.
///
/// On iOS 26+ wraps children in a `GlassEffectContainer(spacing: 12)` so
/// adjacent glass elements morph into a single shape when they come near each
/// other. On iOS 17/18 composites a single ``FCLGlassContainer`` around the
/// children; child transitions use `.scale + .opacity` with a spring tuned to
/// match the native morph, collapsing to cross-fade when reduce-motion is on.
public struct FCLGlassToolbar<Content: View>: View {
    /// Whether the toolbar anchors at the top or bottom of its parent.
    ///
    /// Placement only affects the fallback corner radius (edge-flush top bars
    /// use 0 at the top edge, floating bottom bars use 28). It does not
    /// control layout — callers place the toolbar via `.safeAreaInset` or
    /// their own container.
    public enum Placement: Sendable, Hashable {
        case top
        case bottom
    }

    private let placement: Placement
    private let tintOverride: FCLChatColorToken?
    private let content: Content

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.fclDelegateVisualTint) private var delegateTint
    @Environment(\.fclReducedTransparencyBackground) private var reducedBackground
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        placement: Placement = .top,
        tint: FCLChatColorToken? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
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

        switch resolved {
        case .liquidGlassNative:
            #if os(iOS)
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) { content }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .tint(tint?.color)
            } else {
                fallbackBar(tint: tint)
            }
            #else
            fallbackBar(tint: tint)
            #endif
        case .liquidGlassFallback, .opaque:
            fallbackBar(tint: tint)
        }
    }

    private var fallbackCornerRadius: CGFloat {
        switch placement {
        case .top: return 0
        case .bottom: return 28
        }
    }

    @ViewBuilder
    private func fallbackBar(tint: FCLChatColorToken?) -> some View {
        FCLGlassContainer(cornerRadius: fallbackCornerRadius, tint: tint) {
            HStack(spacing: 12) { content }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .animation(
                    reduceMotion
                        ? .linear(duration: 0.12)
                        : .spring(response: 0.30, dampingFraction: 0.85),
                    value: reduceMotion
                )
        }
    }
}

#if DEBUG
#Preview("Toolbar — Top (liquidGlass)") {
    VStack {
        FCLGlassToolbar(placement: .top) {
            Image(systemName: "xmark")
            Spacer()
            Text("Title").font(.headline)
            Spacer()
            Image(systemName: "ellipsis")
        }
        Spacer()
    }
    .background(Color.gray.opacity(0.2))
}

#Preview("Toolbar — Bottom (liquidGlass)") {
    VStack {
        Spacer()
        FCLGlassToolbar(placement: .bottom, tint: FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0)) {
            Image(systemName: "camera")
            Image(systemName: "photo")
            Spacer()
            Text("Done").font(.subheadline.weight(.semibold))
        }
        .padding()
    }
    .background(Color.gray.opacity(0.2))
}

#Preview("Toolbar — Opaque (.default)") {
    FCLGlassToolbar {
        Text("Opaque top bar")
    }
    .fclVisualStyle(.default)
}

@available(iOS 26, *)
#Preview("Toolbar — Native (iOS 26)") {
    FCLGlassToolbar(placement: .bottom) {
        Image(systemName: "camera")
        Image(systemName: "photo.on.rectangle")
        Spacer()
        Text("Send")
    }
    .padding()
    .background(LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom))
}
#endif
