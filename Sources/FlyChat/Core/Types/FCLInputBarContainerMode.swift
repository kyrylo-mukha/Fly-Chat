import CoreGraphics

/// Determines the visual container style of the chat input bar.
///
/// The input bar can be rendered in several modes that control how the background
/// and text field are visually grouped.
public enum FCLInputBarContainerMode: Sendable, Hashable {
    /// Wraps the entire input bar (field, buttons, and accessories) in a single rounded container.
    ///
    /// - Parameter insets: Padding between the rounded container edge and its contents.
    ///   Defaults to `FCLEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8)`.
    case allInRounded(insets: FCLEdgeInsets = FCLEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8))

    /// Applies rounded styling only to the text field, leaving buttons and accessories unstyled.
    case fieldOnlyRounded

    /// Disables all built-in container styling, allowing the host app to provide its own.
    case custom
}
