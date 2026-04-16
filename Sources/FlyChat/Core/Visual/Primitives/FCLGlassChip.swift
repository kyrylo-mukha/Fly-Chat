import SwiftUI

/// Capsule-shaped chip with an optional leading accessory and trailing badge.
///
/// On iOS 26+ composites the content inside a `.glassEffect(.regular.interactive(true), in: Capsule())`.
/// On iOS 17/18 composites the shared fallback glass stack on a capsule. Tapping
/// the chip plays a subtle press-shrink (0.95) when `action` is non-nil.
public struct FCLGlassChip<Accessory: View>: View {
    private let title: String
    private let badgeCount: Int?
    private let tintOverride: FCLChatColorToken?
    private let action: (() -> Void)?
    private let accessory: Accessory

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.fclDelegateVisualTint) private var delegateTint
    @Environment(\.fclReducedTransparencyBackground) private var reducedBackground
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight

    public init(
        title: String,
        badgeCount: Int? = nil,
        tint: FCLChatColorToken? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.badgeCount = badgeCount
        self.tintOverride = tint
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
            case .liquidGlassNative:
                #if os(iOS)
                if #available(iOS 26, *) {
                    return AnyView(
                        shape.fill(Color.clear)
                            .glassEffect(.regular.interactive(action != nil), in: shape)
                    )
                } else {
                    return AnyView(fallbackBackground(shape: shape, tint: tint))
                }
                #else
                return AnyView(fallbackBackground(shape: shape, tint: tint))
                #endif
            case .liquidGlassFallback:
                return AnyView(fallbackBackground(shape: shape, tint: tint))
            case .opaque:
                return AnyView(shape.fill((tint ?? reducedBackground).color))
            }
        }()

        let body = content.background(background)

        if let action {
            Button(action: action) { body }
                .buttonStyle(FCLChipPressStyle(reduceMotion: reduceMotion))
        } else {
            body
        }
    }

    @ViewBuilder
    private func fallbackBackground(shape: Capsule, tint: FCLChatColorToken?) -> some View {
        FCLGlassFallbackBackground(
            shape: shape,
            tint: tint,
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

#Preview("Chip — Done with image accessory and badge (camera Done-chip)") {
    // Simulates the Done-chip that appears in FCLCameraShutterRow when
    // capturedCount >= 2. A solid-color swatch stands in for an actual capture
    // thumbnail; production code supplies a UIImage decoded from the relay.
    // The accessory is clipped to a continuous 4pt-corner rounded rect, matching
    // FCLCameraShutterRow.thumbnailAccessory.
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
