#if canImport(UIKit)
import AVFoundation
import Photos
import SwiftUI

// MARK: - FCLAttachmentPickerSheet

/// The root sheet view for the attachment picker.
///
/// `FCLAttachmentPickerSheet` presents a half/full-height sheet containing a tab-based
/// attachment picker. The bottom bar switches between:
/// - ``FCLPickerTabBar`` when the state is `.browsing` or `.sending` / `.error`
/// - ``FCLPickerInputBar`` when the state is `.gallerySelected`
///
/// The bottom bar transition is animated with an ease-in-out curve.
struct FCLAttachmentPickerSheet: View {
    /// The presenter that drives picker state, selected assets, and caption text.
    @ObservedObject var presenter: FCLAttachmentPickerPresenter

    /// The data source that provides photo library assets and thumbnails.
    @ObservedObject var galleryDataSource: FCLGalleryDataSource

    /// The attachment delegate supplying tab configuration, custom tabs, and compression settings.
    let delegate: (any FCLAttachmentDelegate)?

    /// Callback invoked when the sheet should be dismissed (e.g. after send or cancel).
    let onDismiss: () -> Void

    /// Callback invoked when the user requests a camera capture from the gallery tab.
    let onCameraCapture: () -> Void

    /// Callback invoked when the user taps a gallery asset thumbnail.
    let onAssetTap: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabContentArea
            bottomBar
        }
        .background(Color(UIColor.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Tab Content Area

    @ViewBuilder
    private var tabContentArea: some View {
        switch presenter.selectedTab {
        case .gallery:
            FCLGalleryTabView(
                presenter: presenter,
                galleryDataSource: galleryDataSource,
                onCameraCapture: onCameraCapture,
                onAssetTap: onAssetTap
            )

        case .file:
            FCLFileTabView(
                recentFiles: delegate?.recentFiles ?? FCLAttachmentDefaults.recentFiles,
                onSendFile: { attachment in
                    presenter.sendFileAttachment(attachment)
                    onDismiss()
                }
            )

        case .custom(let id):
            customTabContent(id: id)
        }
    }

    // MARK: - Custom Tab Content

    @ViewBuilder
    private func customTabContent(id: String) -> some View {
        let customTabs = delegate?.customTabs ?? []
        let matchingTab = customTabs.enumerated().first { index, t in
            "custom-\(t.tabTitle)-\(index)" == "custom-\(id)"
        }
        if let (_, tab) = matchingTab {
            FCLCustomTabWrapper(
                tab: tab,
                onSelect: { attachment in
                    presenter.sendFileAttachment(attachment)
                    onDismiss()
                }
            )
        } else {
            Text("Unknown Tab")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        let showInputBar = presenter.state == .gallerySelected

        VStack(spacing: 0) {
            Divider()

            if showInputBar {
                FCLPickerInputBar(
                    captionText: $presenter.captionText,
                    hasSelection: !presenter.selectedAssets.isEmpty,
                    fieldBackgroundColor: Color(UIColor.tertiarySystemFill),
                    fieldCornerRadius: 18,
                    onSend: { compressAndSendGallery() }
                )
            } else {
                FCLPickerTabBar(
                    tabs: buildTabDisplayItems(),
                    selectedTab: presenter.selectedTab,
                    isEnabled: presenter.state != .gallerySelected,
                    onTabSelected: { presenter.selectTab($0) }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: presenter.state)
    }

    // MARK: - Compress & Send Gallery

    private func compressAndSendGallery() {
        let selectedIDs = presenter.selectedAssets
        let config = presenter.compressionConfig

        presenter.beginSending()

        Task { @MainActor in
            do {
                var attachments: [FCLAttachment] = []

                for assetID in selectedIDs {
                    let fetchResult = PHAsset.fetchAssets(
                        withLocalIdentifiers: [assetID],
                        options: nil
                    )
                    guard let asset = fetchResult.firstObject else { continue }

                    if asset.mediaType == .video {
                        let url = try await loadAndExportVideo(
                            for: asset,
                            preset: config.videoExportPreset
                        )
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
                        attachments.append(FCLAttachment(
                            type: .video,
                            url: url,
                            fileName: url.lastPathComponent,
                            fileSize: fileSize
                        ))
                    } else {
                        let image = try await galleryDataSource.fullSizeImage(for: asset)
                        let url = try FCLMediaCompressor.compressImageToTempFile(image, config: config)
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
                        attachments.append(FCLAttachment(
                            type: .image,
                            url: url,
                            fileName: url.lastPathComponent,
                            fileSize: fileSize
                        ))
                    }
                }

                presenter.sendGalleryAttachments(attachments)
                onDismiss()
            } catch {
                presenter.handleError(error.localizedDescription)
            }
        }
    }

    // MARK: - Load & Export Video

    /// Loads the `AVAsset` for a `PHAsset` and exports it in one step, returning only the
    /// resulting temp file URL (which is `Sendable`). This avoids sending a non-`Sendable`
    /// `AVAsset` across isolation boundaries.
    private func loadAndExportVideo(
        for phAsset: PHAsset,
        preset: FCLVideoExportPreset
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(
                forVideo: phAsset,
                options: options
            ) { avAsset, _, _ in
                guard let avAsset else {
                    continuation.resume(
                        throwing: FCLCompressionError.exportSessionCreationFailed
                    )
                    return
                }
                // Export on the current (non-isolated) thread to avoid sending AVAsset.
                Task {
                    do {
                        let url = try await FCLMediaCompressor.exportVideo(
                            asset: avAsset,
                            preset: preset
                        )
                        continuation.resume(returning: url)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Builds the ordered list of ``FCLPickerTabDisplayItem`` values from the presenter's available tabs.
    private func buildTabDisplayItems() -> [FCLPickerTabDisplayItem] {
        let customTabs = delegate?.customTabs ?? []

        return presenter.availableTabs.map { tab in
            switch tab {
            case .gallery:
                return FCLPickerTabDisplayItem(
                    tab: .gallery,
                    icon: .system("photo.on.rectangle"),
                    title: "Gallery"
                )
            case .file:
                return FCLPickerTabDisplayItem(
                    tab: .file,
                    icon: .system("folder"),
                    title: "Files"
                )
            case .custom(let id):
                // Match the custom tab by reconstructing the id the presenter uses.
                let matchingTab = customTabs.enumerated().first { index, t in
                    "custom-\(t.tabTitle)-\(index)" == "custom-\(id)"
                }
                let icon = matchingTab.map { _, t in t.tabIcon } ?? FCLImageSource.system("square.grid.2x2")
                let title = matchingTab.map { _, t in t.tabTitle } ?? id
                return FCLPickerTabDisplayItem(tab: tab, icon: icon, title: title)
            }
        }
    }
}

// MARK: - FCLCustomTabWrapper

/// A `UIViewControllerRepresentable` that hosts a custom tab's view controller
/// provided by the host app via ``FCLCustomAttachmentTab``.
private struct FCLCustomTabWrapper: UIViewControllerRepresentable {
    let tab: any FCLCustomAttachmentTab
    let onSelect: @MainActor (FCLAttachment) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        tab.makeViewController(onSelect: onSelect)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - Previews

#if DEBUG
struct FCLAttachmentPickerSheet_Previews: PreviewProvider {
    static var previews: some View {
        FCLAttachmentPickerSheetPreviewWrapper(simulateGallerySelected: false)
            .previewDisplayName("Browsing State")

        FCLAttachmentPickerSheetPreviewWrapper(simulateGallerySelected: true)
            .previewDisplayName("Gallery Selected State")
    }
}

private struct FCLAttachmentPickerSheetPreviewWrapper: View {
    let simulateGallerySelected: Bool

    @StateObject private var presenter = FCLAttachmentPickerPresenter(
        delegate: nil,
        onSend: { _, _ in }
    )
    @StateObject private var galleryDataSource = FCLGalleryDataSource(isVideoEnabled: true)

    var body: some View {
        Color(UIColor.systemBackground)
            .sheet(isPresented: .constant(true)) {
                FCLAttachmentPickerSheet(
                    presenter: presenter,
                    galleryDataSource: galleryDataSource,
                    delegate: nil,
                    onDismiss: {},
                    onCameraCapture: {},
                    onAssetTap: { _ in }
                )
            }
            .onAppear {
                if simulateGallerySelected {
                    presenter.toggleAssetSelection("preview-asset-1")
                }
            }
    }
}
#endif
#endif
