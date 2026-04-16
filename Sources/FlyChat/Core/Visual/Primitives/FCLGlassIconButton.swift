import SwiftUI

/// Circular icon button with a glass surface.
///
/// On iOS 26+ renders an SF Symbol inside a `.buttonStyle(.glass)` button. On
/// iOS 17/18 composites the shared fallback glass stack on a `Circle` shape,
/// with a slightly more pronounced press-shrink (0.9) than the pill button.
/// Default size is 44 × 44 to meet Apple's minimum hit-target guideline.
public struct FCLGlassIconButton: View {
    private let systemImage: String
    private let size: CGFloat
    private let tintOverride: FCLChatColorToken?
    private let action: () -> Void

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.fclDelegateVisualTint) private var delegateTint
    @Environment(\.fclReducedTransparencyBackground) private var reducedBackground
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight

    public init(
        systemImage: String,
        size: CGFloat = 44,
        tint: FCLChatColorToken? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.size = size
        self.tintOverride = tint
        self.action = action
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
                Button(action: action) {
                    Image(systemName: systemImage)
                        .frame(width: size, height: size)
                }
                .buttonStyle(.glass)
                .tint(tint?.color)
                .clipShape(Circle())
            } else {
                fallback(tint: tint)
            }
            #else
            fallback(tint: tint)
            #endif
        case .liquidGlassFallback:
            fallback(tint: tint)
        case .opaque:
            Button(action: action) {
                Image(systemName: systemImage)
                    .frame(width: size, height: size)
            }
            .buttonStyle(FCLOpaqueCircleButtonStyle(
                tint: tint ?? reducedBackground,
                reduceMotion: reduceMotion
            ))
        }
    }

    @ViewBuilder
    private func fallback(tint: FCLChatColorToken?) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: size, height: size)
        }
        .buttonStyle(FCLGlassFallbackIconButtonStyle(
            tint: tint,
            reduceTransparency: reduceTransparency,
            reducedTransparencyBackground: reducedBackground,
            reduceMotion: reduceMotion,
            colorScheme: colorScheme,
            legibilityWeight: legibilityWeight
        ))
    }
}

struct FCLGlassFallbackIconButtonStyle: ButtonStyle {
    let tint: FCLChatColorToken?
    let reduceTransparency: Bool
    let reducedTransparencyBackground: FCLChatColorToken
    let reduceMotion: Bool
    let colorScheme: ColorScheme
    let legibilityWeight: LegibilityWeight?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                FCLGlassFallbackBackground(
                    shape: Circle(),
                    tint: tint,
                    reduceTransparency: reduceTransparency,
                    reducedTransparencyBackground: reducedTransparencyBackground,
                    colorScheme: colorScheme,
                    legibilityWeight: legibilityWeight
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.12)
                    : .spring(response: 0.24, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

struct FCLOpaqueCircleButtonStyle: ButtonStyle {
    let tint: FCLChatColorToken
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(tint.color))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.12)
                    : .spring(response: 0.24, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

#if DEBUG
#Preview("IconButton — Default (liquidGlass)") {
    HStack(spacing: 12) {
        FCLGlassIconButton(systemImage: "paperclip", action: {})
        FCLGlassIconButton(systemImage: "mic.fill", action: {})
        FCLGlassIconButton(
            systemImage: "paperplane.fill",
            tint: FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0),
            action: {}
        )
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("IconButton — Opaque (.default)") {
    FCLGlassIconButton(systemImage: "xmark", action: {})
        .fclVisualStyle(.default)
        .padding()
}

#Preview("IconButton — Small") {
    FCLGlassIconButton(systemImage: "camera", size: 32, action: {})
        .padding()
}

@available(iOS 26, *)
#Preview("IconButton — Native (iOS 26)") {
    FCLGlassIconButton(systemImage: "paperplane.fill", action: {})
        .padding()
        .background(LinearGradient(colors: [.green, .teal], startPoint: .top, endPoint: .bottom))
}
#endif
