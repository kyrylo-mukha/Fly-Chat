import CoreGraphics
import SwiftUI

// MARK: - FCLAttachmentMaskShape

/// The masking shape applied to the attachment grid container inside a chat bubble.
///
/// Two modes are available:
/// - ``FCLAttachmentMaskMode/bubble(topRadius:bottomRadius:tail:)`` — used when the message has
///   no text. The mask reproduces the full bubble outline (tail corner + all rounded corners)
///   so the grid is visually flush with the bubble shape.
/// - ``FCLAttachmentMaskMode/topRoundedBottomFlat(topRadius:)`` — used when text follows the
///   attachment grid below it. The top corners are rounded to the bubble's top radius; the
///   bottom edge is a straight cut with no rounding, creating a clean boundary between the
///   grid and the text below.
public enum FCLAttachmentMaskMode: Sendable, Equatable {
    /// Full-bubble mask: all corners are rounded and the tail corner uses a reduced radius.
    ///
    /// - Parameters:
    ///   - topRadius: The corner radius at the two non-tail top corners.
    ///   - bottomRadius: The corner radius at the two non-tail bottom corners.
    ///   - side: Which side of the timeline the bubble appears on (determines tail corner position).
    ///   - tailStyle: The bubble's tail style.
    case bubble(topRadius: CGFloat, bottomRadius: CGFloat, side: FCLChatBubbleSide, tailStyle: FCLBubbleTailStyle)

    /// Top-rounded, bottom-flat mask: the top edge is rounded; the bottom edge is straight.
    ///
    /// Symmetric across incoming and outgoing. Use when text content follows below the grid.
    ///
    /// - Parameter topRadius: The radius applied to both top corners.
    case topRoundedBottomFlat(topRadius: CGFloat)
}

/// A SwiftUI `Shape` that clips the attachment grid container inside a chat bubble.
///
/// Instantiate with an ``FCLAttachmentMaskMode`` and apply via `.clipShape(FCLAttachmentMaskShape(mode))`.
/// The `.bubble` mode delegates its corner computation to
/// ``FCLChatBubbleShape/imageContainerCorners(side:tailStyle:contentAbove:contentBelow:)`` so
/// geometry stays consistent with the bubble outline.
public struct FCLAttachmentMaskShape: Shape, Sendable {
    /// The masking mode that determines the shape geometry.
    public let mode: FCLAttachmentMaskMode

    /// Creates an attachment mask shape with the given mode.
    public init(_ mode: FCLAttachmentMaskMode) {
        self.mode = mode
    }

    /// Generates the clip path for the attachment grid container.
    public func path(in rect: CGRect) -> Path {
        switch mode {
        case let .bubble(_, _, side, tailStyle):
            // Derive per-corner radii by calling the shared imageContainerCorners helper.
            // topRadius and bottomRadius stored in the enum are for API documentation purposes;
            // the actual radii are computed canonically from FCLChatBubbleShape.
            // The grid is image-only when this mode is used, so no content above or below.
            let corners = FCLChatBubbleShape.imageContainerCorners(
                side: side,
                tailStyle: tailStyle,
                contentAbove: false,
                contentBelow: false
            )
            return roundedRectPath(
                in: rect,
                topLeft: corners.topLeft,
                topRight: corners.topRight,
                bottomLeft: corners.bottomLeft,
                bottomRight: corners.bottomRight
            )

        case let .topRoundedBottomFlat(topRadius):
            // Top-left and top-right corners are rounded; bottom edge is straight.
            return roundedRectPath(
                in: rect,
                topLeft: topRadius,
                topRight: topRadius,
                bottomLeft: 0,
                bottomRight: 0
            )
        }
    }

    // MARK: - Private path builder

    /// Draws a rounded rectangle path with independent per-corner radii.
    private func roundedRectPath(
        in rect: CGRect,
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomLeft: CGFloat,
        bottomRight: CGFloat
    ) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: topLeft, y: 0))

        path.addLine(to: CGPoint(x: w - topRight, y: 0))
        path.addArc(
            center: CGPoint(x: w - topRight, y: topRight),
            radius: topRight,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: w, y: h - bottomRight))
        path.addArc(
            center: CGPoint(x: w - bottomRight, y: h - bottomRight),
            radius: bottomRight,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: bottomLeft, y: h))
        path.addArc(
            center: CGPoint(x: bottomLeft, y: h - bottomLeft),
            radius: bottomLeft,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: 0, y: topLeft))
        path.addArc(
            center: CGPoint(x: topLeft, y: topLeft),
            radius: topLeft,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("Bubble Mask — Outgoing, Edged Bottom, 1 Attachment") {
    FCLAttachmentMaskShape(
        .bubble(
            topRadius: 17,
            bottomRadius: 17,
            side: .right,
            tailStyle: .edged(.bottom)
        )
    )
    .fill(Color.blue.opacity(0.4))
    .frame(width: 240, height: 180)
    .padding()
}

#Preview("Bubble Mask — Incoming, Edged Bottom, 1 Attachment") {
    FCLAttachmentMaskShape(
        .bubble(
            topRadius: 17,
            bottomRadius: 17,
            side: .left,
            tailStyle: .edged(.bottom)
        )
    )
    .fill(Color.gray.opacity(0.4))
    .frame(width: 240, height: 180)
    .padding()
}

#Preview("Top-Rounded Bottom-Flat Mask (text below)") {
    VStack(spacing: 0) {
        FCLAttachmentMaskShape(.topRoundedBottomFlat(topRadius: 17))
            .fill(Color.blue.opacity(0.4))
            .frame(width: 240, height: 160)
        Rectangle()
            .fill(Color.blue.opacity(0.2))
            .frame(width: 240, height: 40)
    }
    .padding()
}
#endif
