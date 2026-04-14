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

    // MARK: - Per-asset edit state

    @Published private(set) var editStateByAssetID: [String: FCLMediaEditState] = [:]
    @Published private(set) var editedImageByAssetID: [String: UIImage] = [:]

    private let delegate: (any FCLAttachmentDelegate)?
    private let onSend: @MainActor ([FCLAttachment], String?) -> Void

    init(
        delegate: (any FCLAttachmentDelegate)?,
        onSend: @escaping @MainActor ([FCLAttachment], String?) -> Void
    ) {
        self.delegate = delegate
        self.onSend = onSend
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

    func toggleAssetSelection(_ assetID: String) {
        if let index = selectedAssets.firstIndex(of: assetID) {
            selectedAssets.remove(at: index)
        } else {
            selectedAssets.append(assetID)
        }
        state = selectedAssets.isEmpty ? .browsing : .gallerySelected
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
    }

    func appendCameraCapture(_ attachment: FCLAttachment) {
        cameraCaptures.append(attachment)
        state = .gallerySelected
    }

    func removeCameraCapture(_ id: UUID) {
        cameraCaptures.removeAll { $0.id == id }
        if cameraCaptures.isEmpty && selectedAssets.isEmpty {
            state = .browsing
        }
    }

    func sendCameraAttachments() {
        state = .sending
        let caption = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = cameraCaptures
        cameraCaptures.removeAll()
        for attachment in all {
            Task { await FCLRecentFilesStore.shared.add(fileURL: attachment.url, fileName: attachment.fileName, fileSize: attachment.fileSize) }
        }
        onSend(all, caption.isEmpty ? nil : caption)
    }

    func clearCameraCaptures() {
        cameraCaptures.removeAll()
    }

    func handleError(_ message: String) {
        state = .error(message)
    }

    func dismissError() {
        state = selectedAssets.isEmpty ? .browsing : .gallerySelected
    }

    // MARK: - Edit State

    func setEditState(_ state: FCLMediaEditState, for assetID: String) {
        editStateByAssetID[assetID] = state
    }

    func setEditedImage(_ image: UIImage, for assetID: String) {
        editedImageByAssetID[assetID] = image
    }

    func editState(for assetID: String) -> FCLMediaEditState {
        editStateByAssetID[assetID] ?? FCLMediaEditState()
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
