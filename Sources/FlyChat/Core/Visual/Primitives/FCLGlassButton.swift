import SwiftUI

/// Capsule-shaped glass button.
///
/// On iOS 26+ uses the native `.buttonStyle(.glass)`. On iOS 17/18 composites
/// the shared fallback "glass stack" on a capsule and applies a press-shrink
/// spring that honors `\.accessibilityReduceMotion`.
public struct FCLGlassButton<Label: View>: View {
    private let role: ButtonRole?
    private let tintOverride: FCLChatColorToken?
    private let action: () -> Void
    private let label: Label

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.fclDelegateVisualTint) private var delegateTint
    @Environment(\.fclReducedTransparencyBackground) private var reducedBackground
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight

    public init(
        role: ButtonRole? = nil,
        tint: FCLChatColorToken? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.tintOverride = tint
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

        switch resolved {
        case .liquidGlassNative:
            #if os(iOS)
            if #available(iOS 26, *) {
                Button(role: role, action: action) {
                    label.padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.glass)
                .tint(tint?.color)
            } else {
                fallbackButton(tint: tint)
            }
            #else
            fallbackButton(tint: tint)
            #endif
        case .liquidGlassFallback:
            fallbackButton(tint: tint)
        case .opaque:
            Button(role: role, action: action) {
                label.padding(.horizontal, 14).padding(.vertical, 10)
            }
            .buttonStyle(FCLOpaqueCapsuleButtonStyle(
                tint: tint ?? reducedBackground,
                reduceMotion: reduceMotion
            ))
        }
    }

    @ViewBuilder
    private func fallbackButton(tint: FCLChatColorToken?) -> some View {
        Button(role: role, action: action) {
            label.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .buttonStyle(FCLGlassFallbackButtonStyle(
            tint: tint,
            reduceTransparency: reduceTransparency,
            reducedTransparencyBackground: reducedBackground,
            reduceMotion: reduceMotion,
            colorScheme: colorScheme,
            legibilityWeight: legibilityWeight
        ))
    }
}

// MARK: - Fallback styles

struct FCLGlassFallbackButtonStyle: ButtonStyle {
    let tint: FCLChatColorToken?
    let reduceTransparency: Bool
    let reducedTransparencyBackground: FCLChatColorToken
    let reduceMotion: Bool
    let colorScheme: ColorScheme
    let legibilityWeight: LegibilityWeight?

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        return configuration.label
            .background(
                FCLGlassFallbackBackground(
                    shape: shape,
                    tint: tint,
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
#endif
