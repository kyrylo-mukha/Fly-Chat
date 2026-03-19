import CoreGraphics

/// Delegate protocol for customizing the spatial layout of message bubbles in the chat timeline.
///
/// Implement this protocol in the host app and return it from ``FCLChatDelegate/layout``
/// to control bubble placement (left/right), maximum width, and vertical spacing between messages.
/// Every property has a default implementation that returns the corresponding value from
/// ``FCLLayoutDefaults``, so you only need to override the properties you want to customize.
@MainActor
public protocol FCLLayoutDelegate: AnyObject {
    /// The side of the screen where incoming messages are aligned.
    ///
    /// Default: `.left`.
    var incomingSide: FCLChatBubbleSide { get }

    /// The side of the screen where outgoing messages are aligned.
    ///
    /// Default: `.right`.
    var outgoingSide: FCLChatBubbleSide { get }

    /// The maximum width of a message bubble as a ratio of the available screen width.
    ///
    /// A value of `0.78` means bubbles can occupy up to 78% of the width.
    /// Default: `0.78`.
    var maxBubbleWidthRatio: CGFloat { get }

    /// Vertical spacing (in points) between consecutive messages from the same sender within a group.
    ///
    /// Default: `4`.
    var intraGroupSpacing: CGFloat { get }

    /// Vertical spacing (in points) between message groups from different senders.
    ///
    /// Default: `12`.
    var interGroupSpacing: CGFloat { get }
}

public extension FCLLayoutDelegate {
    var incomingSide: FCLChatBubbleSide { FCLLayoutDefaults.incomingSide }
    var outgoingSide: FCLChatBubbleSide { FCLLayoutDefaults.outgoingSide }
    var maxBubbleWidthRatio: CGFloat { FCLLayoutDefaults.maxBubbleWidthRatio }
    var intraGroupSpacing: CGFloat { FCLLayoutDefaults.intraGroupSpacing }
    var interGroupSpacing: CGFloat { FCLLayoutDefaults.interGroupSpacing }
}
