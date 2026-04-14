#if canImport(UIKit)
import AVFoundation
import Photos
import SwiftUI

// MARK: - FCLPickerModal

/// Drives the single unified `fullScreenCover` on ``FCLAttachmentPickerSheet``.
private enum FCLPickerModal: Identifiable {
    case camera
    case cameraStack
    case assetPreview(String)

    var id: String {
        switch self {
        case .camera: return "camera"
        case .cameraStack: return "cameraStack"
        case .assetPreview(let assetID): return "assetPreview-\(assetID)"
        }
    }
}

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

    @State private var modal: FCLPickerModal?

    var body: some View {
        VStack(spacing: 0) {
            tabContentArea
            bottomBar
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $modal) { currentModal in
            switch currentModal {
            case .camera:
                FCLCameraBridge(
                    isVideoEnabled: delegate?.isCameraVideoEnabled ?? FCLAttachmentDefaults.isCameraVideoEnabled,
                    onCapture: { attachment in
                        let wasEmpty = presenter.cameraCaptures.isEmpty
                        presenter.appendCameraCapture(attachment)
                        // Single capture from an empty stack goes directly to cameraStack
                        // (FCLCameraStackPreview renders a single-item layout in that case).
                        // Subsequent captures also go to cameraStack (multi-item paged layout).
                        _ = wasEmpty  // routing is always .cameraStack; variable retained for clarity
                        self.modal = .cameraStack
                    },
                    onCancel: {
                        if presenter.cameraCaptures.isEmpty {
                            self.modal = nil
                        } else {
                            self.modal = .cameraStack
                        }
                    }
                )
                .ignoresSafeArea()
            case .cameraStack:
                FCLCameraStackPreview(
                    presenter: presenter,
                    captionText: $presenter.captionText,
                    onAddMore: { self.modal = .camera },
                    onSend: {
                        presenter.sendCameraAttachments()
                        onDismiss()
                    },
                    onCancel: {
                        presenter.clearCameraCaptures()
                        self.modal = nil
                    }
                )
            case .assetPreview(let assetID):
                FCLPickerAssetPreview(
                    presenter: presenter,
                    galleryDataSource: galleryDataSource,
                    initialAssetID: assetID,
                    onSend: {
                        compressAndSendGallery()
                        self.modal = nil
                    },
                    onDismiss: { self.modal = nil }
                )
            }
        }
    }

    // MARK: - Tab Content Area

    @ViewBuilder
    private var tabContentArea: some View {
        switch presenter.selectedTab {
        case .gallery:
            FCLGalleryTabView(
                presenter: presenter,
                galleryDataSource: galleryDataSource,
                onCameraCapture: {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        modal = .camera
                    }
                },
                onAssetTap: { assetID in
                    modal = .assetPreview(assetID)
                }
            )

        case .file:
            FCLFileTabView(
                delegateRecentFiles: delegate?.recentFiles ?? FCLAttachmentDefaults.recentFiles,
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
                .foregroundColor(Color(.secondaryLabel))
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
                    fieldBackgroundColor: Color(.tertiarySystemFill),
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
                        let image: UIImage
                        if let edited = presenter.editedImage(for: assetID) {
                            image = edited
                        } else {
                            image = try await galleryDataSource.fullSizeImage(for: asset)
                        }
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
                // Safety: avAsset is used only within the Task below and never
                // accessed concurrently. nonisolated(unsafe) avoids sending a
                // non-Sendable AVAsset across isolation boundaries.
                nonisolated(unsafe) let asset = avAsset
                Task {
                    do {
                        let url = try await FCLMediaCompressor.exportVideo(
                            asset: asset,
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

// MARK: - FCLCameraStackPreview

/// A full-screen preview showing camera captures accumulated so far.
///
/// When a single capture is present the view renders a clean single-image layout
/// (full-screen image, caption field bottom-leading, send button bottom-trailing,
/// close button top-trailing, add-more `+` button top-leading) to match the
/// picker asset preview experience. When two or more captures are present the
/// view renders the paged layout with a count badge and an "Add another" button.
private struct FCLCameraStackPreview: View {
    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @Binding var captionText: String

    let onAddMore: () -> Void
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if presenter.cameraCaptures.count == 1 {
            singleCaptureView
        } else {
            multiCaptureView
        }
    }

    // MARK: - Single Capture Layout

    private var singleCaptureView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let capture = presenter.cameraCaptures.first {
                FCLCapturePageView(attachment: capture)
                    .ignoresSafeArea()
            }

            // Overlay controls
            VStack {
                // Top bar: close (trailing), add-more (leading)
                HStack {
                    Button(action: onAddMore) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }

                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)

                Spacer()

                // Bottom: caption (leading) + send button (trailing)
                HStack(spacing: 12) {
                    TextField("Add a caption…", text: $captionText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)
                        .tint(.white)

                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Multi-Capture Layout

    private var multiCaptureView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Paged media viewer
            TabView {
                ForEach(presenter.cameraCaptures) { attachment in
                    FCLCapturePageView(attachment: attachment)
                        .tag(attachment.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Overlay controls
            VStack {
                // Top bar
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }

                    Spacer()

                    // Capture count badge
                    if presenter.cameraCaptures.count > 0 {
                        Text("\(presenter.cameraCaptures.count)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)

                Spacer()

                // Bottom: caption + send + add-more
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        TextField("Add a caption…", text: $captionText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(.white)
                            .tint(.white)

                        Button(action: onSend) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                    }

                    Button(action: onAddMore) {
                        Label("Add another", systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - FCLCapturePageView

/// Displays a single captured photo or video thumbnail inside `FCLCameraStackPreview`.
private struct FCLCapturePageView: View {
    let attachment: FCLAttachment

    var body: some View {
        if let image = attachment.thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let imageData = attachment.type == .image ? (try? Data(contentsOf: attachment.url)) : nil,
                  let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Video or image without thumbnail: show icon placeholder
            ZStack {
                Color.black
                VStack(spacing: 8) {
                    Image(systemName: attachment.type == .video ? "video.fill" : "photo.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(attachment.fileName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
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
struct FCLCameraStackPreview_Previews: PreviewProvider {
    static var previews: some View {
        FCLCameraStackSinglePreviewWrapper()
            .previewDisplayName("Camera Stack — 1 capture (single layout)")

        FCLCameraStackMultiPreviewWrapper()
            .previewDisplayName("Camera Stack — 2 captures (paged layout)")
    }
}

@MainActor
private struct FCLCameraStackSinglePreviewWrapper: View {
    @StateObject private var presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }

    var body: some View {
        FCLCameraStackPreview(
            presenter: presenter,
            captionText: $presenter.captionText,
            onAddMore: {},
            onSend: {},
            onCancel: {}
        )
        .onAppear {
            presenter.appendCameraCapture(FCLAttachment(
                type: .image,
                url: URL(string: "file:///tmp/cam_a.jpg")!,
                fileName: "cam_a.jpg"
            ))
        }
    }
}

@MainActor
private struct FCLCameraStackMultiPreviewWrapper: View {
    @StateObject private var presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }

    var body: some View {
        FCLCameraStackPreview(
            presenter: presenter,
            captionText: $presenter.captionText,
            onAddMore: {},
            onSend: {},
            onCancel: {}
        )
        .onAppear {
            presenter.appendCameraCapture(FCLAttachment(
                type: .image,
                url: URL(string: "file:///tmp/cam_a.jpg")!,
                fileName: "cam_a.jpg"
            ))
            presenter.appendCameraCapture(FCLAttachment(
                type: .video,
                url: URL(string: "file:///tmp/cam_b.mov")!,
                fileName: "cam_b.mov"
            ))
        }
    }
}

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
        Color(.systemBackground)
            .sheet(isPresented: .constant(true)) {
                FCLAttachmentPickerSheet(
                    presenter: presenter,
                    galleryDataSource: galleryDataSource,
                    delegate: nil,
                    onDismiss: {}
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
