#if canImport(UIKit)
import UIKit

/// Actor-isolated in-memory avatar image cache, keyed by sender ID.
actor FCLAvatarImageCache {
    private let cache = NSCache<NSString, UIImage>()

    /// Retrieves the cached avatar image for the given sender, if available.
    /// - Parameter senderID: The unique identifier of the sender.
    /// - Returns: The cached `UIImage`, or `nil` if no image is cached for this sender.
    func image(for senderID: String) -> UIImage? {
        cache.object(forKey: senderID as NSString)
    }

    /// Stores an avatar image in the cache for the given sender.
    /// - Parameters:
    ///   - image: The avatar image to cache.
    ///   - senderID: The unique identifier of the sender to associate with the image.
    func store(_ image: UIImage, for senderID: String) {
        cache.setObject(image, forKey: senderID as NSString)
    }
}
#endif
