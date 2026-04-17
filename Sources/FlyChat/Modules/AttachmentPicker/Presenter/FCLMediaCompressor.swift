#if canImport(UIKit)
import AVFoundation
import Foundation
import UIKit

enum FCLMediaCompressor {

    static func downscale(_ image: UIImage, config: FCLMediaCompression) -> UIImage {
        let maxDim = config.maxDimension
        let size = image.size
        guard size.width > maxDim || size.height > maxDim else { return image }
        let scale: CGFloat = size.width > size.height ? maxDim / size.width : maxDim / size.height
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    static func compressToJPEG(_ image: UIImage, quality: CGFloat) -> Data? {
        image.jpegData(compressionQuality: quality)
    }

    static func compressImageToTempFile(_ image: UIImage, config: FCLMediaCompression) throws -> URL {
        let downscaled = downscale(image, config: config)
        guard let data = compressToJPEG(downscaled, quality: config.jpegQuality) else {
            throw FCLCompressionError.jpegEncodingFailed
        }
        let fileName = "fcl_\(UUID().uuidString.prefix(8)).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }

    static func avPreset(for preset: FCLVideoExportPreset) -> String {
        switch preset {
        case .lowQuality: return AVAssetExportPresetLowQuality
        case .mediumQuality: return AVAssetExportPresetMediumQuality
        case .highQuality: return AVAssetExportPresetHighestQuality
        case .passthrough: return AVAssetExportPresetPassthrough
        }
    }
}

enum FCLCompressionError: Error, LocalizedError {
    case jpegEncodingFailed
    case exportSessionCreationFailed
    case videoExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .jpegEncodingFailed: return "Failed to encode image as JPEG"
        case .exportSessionCreationFailed: return "Failed to create video export session"
        case .videoExportFailed(let reason): return "Video export failed: \(reason)"
        }
    }
}
#endif
