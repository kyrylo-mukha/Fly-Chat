import CoreGraphics

/// Configuration for compressing media attachments before sending.
public struct FCLMediaCompression: Sendable, Equatable {
    public var maxDimension: CGFloat
    public var jpegQuality: CGFloat
    public var videoExportPreset: FCLVideoExportPreset

    public init(
        maxDimension: CGFloat = 1920,
        jpegQuality: CGFloat = 0.7,
        videoExportPreset: FCLVideoExportPreset = .mediumQuality
    ) {
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
        self.videoExportPreset = videoExportPreset
    }

    public static let `default` = FCLMediaCompression()
}

/// Video export quality presets mapping to AVAssetExportSession preset names.
public enum FCLVideoExportPreset: String, Sendable, Equatable {
    case lowQuality
    case mediumQuality
    case highQuality
    case passthrough
}
