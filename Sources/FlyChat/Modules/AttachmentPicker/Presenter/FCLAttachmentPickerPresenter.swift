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

    /// Whether the Files-tab search morph is open.
    @Published private(set) var fileSearchState: FileSearchState = .closed

    /// Query text bound when the search morph is open.
    @Published var fileSearchText: String = ""

    /// `true` after the sheet presentation animation has finished.
    /// Authorization requests and asset fetches wait for this flag.
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

    /// Routes a post-dismiss send error to the host and updates local state.
    func reportSendError(_ message: String) {
        onSendError?(message)
        state = .error(message)
    }

    /// Clears all per-asset edit bitmaps.
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

    /// Opens the Files-tab search morph.
    func beginFileSearch() {
        fileSearchState = .open
    }

    /// Closes the Files-tab search morph and clears the query text.
    func cancelFileSearch() {
        fileSearchState = .closed
        fileSearchText = ""
    }

    /// Signals that the sheet presentation animation has finished. Idempotent.
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

    /// Converts camera capture results into `FCLAttachment` values and appends them.
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
        editedImageByAssetID.removeValue(forKey: id.uuidString) // prevent stale edits on re-capture
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
        // Defer the wipe so SwiftUI commits the dismiss transaction before the
        // camera-captures array empties, preventing a mid-transition thumbnail flash.
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
