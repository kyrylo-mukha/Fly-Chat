import CoreGraphics
import SwiftUI


// MARK: - FCLBubbleCorners

/// Per-corner radius values for a bubble-related container (e.g., the image grid container).
///
/// Values are in the geometric/absolute coordinate space (topLeft = physical top-left),
/// not layout-direction–relative. The companion helper
/// ``FCLChatBubbleShape/imageContainerCorners(side:tailStyle:contentAbove:contentBelow:)``
/// computes correct values based on the bubble's side and tail style.
public struct FCLBubbleCorners: Sendable, Equatable {
    /// Radius at the top-left corner (physical, not leading/trailing).
    public var topLeft: CGFloat
    /// Radius at the top-right corner.
    public var topRight: CGFloat
    /// Radius at the bottom-left corner.
    public var bottomLeft: CGFloat
    /// Radius at the bottom-right corner.
    public var bottomRight: CGFloat

    /// Initialises a corners descriptor.
    public init(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    /// All corners equal to the same radius.
    public static func uniform(_ r: CGFloat) -> FCLBubbleCorners {
        FCLBubbleCorners(topLeft: r, topRight: r, bottomLeft: r, bottomRight: r)
    }
}

/// Represents which side of the chat timeline a message bubble is placed on.
public enum FCLChatBubbleSide: String, Sendable, Hashable {
    /// The bubble is aligned to the left (typically incoming messages).
    case left
    /// The bubble is aligned to the right (typically outgoing messages).
    case right
}

/// The vertical edge where a bubble tail (reduced-radius corner) appears.
public enum FCLBubbleTailEdge: Sendable, Hashable {
    /// The tail appears at the top of the bubble.
    case top
    /// The tail appears at the bottom of the bubble.
    case bottom
}

/// Controls the visual tail style of a chat bubble.
///
/// Used by ``FCLChatBubbleShape`` to determine corner radii.
/// In grouped conversations the presenter assigns `.none` to mid-group bubbles
/// and `.edged` to the first or last bubble in a sender run.
public enum FCLBubbleTailStyle: Sendable, Hashable {
    /// Regular rounded rectangle with uniform corner radius.
    case none
    /// One corner on the tail side has a reduced radius (~6pt).
    case edged(FCLBubbleTailEdge)
}

/// Lightweight bubble shape with configurable tail style.
///
/// Draws a rounded rectangle where one corner can have a smaller radius to indicate
/// the "tail" of a chat bubble (similar to iMessage). The shape supports smooth
/// animation between tail styles via ``animatableData``.
public struct FCLChatBubbleShape: Shape, Sendable, Hashable {
    /// The side of the screen the bubble is placed on.
    public let side: FCLChatBubbleSide
    /// The tail style that determines which corner (if any) gets a reduced radius.
    public let tailStyle: FCLBubbleTailStyle

    /// The current corner radius for the edged (tail) corner. Animatable between
    /// ``standardRadius`` (17pt, when `.none`) and ``reducedRadius`` (6pt, when `.edged`).
    public var edgedCornerRadius: CGFloat

    /// The default corner radius applied to all non-tail corners.
    ///
    /// Exposed as internal so that attachment mask shapes can reference the canonical
    /// bubble top radius without duplicating the constant.
    static let standardRadius: CGFloat = 17
    /// The smaller corner radius applied to the tail corner in `.edged` style.
    private static let reducedRadius: CGFloat = 6

    /// Creates a bubble shape with the specified side and tail style.
    ///
    /// - Parameters:
    ///   - side: Which side of the chat timeline the bubble appears on.
    ///   - tailStyle: The tail style controlling corner radius variation. Defaults to `.edged(.bottom)`.
    public init(side: FCLChatBubbleSide, tailStyle: FCLBubbleTailStyle = .edged(.bottom)) {
        self.side = side
        self.tailStyle = tailStyle
        switch tailStyle {
        case .none:
            self.edgedCornerRadius = Self.standardRadius
        case .edged:
            self.edgedCornerRadius = Self.reducedRadius
        }
    }

    /// The animatable property that drives smooth corner radius transitions between tail styles.
    public var animatableData: CGFloat {
        get { edgedCornerRadius }
        set { edgedCornerRadius = newValue }
    }

    // MARK: - Image Container Corner Helper

    /// Computes the per-corner radii that an image container inside a chat bubble should use
    /// so that its visible (edge-touching) corners are concentric with the bubble's own corners.
    ///
    /// Rules applied:
    /// - A corner that is **flush with the bubble edge** and is **not occluded by adjacent content**
    ///   inherits the bubble's corner radius at that position (standard or reduced for the tail corner).
    /// - A corner where content is stacked above or below the container becomes **square** (radius 0)
    ///   so there is no visible gap between the image and the adjacent content.
    ///
    /// - Parameters:
    ///   - side: Which side of the bubble the message is on (left = incoming, right = outgoing).
    ///   - tailStyle: The bubble's current tail style — determines which corner has a reduced radius.
    ///   - contentAbove: Pass `true` when another content element (text, file row) sits above the image
    ///     container inside the same bubble. The container's top corners will be squared.
    ///   - contentBelow: Pass `true` when another content element sits below the image container.
    ///     The container's bottom corners will be squared.
    /// - Returns: ``FCLBubbleCorners`` with the appropriate radius at each corner.
    static func imageContainerCorners(
        side: FCLChatBubbleSide,
        tailStyle: FCLBubbleTailStyle,
        contentAbove: Bool,
        contentBelow: Bool
    ) -> FCLBubbleCorners {
        let r = standardRadius
        let er = reducedRadius
        let isRight = side == .right

        var tl, tr, bl, br: CGFloat
        switch tailStyle {
        case .none:
            tl = r; tr = r; bl = r; br = r
        case .edged(.bottom):
            if isRight { tl = r; tr = r; bl = r; br = er }
            else        { tl = r; tr = r; bl = er; br = r }
        case .edged(.top):
            if isRight { tl = r; tr = er; bl = r; br = r }
            else        { tl = er; tr = r; bl = r; br = r }
        }

        if contentAbove { tl = 0; tr = 0 }
        if contentBelow { bl = 0; br = 0 }

        return FCLBubbleCorners(topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br)
    }

    /// Generates the rounded rectangle path with per-corner radii based on the current tail style and side.
    ///
    /// - Parameter rect: The bounding rectangle of the shape.
    /// - Returns: A `Path` describing the bubble outline.
    public func path(in rect: CGRect) -> Path {
        let r = Self.standardRadius
        let er = edgedCornerRadius
        let isRight = side == .right

        let topLeft: CGFloat
        let topRight: CGFloat
        let bottomLeft: CGFloat
        let bottomRight: CGFloat

        switch tailStyle {
        case .none:
            topLeft = r; topRight = r; bottomLeft = r; bottomRight = r
        case .edged(.bottom):
            if isRight {
                topLeft = r; topRight = r; bottomLeft = r; bottomRight = er
            } else {
                topLeft = r; topRight = r; bottomLeft = er; bottomRight = r
            }
        case .edged(.top):
            if isRight {
                topLeft = r; topRight = er; bottomLeft = r; bottomRight = r
            } else {
                topLeft = er; topRight = r; bottomLeft = r; bottomRight = r
            }
        }

        return roundedRectPath(
            in: rect,
            topLeft: topLeft,
            topRight: topRight,
            bottomLeft: bottomLeft,
            bottomRight: bottomRight
        )
    }

    /// Draws a rounded rectangle path with independent corner radii using arc segments.
    ///
    /// - Parameters:
    ///   - rect: The bounding rectangle.
    ///   - topLeft: Corner radius for the top-left corner.
    ///   - topRight: Corner radius for the top-right corner.
    ///   - bottomLeft: Corner radius for the bottom-left corner.
    ///   - bottomRight: Corner radius for the bottom-right corner.
    /// - Returns: A closed `Path` forming the rounded rectangle.
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
struct FCLChatBubbleShape_Previews: PreviewProvider {
    static var previews: some View {
        allTailStylesPreview
        imageContainerCornersPreview
    }

    private static var allTailStylesPreview: some View {
        VStack(spacing: 16) {
            ForEach(
                [FCLBubbleTailStyle.none, .edged(.bottom), .edged(.top)],
                id: \.self
            ) { style in
                HStack(spacing: 20) {
                    FCLChatBubbleShape(side: .left, tailStyle: style)
                        .fill(Color(red: 0.93, green: 0.93, blue: 0.95))
                        .frame(width: 160, height: 60)

                    FCLChatBubbleShape(side: .right, tailStyle: style)
                        .fill(Color.blue)
                        .frame(width: 160, height: 60)
                }
            }
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .previewDisplayName("All Tail Styles × Both Sides")
    }

    private static var imageContainerCornersPreview: some View {
        let scenarios: [(String, FCLBubbleCorners)] = [
            ("Image-only (right, edged bottom)",
             FCLChatBubbleShape.imageContainerCorners(side: .right, tailStyle: .edged(.bottom), contentAbove: false, contentBelow: false)),
            ("Image+text below (right, edged bottom)",
             FCLChatBubbleShape.imageContainerCorners(side: .right, tailStyle: .edged(.bottom), contentAbove: false, contentBelow: true)),
            ("Text above+image (left, edged bottom)",
             FCLChatBubbleShape.imageContainerCorners(side: .left, tailStyle: .edged(.bottom), contentAbove: true, contentBelow: false)),
            ("Sandwiched (left, none)",
             FCLChatBubbleShape.imageContainerCorners(side: .left, tailStyle: .none, contentAbove: true, contentBelow: true)),
        ]
        return VStack(spacing: 12) {
            ForEach(Array(scenarios.enumerated()), id: \.offset) { _, scenario in
                let corners = scenario.1
                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.0)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: corners.topLeft,
                            bottomLeading: corners.bottomLeft,
                            bottomTrailing: corners.bottomRight,
                            topTrailing: corners.topRight
                        )
                    )
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 160, height: 50)
                }
            }
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .previewDisplayName("imageContainerCorners Scenarios")
    }
}
#endif
