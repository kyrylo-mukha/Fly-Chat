#if canImport(UIKit)
import Foundation
import UIKit

/// Asynchronous, `NSCache`-backed loader that decodes downscaled thumbnails from attachment URLs.
final actor FCLAsyncThumbnailLoader {
    static let shared = FCLAsyncThumbnailLoader()

    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    func thumbnail(for attachment: FCLAttachment, targetSize: CGSize) async -> UIImage? {
        let key = "\(attachment.id.uuidString)-\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let url = attachment.url
        guard let data = try? Data(contentsOf: url),
              let source = UIImage(data: data) else { return nil }

        let scaled = source.downscaled(to: targetSize) ?? source
        cache.setObject(scaled, forKey: key)
        return scaled
    }

    /// Returns the natural pixel size of the underlying asset, or nil if unavailable.
    func pixelSize(for attachment: FCLAttachment) async -> CGSize? {
        let url = attachment.url
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
}

private extension UIImage {
    func downscaled(to target: CGSize) -> UIImage? {
        let srcSize = size
        guard srcSize.width > 0, srcSize.height > 0 else { return nil }
        let scale = min(target.width / srcSize.width, target.height / srcSize.height, 1.0)
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = self.scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif
