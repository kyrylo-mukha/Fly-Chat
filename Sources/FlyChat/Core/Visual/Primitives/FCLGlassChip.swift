import SwiftUI

/// Capsule-shaped chip with an optional leading accessory and trailing badge.
///
/// On iOS 26+ composites the content over UIKit's native `UIGlassEffect`. On
/// iOS 17/18 it falls back to a `UIBlurEffect`-backed `UIVisualEffectView`.
/// Tapping the chip plays a subtle press-shrink (0.95) when `action` is non-nil.
public struct FCLGlassChip<Accessory: View>: View {
    private let title: String
    private let badgeCount: Int?
    private let tintOverride: FCLChatColorToken?
    private let surfaceStyle: FCLGlassSurfaceStyle
    private let action: (() -> Void)?
    private let accessory: Accessory

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
        title: String,
        badgeCount: Int? = nil,
        tint: FCLChatColorToken? = nil,
        surfaceStyle: FCLGlassSurfaceStyle = .regular,
        action: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.badgeCount = badgeCount
        self.tintOverride = tint
        self.surfaceStyle = surfaceStyle
        self.action = action
        self.accessory = accessory()
    }

    public var body: some View {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: explicitStyle,
            delegate: delegateStyle,
            reduceTransparency: reduceTransparency
        )
        let tint = tintOverride ?? delegateTint

        let content = HStack(spacing: 6) {
            accessory
                .padding(4)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.medium))
            if let badgeCount {
                Text("\(badgeCount)")
                    .font(.caption.weight(.semibold))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.25)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)

        let shape = Capsule(style: .continuous)

        let background: AnyView = {
            switch resolved {
            case .liquidGlassNative, .liquidGlassFallback:
                return AnyView(glassBackground(shape: shape, tint: tint, resolved: resolved))
            case .opaque:
                return AnyView(shape.fill((tint ?? reducedBackground).color))
            }
        }()

        let rimColor = Self.effectiveRimStroke(showButtonShapes: showButtonShapes, tint: tint)
        let body = content
            .background(background)
            .overlay {
                if let rimColor {
                    Capsule(style: .continuous)
                        .strokeBorder(rimColor.opacity(0.9), lineWidth: 1.5)
                }
            }

        if let action {
            Button(action: action) { body }
                .buttonStyle(FCLChipPressStyle(reduceMotion: reduceMotion))
        } else {
            body
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
    private func glassBackground(
        shape: Capsule,
        tint: FCLChatColorToken?,
        resolved: FCLResolvedVisualStyle
    ) -> some View {
        FCLLiquidGlassSurface(
            shape: shape,
            tint: tint,
            isInteractive: action != nil,
            surfaceStyle: surfaceStyle,
            resolvedStyle: resolved,
            reduceTransparency: reduceTransparency,
            reducedTransparencyBackground: reducedBackground,
            colorScheme: colorScheme,
            legibilityWeight: legibilityWeight
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

struct FCLChipPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.12)
                    : .spring(response: 0.24, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

#if DEBUG
#Preview("Chip — Default (liquidGlass)") {
    HStack(spacing: 8) {
        FCLGlassChip(title: "Photos")
        FCLGlassChip(title: "Files", badgeCount: 3)
        FCLGlassChip(title: "Camera", action: {}) {
            Image(systemName: "camera.fill")
        }
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Chip — Opaque (.default)") {
    FCLGlassChip(title: "Opaque", badgeCount: 12)
        .fclVisualStyle(.default)
        .padding()
}

#Preview("Chip — Tinted") {
    FCLGlassChip(title: "Tinted", tint: FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0))
        .padding()
}

@available(iOS 26, *)
#Preview("Chip — Native (iOS 26)") {
    HStack {
        FCLGlassChip(title: "Photo", action: {})
        FCLGlassChip(title: "Video", action: {})
    }
    .padding()
    .background(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
}

#Preview("Chip — Reduced Transparency") {
    FCLGlassChip(title: "Photos", badgeCount: 3)
        .padding()
        .background(Color.gray.opacity(0.2))
        .fclPreviewReduceTransparency()
}

#Preview("Chip — Reduced Motion") {
    FCLGlassChip(title: "Camera", action: {})
        .padding()
        .background(Color.gray.opacity(0.2))
        .fclPreviewReduceMotion()
}

#Preview("Chip — Done with image accessory and badge (camera Done-chip)") {
    ZStack {
        Color.black.ignoresSafeArea()
        FCLGlassChip(
            title: "Done",
            badgeCount: 3,
            action: {}
        ) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.teal, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 24)
        }
        .padding()
    }
}
#endif
