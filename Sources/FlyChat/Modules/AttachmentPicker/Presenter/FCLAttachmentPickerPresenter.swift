// MARK: - Host app Info.plist requirements
//
// The host app must declare the following keys in its Info.plist before using
// the attachment picker's camera feature:
//
//   NSCameraUsageDescription      — describes why camera access is needed.
//   NSMicrophoneUsageDescription  — describes why microphone access is needed
//                                   (required when video recording is enabled).
//
// Failing to include these keys causes the system to terminate the host app
// when camera or microphone authorization is requested.

#if canImport(UIKit)
import Combine
import Foundation
import Photos
import UIKit

enum FCLAttachmentPickerState: Equatable {
    case browsing
    case gallerySelected
    case sending
    case error(String)
}

@MainActor
final class FCLAttachmentPickerPresenter: ObservableObject {
    @Published private(set) var state: FCLAttachmentPickerState = .browsing
    @Published private(set) var selectedTab: FCLPickerTab = .gallery
    @Published private(set) var selectedAssets: [String] = []
    @Published private(set) var cameraCaptures: [FCLAttachment] = []
    @Published var captionText: String = ""

    // MARK: - Scope A state (file search + presentation completion)

    /// Whether the Files-tab search morph is open. When `.open`, the top toolbar
    /// swaps to a search text field + Cancel button and the Files tab filters
    /// its recent-files list by ``fileSearchText``.
    @Published private(set) var fileSearchState: FileSearchState = .closed

    /// Current query text bound by the search text field when
    /// ``fileSearchState`` is `.open`. Always empty when the search is closed.
    @Published var fileSearchText: String = ""

    /// Set to `true` after the sheet's presentation animation has finished.
    /// Downstream side effects that would block the animation (notably the
    /// `PHPhotoLibrary` authorization request and the initial PHAsset fetch)
    /// wait for this flag before running.
    @Published private(set) var isPresentationComplete: Bool = false

    /// States for the in-sheet Files search morph.
    public enum FileSearchState: Sendable, Hashable {
        case closed
        case open
    }

    // MARK: - Per-asset edit state

    @Published private(set) var editedImageByAssetID: [String: UIImage] = [:]

    private let delegate: (any FCLAttachmentDelegate)?
    private let onSend: @MainActor ([FCLAttachment], String?) -> Void
    /// Optional callback invoked when a send-path error occurs after the picker
    /// modal stack has been dismissed. The host (typically the chat screen)
    /// forwards this to ``FCLChatPresenter/reportSendError(_:)`` so the error
    /// surfaces as a toast on the chat, not on the already-gone sheet.
    private let onSendError: (@MainActor (String) -> Void)?

    init(
        delegate: (any FCLAttachmentDelegate)?,
        onSend: @escaping @MainActor ([FCLAttachment], String?) -> Void,
        onSendError: (@MainActor (String) -> Void)? = nil
    ) {
        self.delegate = delegate
        self.onSend = onSend
        self.onSendError = onSendError
    }

    /// Reports an error originating from an asynchronous send operation to the
    /// host, after the picker modal has already been dismissed. Also updates
    /// local state so any still-attached picker surface can react.
    func reportSendError(_ message: String) {
        onSendError?(message)
        state = .error(message)
    }

    /// Clears all per-asset edit state (bitmaps and tool history). Called on
    /// send completion, on dismiss, and whenever the staged asset set empties.
    func clearEditState() {
        editedImageByAssetID.removeAll()
    }

    var availableTabs: [FCLPickerTab] {
        var tabs: [FCLPickerTab] = [.gallery]
        if delegate?.isFileTabEnabled ?? FCLAttachmentDefaults.isFileTabEnabled {
            tabs.append(.file)
        }
        for (index, tab) in (delegate?.customTabs ?? []).enumerated() {
            tabs.append(.custom(id: "\(tab.tabTitle)-\(index)"))
        }
        return tabs
    }

    func selectTab(_ tab: FCLPickerTab) {
        guard state == .browsing else { return }
        selectedTab = tab
    }

    // MARK: - Scope A actions

    /// Opens the Files-tab search morph. Keeps any existing ``fileSearchText``.
    func beginFileSearch() {
        fileSearchState = .open
    }

    /// Closes the Files-tab search morph and clears the query.
    func cancelFileSearch() {
        fileSearchState = .closed
        fileSearchText = ""
    }

    /// Signals that the sheet's presentation animation has finished. Gated downstream
    /// side effects (permission request, initial asset fetch) may now run. The call
    /// is idempotent — repeated invocations are no-ops.
    func markPresentationComplete() {
        guard !isPresentationComplete else { return }
        isPresentationComplete = true
    }

    func toggleAssetSelection(_ assetID: String) {
        if let index = selectedAssets.firstIndex(of: assetID) {
            selectedAssets.remove(at: index)
        } else {
            selectedAssets.append(assetID)
        }
        state = selectedAssets.isEmpty ? .browsing : .gallerySelected
        // Drop any edit state when the selection empties — otherwise stale
        // per-asset edits would apply to a future, unrelated selection.
        if selectedAssets.isEmpty {
            clearEditState()
        }
    }

    func beginSending() {
        state = .sending
    }

    func sendFileAttachment(_ attachment: FCLAttachment) {
        state = .sending
        Task { await FCLRecentFilesStore.shared.add(fileURL: attachment.url, fileName: attachment.fileName, fileSize: attachment.fileSize) }
        onSend([attachment], nil)
    }

    func sendGalleryAttachments(_ attachments: [FCLAttachment]) {
        state = .sending
        let caption = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        for attachment in attachments {
            Task { await FCLRecentFilesStore.shared.add(fileURL: attachment.url, fileName: attachment.fileName, fileSize: attachment.fileSize) }
        }
        onSend(attachments, caption.isEmpty ? nil : caption)
        clearEditState()
    }

    func appendCameraCapture(_ attachment: FCLAttachment) {
        cameraCaptures.append(attachment)
        state = .gallerySelected
    }

    /// Converts an array of ``FCLCameraCaptureResult`` values (produced by the Camera module)
    /// into ``FCLAttachment`` values and appends them to `cameraCaptures`.
    ///
    /// File size is read from the filesystem on-the-fly; if the file is unavailable
    /// the size is left as `nil`. Thumbnail data is decoded from `thumbnailURL` when
    /// present; otherwise the field is `nil`.
    func appendCameraResults(_ results: [FCLCameraCaptureResult]) {
        for result in results {
            let fileSize = (try? FileManager.default.attributesOfItem(
                atPath: result.fileURL.path
            )[.size] as? Int64) ?? nil

            let thumbnailData: Data? = result.thumbnailURL.flatMap { url in
                try? Data(contentsOf: url)
            }

            let attachmentType: FCLAttachmentType = result.mediaType == .video ? .video : .image

            let attachment = FCLAttachment(
                type: attachmentType,
                url: result.fileURL,
                thumbnailData: thumbnailData,
                fileName: result.fileURL.lastPathComponent,
                fileSize: fileSize
            )
            cameraCaptures.append(attachment)
        }
        if !cameraCaptures.isEmpty {
            state = .gallerySelected
        }
    }

    func removeCameraCapture(_ id: UUID) {
        cameraCaptures.removeAll { $0.id == id }
        // Drop any edit state keyed by this capture's UUID string so a
        // re-captured asset does not inherit stale edits.
        editedImageByAssetID.removeValue(forKey: id.uuidString)
        if cameraCaptures.isEmpty && selectedAssets.isEmpty {
            state = .browsing
            clearEditState()
        }
    }

    func sendCameraAttachments() {
        state = .sending
        let caption = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = cameraCaptures
        for attachment in all {
            Task { await FCLRecentFilesStore.shared.add(fileURL: attachment.url, fileName: attachment.fileName, fileSize: attachment.fileSize) }
        }
        onSend(all, caption.isEmpty ? nil : caption)
        // Defer the `cameraCaptures` emptying to the next runloop
        // turn. Emitting an empty `@Published` value synchronously here
        // would propagate to the still-mounted preview/stack views
        // before the host finishes its dismiss animation, causing a
        // visible flash where the stack thumbnail collapses to nothing
        // mid-transition. Posting onto the main queue runs the wipe
        // after SwiftUI has committed the dismiss transaction.
        DispatchQueue.main.async { [weak self] in
            self?.cameraCaptures.removeAll()
            self?.clearEditState()
        }
    }

    func clearCameraCaptures() {
        cameraCaptures.removeAll()
        clearEditState()
    }

    func handleError(_ message: String) {
        state = .error(message)
    }

    func dismissError() {
        state = selectedAssets.isEmpty ? .browsing : .gallerySelected
    }

    // MARK: - Edit State

    func setEditedImage(_ image: UIImage, for assetID: String) {
        editedImageByAssetID[assetID] = image
    }

    func editedImage(for assetID: String) -> UIImage? {
        editedImageByAssetID[assetID]
    }

    var compressionConfig: FCLMediaCompression {
        delegate?.mediaCompression ?? FCLAttachmentDefaults.mediaCompression
    }

    var isVideoEnabled: Bool {
        delegate?.isVideoEnabled ?? FCLAttachmentDefaults.isVideoEnabled
    }
}
#endif
