import SwiftUI

// MARK: - Double-Checkmark Path

/// A shape that draws two overlapping checkmark strokes, used to represent the "read" status.
///
/// There is no public SF Symbol that reliably represents a double checkmark across all
/// supported iOS versions (17+). This custom `Shape` draws two strokes directly —
/// matching the convention established by mainstream messaging apps.
private struct FCLDoubleCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // First (left) checkmark
        let offset: CGFloat = w * 0.18
        path.move(to: CGPoint(x: rect.minX, y: h * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.28, y: h * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.58 - offset, y: h * 0.28))

        // Second (right) checkmark — shifted right
        path.move(to: CGPoint(x: rect.minX + w * 0.22, y: h * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.50, y: h * 0.82))
        path.addLine(to: CGPoint(x: rect.maxX, y: h * 0.18))

        return path
    }
}

// MARK: - FCLChatMessageStatusView

/// A compact SwiftUI view that renders a delivery-status glyph adjacent to the message timestamp.
///
/// The glyph scales with the `.caption2` font metric and is tinted according to the
/// colors provided by `FCLAppearanceDelegate.statusColors`. Custom icons supplied via
/// `FCLAppearanceDelegate.statusIcons` are applied with `.renderingMode(.template)` so
/// they receive the color tint; if the host provides a symbol using `.original` rendering
/// mode, SwiftUI respects that and the tint is not forced.
///
/// - Note: This view is only rendered for outgoing messages when
///   `FCLLayoutDelegate.showsStatusForOutgoing` is `true`. Incoming messages never show
///   the status indicator.
@MainActor
public struct FCLChatMessageStatusView: View {
    /// The delivery status to display.
    public let status: FCLChatMessageStatus
    /// The color token applied to the glyph.
    public let color: FCLChatColorToken
    /// An optional custom icon that overrides the default SF Symbol / path glyph.
    ///
    /// When `nil`, the built-in default glyph for the given `status` is used.
    public let customIcon: Image?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a status view.
    /// - Parameters:
    ///   - status: The delivery status to render.
    ///   - color: The color token applied to the glyph. Defaults to white at 60% opacity,
    ///     matching the muted foreground used inside outgoing bubbles.
    ///   - customIcon: An optional host-provided image. When non-nil it replaces the built-in glyph.
    public init(
        status: FCLChatMessageStatus,
        color: FCLChatColorToken = FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.6),
        customIcon: Image? = nil
    ) {
        self.status = status
        self.color = color
        self.customIcon = customIcon
    }

    public var body: some View {
        glyph
            .transaction { t in
                if reduceMotion {
                    t.disablesAnimations = true
                }
            }
    }

    @ViewBuilder
    private var glyph: some View {
        if let icon = customIcon {
            icon
                .renderingMode(.template)
                .foregroundColor(color.color)
                .font(.caption2)
        } else {
            switch status {
            case .created:
                Image(systemName: "clock")
                    .renderingMode(.template)
                    .foregroundColor(color.color)
                    .font(.caption2)

            case .sent:
                Image(systemName: "checkmark")
                    .renderingMode(.template)
                    .foregroundColor(color.color)
                    .font(.caption2)

            case .read:
                FCLDoubleCheckmarkShape()
                    .stroke(color.color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 10)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Created — Default Color") {
    FCLChatMessageStatusView(status: .created)
        .padding()
}

#Preview("Sent — Default Color") {
    FCLChatMessageStatusView(status: .sent)
        .padding()
}

#Preview("Read — Accent Color") {
    FCLChatMessageStatusView(
        status: .read,
        color: FCLChatColorToken(red: 0.27, green: 0.78, blue: 0.47)
    )
    .padding()
}

#Preview("All Three States") {
    HStack(spacing: 12) {
        FCLChatMessageStatusView(
            status: .created,
            color: FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.6)
        )
        FCLChatMessageStatusView(
            status: .sent,
            color: FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.6)
        )
        FCLChatMessageStatusView(
            status: .read,
            color: FCLChatColorToken(red: 0.27, green: 0.78, blue: 0.47)
        )
    }
    .padding()
    .background(Color(red: 0.0, green: 0.48, blue: 1.0))
    .cornerRadius(12)
    .padding()
}

#Preview("Custom Icons — Outgoing Bubble Context") {
    let customDelegate = FCLStatusPreviewDelegate()
    HStack(spacing: 12) {
        FCLChatMessageStatusView(
            status: .created,
            color: customDelegate.statusColors.created,
            customIcon: customDelegate.statusIcons.created
        )
        FCLChatMessageStatusView(
            status: .sent,
            color: customDelegate.statusColors.sent,
            customIcon: customDelegate.statusIcons.sent
        )
        FCLChatMessageStatusView(
            status: .read,
            color: customDelegate.statusColors.read,
            customIcon: customDelegate.statusIcons.read
        )
    }
    .padding()
    .background(Color(red: 0.0, green: 0.48, blue: 1.0))
    .cornerRadius(12)
    .padding()
}

@MainActor
private final class FCLStatusPreviewDelegate: FCLAppearanceDelegate {
    var statusIcons: FCLChatStatusIcons {
        FCLChatStatusIcons(
            created: Image(systemName: "clock.badge"),
            sent: Image(systemName: "checkmark.circle"),
            read: Image(systemName: "checkmark.circle.fill")
        )
    }
    var statusColors: FCLChatStatusColors {
        FCLChatStatusColors(
            created: FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.6),
            sent: FCLChatColorToken(red: 1, green: 1, blue: 1, alpha: 0.8),
            read: FCLChatColorToken(red: 0.4, green: 0.9, blue: 0.5)
        )
    }
}
#endif
