/// The top-level delegate that the host app implements to customize the chat experience.
///
/// `FCLChatDelegate` acts as a delegate hub, providing access to specialized sub-delegates
/// for appearance, avatars, layout, and input bar configuration. Each sub-delegate is optional;
/// when `nil`, the library uses built-in defaults defined in ``FCLDelegateDefaults``.
///
/// Conforming types must be `AnyObject` (reference types) and are confined to `@MainActor`
/// because delegate properties drive UI configuration.
@MainActor
public protocol FCLChatDelegate: AnyObject {
    /// Delegate that controls bubble colors, text colors, fonts, tail style, and other visual properties.
    ///
    /// Return `nil` to use the library's default appearance.
    var appearance: (any FCLAppearanceDelegate)? { get }

    /// Delegate that controls avatar display, sizing, caching, and URL resolution.
    ///
    /// Return `nil` to use the library's default avatar behavior.
    var avatar: (any FCLAvatarDelegate)? { get }

    /// Delegate that controls bubble placement, sizing, and spacing in the chat timeline.
    ///
    /// Return `nil` to use the library's default layout.
    var layout: (any FCLLayoutDelegate)? { get }

    /// Delegate that controls input bar appearance and behavior.
    ///
    /// Return `nil` to use the library's default input bar configuration.
    var input: (any FCLInputDelegate)? { get }
}

public extension FCLChatDelegate {
    var appearance: (any FCLAppearanceDelegate)? { nil }
    var avatar: (any FCLAvatarDelegate)? { nil }
    var layout: (any FCLLayoutDelegate)? { nil }
    var input: (any FCLInputDelegate)? { nil }
}
