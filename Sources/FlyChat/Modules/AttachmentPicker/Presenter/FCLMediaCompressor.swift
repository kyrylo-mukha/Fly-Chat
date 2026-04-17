#if canImport(UIKit)
import AVFoundation
import Foundation
import UIKit

// MARK: - FCLVideoExportAssetBox

/// Single-owner `Sendable` wrapper around `AVAsset` used to hand an asset off
/// from the PhotoKit callback queue to a detached export `Task`.
///
/// The invariant carried by every instance:
///
/// 1. `asset` is loaded on the `PHImageManager.requestAVAsset` delivery queue.
/// 2. The `withCheckedThrowingContinuation` resume moves the box — and only
///    the box — onto the cooperative executor. The PhotoKit queue retains no
///    observable reference once the continuation has resumed.
/// 3. The receiving `Task` consumes the box exactly once and immediately passes
///    its `asset` to the export helper. No other code reads or mutates the
///    asset after the continuation resumes.
///
/// In other words: the box is consumed exactly once on a single cooperative
/// executor `Task`; no further mutation happens on PhotoKit's delivery queue
/// after the continuation resumes. The `@unchecked Sendable` escape hatch is
/// justified by this single-owner hand-off pattern and must not be generalised
/// to any broader use site.
struct FCLVideoExportAssetBox: @unchecked Sendable {
    let asset: AVAsset
}

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

    // MARK: - Video Export (iOS 18+)

    /// Exports a video `AVAsset` to a temporary MP4 file using the iOS 18
    /// `export(to:as:)` API.
    ///
    /// The `sending` parameter transfers ownership of the asset into this
    /// function so the compiler can verify the caller does not keep an alias
    /// after the call. Combined with the single-owner box hand-off in
    /// `FCLAttachmentPickerSheet.exportVideo(for:preset:)`, this removes the
    /// queue-crossing hazard that caused the `_dispatch_assert_queue_fail`
    /// crash with the legacy mutable-configuration pattern.
    ///
    /// This overload uses the modern throwing API — no mutable `outputURL`
    /// / `outputFileType` setters, and no `session.status` polling after the
    /// export call returns.
    @available(iOS 18, *)
    static func exportVideoV2(
        asset: sending AVAsset,
        preset: FCLVideoExportPreset
    ) async throws -> URL {
        let avPresetName = avPreset(for: preset)
        guard let session = AVAssetExportSession(asset: asset, presetName: avPresetName) else {
            throw FCLCompressionError.exportSessionCreationFailed
        }
        let fileName = "fcl_\(UUID().uuidString.prefix(8)).mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            throw FCLCompressionError.videoExportFailed(error.localizedDescription)
        }
        return outputURL
    }

    // MARK: - Video Export (iOS 17 fallback)

    /// Legacy iOS 17 video export path, kept only as a fallback for devices
    /// that have not yet adopted iOS 18.
    ///
    /// The legacy flow mutates `outputURL` / `outputFileType` on the export
    /// session and then awaits the zero-argument `export()`. It must still be
    /// called from a single cooperative executor `Task` that owns the asset
    /// exclusively — the single-owner `FCLVideoExportAssetBox` hand-off
    /// upstream is what guarantees that invariant.
    @available(iOS, introduced: 17, deprecated: 18, message: "Use iOS 18 export(to:as:).")
    static func exportVideoLegacy(
        asset: AVAsset,
        preset: FCLVideoExportPreset
    ) async throws -> URL {
        let avPresetName = avPreset(for: preset)
        guard let session = AVAssetExportSession(asset: asset, presetName: avPresetName) else {
            throw FCLCompressionError.exportSessionCreationFailed
        }
        let fileName = "fcl_\(UUID().uuidString.prefix(8)).mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        session.outputURL = outputURL
        session.outputFileType = .mp4
        await session.export()
        guard session.status == .completed else {
            throw FCLCompressionError.videoExportFailed(session.error?.localizedDescription ?? "Unknown error")
        }
        return outputURL
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
