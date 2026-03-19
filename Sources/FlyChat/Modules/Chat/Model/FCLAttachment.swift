import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// The kind of media or file represented by an attachment.
public enum FCLAttachmentType: String, Sendable, Hashable {
    /// A still image (JPEG, PNG, etc.).
    case image
    /// A video file.
    case video
    /// A generic document or file.
    case file
}

/// A media or file attachment associated with a chat message.
public struct FCLAttachment: Identifiable, Hashable, Sendable {
    /// Unique identifier for the attachment.
    public let id: UUID
    /// The kind of content this attachment represents (image, video, or file).
    public let type: FCLAttachmentType
    /// The local or remote URL pointing to the attachment data.
    public let url: URL
    /// Raw PNG data for a preview thumbnail, if available.
    public let thumbnailData: Data?
    /// The original or generated file name for display purposes.
    public let fileName: String
    /// The size of the file in bytes, if known.
    public let fileSize: Int64?

    /// Creates a new attachment with raw thumbnail data.
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - type: The kind of content (image, video, or file).
    ///   - url: The local or remote URL pointing to the attachment data.
    ///   - thumbnailData: Raw PNG data for a preview thumbnail. Defaults to `nil`.
    ///   - fileName: The file name for display purposes.
    ///   - fileSize: The size of the file in bytes. Defaults to `nil`.
    public init(
        id: UUID = UUID(),
        type: FCLAttachmentType,
        url: URL,
        thumbnailData: Data? = nil,
        fileName: String,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.thumbnailData = thumbnailData
        self.fileName = fileName
        self.fileSize = fileSize
    }

    #if canImport(UIKit)
    /// A `UIImage` decoded from `thumbnailData`, or `nil` if no thumbnail data exists.
    public var thumbnailImage: UIImage? {
        thumbnailData.flatMap { UIImage(data: $0) }
    }

    /// Creates a new attachment using a `UIImage` as the thumbnail source.
    ///
    /// The image is converted to PNG data internally for `Sendable`-safe storage.
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - type: The kind of content (image, video, or file).
    ///   - url: The local or remote URL pointing to the attachment data.
    ///   - thumbnail: A `UIImage` to use as the preview thumbnail. Defaults to `nil`.
    ///   - fileName: The file name for display purposes.
    ///   - fileSize: The size of the file in bytes. Defaults to `nil`.
    public init(
        id: UUID = UUID(),
        type: FCLAttachmentType,
        url: URL,
        thumbnail: UIImage?,
        fileName: String,
        fileSize: Int64? = nil
    ) {
        self.init(
            id: id,
            type: type,
            url: url,
            thumbnailData: thumbnail?.pngData(),
            fileName: fileName,
            fileSize: fileSize
        )
    }
    #endif
}
