import CoreGraphics
import SwiftUI

/// A layout-direction-aware inset type used throughout FlyChat for padding and spacing.
///
/// Unlike `UIEdgeInsets`, this type uses `leading`/`trailing` instead of `left`/`right`,
/// making it suitable for right-to-left language support. It is `Sendable` and `Hashable`
/// so it can be safely passed across concurrency boundaries and used as a dictionary key.
public struct FCLEdgeInsets: Sendable, Hashable {
    /// The inset from the top edge, in points.
    public let top: CGFloat

    /// The inset from the leading (start) edge, in points.
    public let leading: CGFloat

    /// The inset from the bottom edge, in points.
    public let bottom: CGFloat

    /// The inset from the trailing (end) edge, in points.
    public let trailing: CGFloat

    /// Creates a new edge insets value.
    /// - Parameter top: Inset from the top edge. Defaults to `0`.
    /// - Parameter leading: Inset from the leading edge. Defaults to `0`.
    /// - Parameter bottom: Inset from the bottom edge. Defaults to `0`.
    /// - Parameter trailing: Inset from the trailing edge. Defaults to `0`.
    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// Converts this value to a SwiftUI `EdgeInsets` for use in SwiftUI layout modifiers.
    public var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }
}
