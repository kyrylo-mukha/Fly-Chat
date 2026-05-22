import SwiftUI

/// Capsule-shaped glass button.
///
/// On iOS 26+ uses UIKit's native `UIGlassEffect`. On iOS 17/18 it falls back
/// to a `UIBlurEffect`-backed `UIVisualEffectView` and applies a press-shrink
/// spring that honors `\.accessibilityReduceMotion`.
public struct FCLGlassButton<Label: View>: View {
    private let role: ButtonRole?
    private let tintOverride: FCLChatColorToken?
    private let surfaceStyle: FCLGlassSurfaceStyle
    private let action: () -> Void
    private let label: Label

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.fclDelegateVisualTint) private var delegateTint
    @Environment(\.fclReducedTransparencyBackground) private var reducedBackground
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityShowButtonShapes) private var showButtonShapes
    @Environment(\.fclPreviewReduceTransparency) private var previewReduceTransparency
    @Environment(\.fclPreviewReduceMotion) private var previewReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight

    private var reduceTransparency: Bool { previewReduceTransparency ?? systemReduceTransparency }
    private var reduceMotion: Bool { previewReduceMotion ?? systemReduceMotion }

    public init(
        role: ButtonRole? = nil,
        tint: FCLChatColorToken? = nil,
        surfaceStyle: FCLGlassSurfaceStyle = .regular,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.tintOverride = tint
        self.surfaceStyle = surfaceStyle
        self.action = action
        self.label = label()
    }

    public var body: some View {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: explicitStyle,
            delegate: delegateStyle,
            reduceTransparency: reduceTransparency
        )
        let tint = tintOverride ?? delegateTint
        let rimColor = Self.effectiveRimStroke(showButtonShapes: showButtonShapes, tint: tint)

        let core: AnyView = {
            switch resolved {
            case .liquidGlassNative, .liquidGlassFallback:
                return AnyView(glassButton(tint: tint, resolved: resolved))
            case .opaque:
                return AnyView(
                    Button(role: role, action: action) {
                        label.padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .buttonStyle(FCLOpaqueCapsuleButtonStyle(
                        tint: tint ?? reducedBackground,
                        reduceMotion: reduceMotion
                    ))
                )
            }
        }()

        if let rimColor {
            core.overlay(
                Capsule(style: .continuous)
                    .strokeBorder(rimColor.opacity(0.9), lineWidth: 1.5)
            )
        } else {
            core
        }
    }

    /// `internal` (not `private`) so unit tests can verify the `showButtonShapes` path
    /// without rendering the full view.
    static func effectiveRimStroke(
        showButtonShapes: Bool,
        tint: FCLChatColorToken?
    ) -> Color? {
        guard showButtonShapes else { return nil }
        return tint?.color ?? Color.primary
    }

    @ViewBuilder
    private func glassButton(tint: FCLChatColorToken?, resolved: FCLResolvedVisualStyle) -> some View {
        Button(role: role, action: action) {
            label.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .buttonStyle(FCLGlassButtonStyle(
            tint: tint,
            surfaceStyle: surfaceStyle,
            resolvedStyle: resolved,
            reduceTransparency: reduceTransparency,
            reducedTransparencyBackground: reducedBackground,
            reduceMotion: reduceMotion,
            colorScheme: colorScheme,
            legibilityWeight: legibilityWeight
        ))
    }
}

// MARK: - Fallback styles

struct FCLGlassButtonStyle: ButtonStyle {
    let tint: FCLChatColorToken?
    let surfaceStyle: FCLGlassSurfaceStyle
    let resolvedStyle: FCLResolvedVisualStyle
    let reduceTransparency: Bool
    let reducedTransparencyBackground: FCLChatColorToken
    let reduceMotion: Bool
    let colorScheme: ColorScheme
    let legibilityWeight: LegibilityWeight?

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        return configuration.label
            .background(
                FCLLiquidGlassSurface(
                    shape: shape,
                    tint: tint,
                    isInteractive: true,
                    surfaceStyle: surfaceStyle,
                    resolvedStyle: resolvedStyle,
                    reduceTransparency: reduceTransparency,
                    reducedTransparencyBackground: reducedTransparencyBackground,
                    colorScheme: colorScheme,
                    legibilityWeight: legibilityWeight
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(pressAnimation, value: configuration.isPressed)
    }

    private var pressAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.12)
            : .spring(response: 0.24, dampingFraction: 0.82)
    }
}

struct FCLOpaqueCapsuleButtonStyle: ButtonStyle {
    let tint: FCLChatColorToken
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule(style: .continuous).fill(tint.color))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.12)
                    : .spring(response: 0.24, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

#if DEBUG
#Preview("Button — Default (liquidGlass)") {
    VStack(spacing: 16) {
        FCLGlassButton(action: {}) { Text("Send") }
        FCLGlassButton(tint: FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0), action: {}) {
            Text("Tinted")
        }
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Button — Opaque (.default)") {
    FCLGlassButton(action: {}) { Text("Opaque") }
        .fclVisualStyle(.default)
        .padding()
}

#Preview("Button — Destructive Role") {
    FCLGlassButton(role: .destructive, action: {}) { Text("Delete") }
        .padding()
}

@available(iOS 26, *)
#Preview("Button — Native (iOS 26)") {
    FCLGlassButton(action: {}) { Text("Native glass") }
        .padding()
        .background(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
}

#Preview("Button — Reduced Transparency") {
    FCLGlassButton(action: {}) { Text("Send") }
        .padding()
        .background(Color.gray.opacity(0.2))
        .fclPreviewReduceTransparency()
}

#Preview("Button — Reduced Motion") {
    FCLGlassButton(action: {}) { Text("Send") }
        .padding()
        .background(Color.gray.opacity(0.2))
        .fclPreviewReduceMotion()
}
#endif
