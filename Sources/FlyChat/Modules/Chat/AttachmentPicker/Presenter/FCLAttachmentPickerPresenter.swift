#if canImport(UIKit)
import Combine
import Foundation
import Photos

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
    @Published var captionText: String = ""

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
        onSend([attachment], nil)
    }

    func sendGalleryAttachments(_ attachments: [FCLAttachment]) {
        state = .sending
        let caption = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSend(attachments, caption.isEmpty ? nil : caption)
    }

    func handleError(_ message: String) {
        state = .error(message)
    }

    func dismissError() {
        state = selectedAssets.isEmpty ? .browsing : .gallerySelected
    }

    var compressionConfig: FCLMediaCompression {
        delegate?.mediaCompression ?? FCLAttachmentDefaults.mediaCompression
    }

    var isVideoEnabled: Bool {
        delegate?.isVideoEnabled ?? FCLAttachmentDefaults.isVideoEnabled
    }
}
#endif
