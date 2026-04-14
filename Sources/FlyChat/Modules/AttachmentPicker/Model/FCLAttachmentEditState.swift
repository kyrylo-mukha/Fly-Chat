#if canImport(UIKit)
import Foundation
import UIKit

// MARK: - FCLAttachmentEditTool

/// The tool currently being used inside the attachment preview editor.
public enum FCLAttachmentEditTool: Equatable, Sendable {
    /// Rotate / flip / crop the asset in place.
    case rotateCrop
    /// Draw on top of the asset with `PencilKit`.
    case markup
}

// MARK: - FCLAttachmentEditState

/// State machine for the attachment preview screen.
///
/// The preview is a single screen that either renders the normal media pager
/// (``preview``) or replaces the pager with an in-place editor bound to a
/// specific asset (``editing``). Transitions are driven by the toolbar inside
/// the preview; no separate modal is pushed.
public enum FCLAttachmentEditState: Equatable, Sendable {
    /// Baseline state: media pager, thumbnail carousel, input row, edit
    /// toolbar row are all visible.
    case preview
    /// The preview has transformed into an editor for `assetID` using `tool`.
    /// The pager, thumbnails, input row, and edit toolbar row are hidden;
    /// tool-specific chrome is shown instead.
    case editing(tool: FCLAttachmentEditTool, assetID: UUID)

    /// Returns the active tool when `self` is `.editing`, otherwise `nil`.
    public var activeTool: FCLAttachmentEditTool? {
        if case .editing(let tool, _) = self { return tool }
        return nil
    }

    /// Returns the asset ID being edited when `self` is `.editing`,
    /// otherwise `nil`.
    public var editingAssetID: UUID? {
        if case .editing(_, let id) = self { return id }
        return nil
    }
}

// MARK: - FCLAttachmentEditCommit

/// The result of committing an in-place edit. Passed up to the screen's owner
/// so the underlying ``FCLAttachment`` (and its file URL) can be refreshed.
///
/// The `fileURL` points to a freshly written image inside the package's
/// scratch directory (see ``FCLAttachmentEditScratch``). The send path is
/// responsible for attaching that URL — or a further compressed copy of it —
/// when the user taps send.
public struct FCLAttachmentEditCommit: Sendable {
    public let assetID: UUID
    public let tool: FCLAttachmentEditTool
    public let fileURL: URL

    public init(assetID: UUID, tool: FCLAttachmentEditTool, fileURL: URL) {
        self.assetID = assetID
        self.tool = tool
        self.fileURL = fileURL
    }
}

// MARK: - FCLAttachmentEditScratch

/// Helpers for writing committed edits to the package's scratch directory
/// so the send path can pick up the edited bitmap from a stable URL.
enum FCLAttachmentEditScratch {
    /// `tmp/FlyChat/AttachmentEdits/` — created lazily.
    static func directory() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FlyChat", isDirectory: true)
            .appendingPathComponent("AttachmentEdits", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Writes `image` as JPEG (quality 0.92) into the scratch directory and
    /// returns the resulting URL. Each call produces a unique file name so
    /// downstream caches are invalidated.
    static func writeJPEG(_ image: UIImage, assetID: UUID) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let name = "\(assetID.uuidString)-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let url = directory().appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
#endif
