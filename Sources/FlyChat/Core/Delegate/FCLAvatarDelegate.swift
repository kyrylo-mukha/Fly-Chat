import CoreGraphics
import Foundation

/// Delegate protocol for customizing avatar display, image resolution, and caching in the chat timeline.
///
/// Implement this protocol in the host app and return it from ``FCLChatDelegate/avatar``
/// to control avatar sizing, visibility, placeholder images, and remote URL resolution.
/// Every property has a default implementation, so you only need to override what you want to customize.
@MainActor
public protocol FCLAvatarDelegate: AnyObject {
    /// The width and height (in points) of each avatar image in the chat timeline.
    ///
    /// Default: `40`.
    var avatarSize: CGFloat { get }

    /// Whether to display an avatar next to outgoing (sent) messages.
    ///
    /// Default: `false`.
    var showOutgoingAvatar: Bool { get }

    /// Whether to display an avatar next to incoming (received) messages.
    ///
    /// Default: `true`.
    var showIncomingAvatar: Bool { get }

    /// A fallback image shown when no avatar is available for a sender.
    ///
    /// Return `nil` to use the library's built-in placeholder.
    /// Default: `nil`.
    var defaultAvatarImage: FCLImageSource? { get }

    /// An optional avatar image cache delegate for storing and retrieving avatar data.
    ///
    /// When provided, the library checks this cache before making network requests.
    /// Default: `nil` (no caching).
    var cache: (any FCLAvatarCacheDelegate)? { get }

    /// Resolves the remote URL for a given sender's avatar image.
    ///
    /// The library calls this method when it needs to display an avatar and no cached
    /// image is available. Return `nil` if no avatar URL is known for the sender.
    ///
    /// - Parameter senderID: The unique identifier of the message sender.
    /// - Returns: A URL pointing to the sender's avatar image, or `nil` if unavailable.
    func avatarURL(for senderID: String) async -> URL?
}

public extension FCLAvatarDelegate {
    var avatarSize: CGFloat { FCLAvatarDefaults.avatarSize }
    var showOutgoingAvatar: Bool { FCLAvatarDefaults.showOutgoingAvatar }
    var showIncomingAvatar: Bool { FCLAvatarDefaults.showIncomingAvatar }
    var defaultAvatarImage: FCLImageSource? { nil }
    var cache: (any FCLAvatarCacheDelegate)? { nil }
    func avatarURL(for senderID: String) async -> URL? { nil }
}

/// Delegate protocol for caching avatar image data.
///
/// Implement this protocol and provide it via ``FCLAvatarDelegate/cache`` to enable
/// persistent or in-memory caching of downloaded avatar images. Both methods are `async`
/// to support disk-based or remote cache backends. Conforming types must be `Sendable`
/// since cache operations may be invoked from background contexts.
public protocol FCLAvatarCacheDelegate: AnyObject, Sendable {
    /// Retrieves cached avatar image data for the given sender.
    ///
    /// - Parameter senderID: The unique identifier of the message sender.
    /// - Returns: The cached image data as `Data`, or `nil` if no cached image exists.
    func cachedImage(for senderID: String) async -> Data?

    /// Stores avatar image data in the cache for the given sender.
    ///
    /// - Parameter data: The raw image data to cache.
    /// - Parameter senderID: The unique identifier of the message sender.
    func cacheImage(_ data: Data, for senderID: String) async
}
