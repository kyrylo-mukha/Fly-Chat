#if canImport(UIKit)
import AVFoundation
import Photos
import SwiftUI
import UIKit

// MARK: - FCLPickerModal

/// Drives the single unified `fullScreenCover` on ``FCLAttachmentPickerSheet``.
private enum FCLPickerModal: Identifiable {
    case cameraFlow
    case assetPreview(String)

    var id: String {
        switch self {
        case .cameraFlow: return "cameraFlow"
        case .assetPreview(let assetID): return "assetPreview-\(assetID)"
        }
    }
}

// MARK: - FCLAttachmentPickerSheet

/// Root sheet view for the attachment picker, containing a tab-based picker with a
/// dynamic bottom bar that switches between the tab bar and the caption input bar.
struct FCLAttachmentPickerSheet: View {
    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @ObservedObject var galleryDataSource: FCLGalleryDataSource
    let delegate: (any FCLAttachmentDelegate)?
    let onDismiss: () -> Void

    @State private var modal: FCLPickerModal?

    @FocusState private var isCaptionFocused: Bool

    /// Whether the camera bridge (`FCLCameraRouterBridge`) layer is visible.
    /// Both `showCamera` and `showPreviewer` can be `true` simultaneously during
    /// the cross-dissolve window — that is the literal cross-fade between layers.
    @State private var showCamera: Bool = false
    /// Whether the pre-send attachment previewer layer is visible.
    @State private var showPreviewer: Bool = false

    @StateObject private var cameraSourceRelay = FCLCameraSourceRelay()
    @State private var isSendInFlight: Bool = false

    @StateObject private var authCoordinator = FCLPhotoAuthorizationCoordinator()
    @StateObject private var collectionRegistry = FCLAssetCollectionRegistry()

    private var galleryAuthorizationStatus: PHAuthorizationStatus { authCoordinator.status }

    private var galleryAssetCount: Int { galleryDataSource.assets.count }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSendDisabled: Bool {
        isSendInFlight || presenter.state == .sending
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(FCLPalette.tertiaryLabel)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)

            tabContentZStack
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        FCLPickerTopToolbar(
                            presenter: presenter,
                            collectionRegistry: collectionRegistry
                        )
                        FCLPickerPermissionSurface(
                            status: galleryAuthorizationStatus,
                            selectedCount: presenter.selectedAssets.count,
                            totalCount: galleryAssetCount,
                            isPresentationComplete: presenter.isPresentationComplete
                        )
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                }
        }
        .background(FCLPalette.systemGroupedBackground)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                presenter.markPresentationComplete()
            }
        }
        .onDisappear {
            presenter.clearEditState()
        }
        .fullScreenCover(item: $modal) { currentModal in
            switch currentModal {
            case .cameraFlow:
                ZStack {
                    if showCamera {
                        FCLCameraRouterBridge(
                            configuration: makeCameraConfiguration(),
                            cameraSourceRelay: cameraSourceRelay,
                            onFinish: { results in
                                presenter.appendCameraResults(results)
                                withAnimation(.easeInOut(
                                    duration: FCLCameraTransitionCurves.crossDissolveDuration
                                )) {
                                    showPreviewer = true
                                    showCamera = false
                                }
                            },
                            onCancel: {
                                if presenter.cameraCaptures.isEmpty {
                                    showCamera = false
                                    showPreviewer = false
                                    modal = nil
                                } else {
                                    withAnimation(.easeInOut(
                                        duration: FCLCameraTransitionCurves.crossDissolveDuration
                                    )) {
                                        showPreviewer = true
                                        showCamera = false
                                    }
                                }
                            }
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(1)
                    }

                    if showPreviewer {
                        FCLAttachmentPreviewScreen(
                            presenter: presenter,
                            captionText: $presenter.captionText,
                            attachments: presenter.cameraCaptures,
                            showsAddMore: true,
                            chatMaxLines: 6,
                            inputDelegate: nil,
                            onSend: {
                                performSynchronizedSend {
                                    presenter.sendCameraAttachments()
                                }
                            },
                            onCancel: {
                                presenter.clearCameraCaptures()
                                showPreviewer = false
                                showCamera = false
                                modal = nil
                            },
                            onAddMore: {
                                withAnimation(.easeInOut(
                                    duration: FCLCameraTransitionCurves.crossDissolveDuration
                                )) {
                                    showCamera = true
                                    showPreviewer = false
                                }
                            },
                            onRotateCrop: {},
                            onMarkup: {}
                        )
                        .transition(.opacity)
                        .zIndex(2)
                    }
                }
            case .assetPreview(let assetID):
                FCLPickerAssetPreview(
                    presenter: presenter,
                    galleryDataSource: galleryDataSource,
                    initialAssetID: assetID,
                    onSend: {
                        performSynchronizedSend {
                            compressAndSendGallery()
                        }
                    },
                    onDismiss: { self.modal = nil }
                )
            }
        }
    }

    // MARK: - Tab Content ZStack

    @ViewBuilder
    private var tabContentZStack: some View {
        let transition = delegate?.tabTransition ?? FCLAttachmentDefaults.tabTransition
        let tabs = presenter.availableTabs
        let selectedIndex = tabs.firstIndex(of: presenter.selectedTab) ?? 0

        GeometryReader { geo in
            ZStack {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    tabView(for: tab)
                        .offset(x: offsetFor(
                            index: index,
                            selectedIndex: selectedIndex,
                            width: geo.size.width,
                            transition: transition
                        ))
                        .opacity(opacityFor(
                            index: index,
                            selectedIndex: selectedIndex,
                            transition: transition
                        ))
                        .allowsHitTesting(index == selectedIndex)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(tabAnimation(for: transition), value: selectedIndex)
        }
    }

    private func offsetFor(
        index: Int,
        selectedIndex: Int,
        width: CGFloat,
        transition: FCLPickerTabTransition
    ) -> CGFloat {
        guard transition == .slide else { return 0 }
        return CGFloat(index - selectedIndex) * width
    }

    private func opacityFor(
        index: Int,
        selectedIndex: Int,
        transition: FCLPickerTabTransition
    ) -> Double {
        guard transition == .crossfade else { return 1 }
        return index == selectedIndex ? 1 : 0
    }

    private func tabAnimation(for transition: FCLPickerTabTransition) -> Animation {
        if reduceMotion { return .linear(duration: 0.12) }
        switch transition {
        case .slide: return .spring(response: 0.32, dampingFraction: 0.85)
        case .crossfade: return .easeInOut(duration: 0.28)
        }
    }

    @ViewBuilder
    private func tabView(for tab: FCLPickerTab) -> some View {
        switch tab {
        case .gallery:
            FCLGalleryTabView(
                authCoordinator: authCoordinator,
                collectionRegistry: collectionRegistry,
                presenter: presenter,
                galleryDataSource: galleryDataSource,
                onCameraCapture: {
                    if AVCaptureDevice.default(for: .video) != nil {
                        showCamera = true
                        showPreviewer = false
                        modal = .cameraFlow
                    }
                },
                onAssetTap: { assetID in
                    modal = .assetPreview(assetID)
                },
                cameraSourceRelay: cameraSourceRelay
            )
        case .file:
            FCLFileTabView(
                presenter: presenter,
                delegateRecentFiles: delegate?.recentFiles ?? FCLAttachmentDefaults.recentFiles,
                onSendFile: { attachment in
                    performSynchronizedSend {
                        presenter.sendFileAttachment(attachment)
                    }
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
                    performSynchronizedSend {
                        presenter.sendFileAttachment(attachment)
                    }
                }
            )
        } else {
            Text("Unknown Tab")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(FCLPalette.secondaryLabel)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        let showInputBar = presenter.state == .gallerySelected || presenter.state == .sending
        if showInputBar {
            FCLPickerInputBar(
                captionText: $presenter.captionText,
                hasSelection: !presenter.selectedAssets.isEmpty && !isSendDisabled,
                fieldBackgroundColor: FCLPalette.tertiarySystemFill,
                fieldCornerRadius: 22,
                captionFocusBinding: $isCaptionFocused,
                onSend: {
                    performSynchronizedSend {
                        compressAndSendGallery()
                    }
                }
            )
            .padding(.bottom, 10)
        } else {
            FCLPickerTabBar(
                tabs: buildTabDisplayItems(),
                selectedTab: presenter.selectedTab,
                isEnabled: presenter.state != .gallerySelected,
                onTabSelected: { presenter.selectTab($0) }
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Synchronized Send Dismiss

    /// Dismisses the keyboard, invokes the send action, and collapses all modal layers
    /// in a single synchronized animation. Guards against reentrancy from rapid double-taps.
    private func performSynchronizedSend(_ action: () -> Void) {
        guard !isSendInFlight else { return }
        isSendInFlight = true
        isCaptionFocused = false
        action()
        withAnimation(.easeOut(duration: 0.22)) {
            modal = nil
            showCamera = false
            showPreviewer = false
            onDismiss()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSendInFlight = false
        }
    }

    // MARK: - Compress & Send Gallery

    private func compressAndSendGallery() {
        let selectedIDs = presenter.selectedAssets
        let config = presenter.compressionConfig

        presenter.beginSending()

        #if DEBUG
        let preSendEditKeys = Set(presenter.editedImageByAssetID.keys)
        var consumedEditKeys: Set<String> = []
        #endif

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
                        let url = try await exportVideo(
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
                            #if DEBUG
                            consumedEditKeys.insert(assetID)
                            #endif
                        } else {
                            image = try await galleryDataSource.fullSizeImage(for: asset)
                        }
                        let url = try FCLMediaCompressor.compressImageToTempFile(image, config: config)
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
                        let attachment = FCLAttachment(
                            type: .image,
                            url: url,
                            fileName: url.lastPathComponent,
                            fileSize: fileSize
                        )
                        attachments.append(attachment)
                    }
                }

                #if DEBUG
                let unconsumed = preSendEditKeys.subtracting(consumedEditKeys)
                if !unconsumed.isEmpty {
                    assertionFailure(
                        "FCLAttachmentPickerSheet.compressAndSendGallery: \(unconsumed.count) edit(s) were not consumed by the send path. Unconsumed keys: \(unconsumed). This usually indicates a key-space mismatch between the preview's write key and the send path's read key."
                    )
                }
                #endif

                presenter.sendGalleryAttachments(attachments)
            } catch {
                presenter.reportSendError(error.localizedDescription)
            }
        }
    }

    // MARK: - Export Video

    /// Exports a gallery video `PHAsset` to a temporary MP4 using PhotoKit's
    /// `requestExportSession`. The session stays on PhotoKit's queue for its full lifetime
    /// to avoid cross-queue `AVAsset` access that caused `_dispatch_assert_queue_fail`.
    private func exportVideo(
        for phAsset: PHAsset,
        preset: FCLVideoExportPreset
    ) async throws -> URL {
        let presetName = FCLMediaCompressor.avPreset(for: preset)
        let fileName = "fcl_\(UUID().uuidString.prefix(8)).mp4"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestExportSession(
                forVideo: phAsset,
                options: options,
                exportPreset: presetName
            ) { session, info in
                guard let session else {
                    let underlying = (info?[PHImageErrorKey] as? Error)?.localizedDescription
                    continuation.resume(
                        throwing: FCLCompressionError.videoExportFailed(
                            underlying ?? "Failed to create export session"
                        )
                    )
                    return
                }
                session.outputURL = outputURL
                session.outputFileType = .mp4
                // `exportAsynchronously` completion is `@Sendable` on iOS 18+; box the
                // session so a single-owner reference crosses the boundary safely.
                let box = FCLUncheckedBox(session)
                session.exportAsynchronously {
                    switch box.value.status {
                    case .completed:
                        continuation.resume(returning: outputURL)
                    case .cancelled:
                        continuation.resume(
                            throwing: FCLCompressionError.videoExportFailed("Export cancelled")
                        )
                    default:
                        continuation.resume(
                            throwing: FCLCompressionError.videoExportFailed(
                                box.value.error?.localizedDescription ?? "Unknown error"
                            )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Camera Configuration

    private func makeCameraConfiguration() -> FCLCameraConfiguration {
        let allowsVideo = delegate?.isCameraVideoEnabled ?? FCLAttachmentDefaults.isCameraVideoEnabled
        let maxCaptures = max(1, 10 - presenter.cameraCaptures.count)
        return FCLCameraConfiguration(
            allowsVideo: allowsVideo,
            maxAssets: maxCaptures,
            defaultMode: .photo,
            defaultFlash: .auto,
            maxVideoDuration: 60
        )
    }

    // MARK: - Helpers

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

// MARK: - FCLCameraRouterBridge

/// A transparent `UIViewControllerRepresentable` that presents the FlyChat camera
/// module via `FCLCameraRouter`. Defers presentation until `viewDidAppear` so the
/// hosting controller is in the window hierarchy before `present(_:animated:)` is called.
private struct FCLCameraRouterBridge: UIViewControllerRepresentable {
    let configuration: FCLCameraConfiguration
    let cameraSourceRelay: FCLCameraSourceRelay
    let onFinish: ([FCLCameraCaptureResult]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            configuration: configuration,
            cameraSourceRelay: cameraSourceRelay,
            onFinish: onFinish,
            onCancel: onCancel
        )
    }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.containerViewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // MARK: Coordinator

    @MainActor
    final class Coordinator {
        let containerViewController: UIViewController
        private var router: FCLCameraRouter?
        private var didPresent = false

        init(
            configuration: FCLCameraConfiguration,
            cameraSourceRelay: FCLCameraSourceRelay,
            onFinish: @escaping ([FCLCameraCaptureResult]) -> Void,
            onCancel: @escaping () -> Void
        ) {
            let vc = PresentationContainerViewController()
            containerViewController = vc

            let router = FCLCameraRouter(
                configuration: configuration,
                onFinish: { results in
                    onFinish(results)
                },
                onCancel: {
                    onCancel()
                },
                sourceRelay: cameraSourceRelay
            )
            self.router = router
            vc.onViewDidAppear = { [weak self, weak vc] in
                guard let self, let vc, !self.didPresent else { return }
                self.didPresent = true
                self.router?.present(from: vc)
            }
        }
    }

    // MARK: - PresentationContainerViewController

    /// Transparent UIKit presenter anchor for `FCLCameraRouter`.
    private final class PresentationContainerViewController: UIViewController {
        var onViewDidAppear: (() -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onViewDidAppear?()
        }
    }
}

// MARK: - FCLCameraStackPreview

/// Full-screen preview of accumulated camera captures with single-image and paged layouts.
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

            VStack {
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

            TabView {
                ForEach(presenter.cameraCaptures) { attachment in
                    FCLCapturePageView(attachment: attachment)
                        .tag(attachment.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }

                    Spacer()

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
        FCLAttachmentPickerSheet(
            presenter: presenter,
            galleryDataSource: galleryDataSource,
            delegate: nil,
            onDismiss: {}
        )
            .onAppear {
                if simulateGallerySelected {
                    presenter.toggleAssetSelection("preview-asset-1")
                }
            }
    }
}
#endif
#endif
