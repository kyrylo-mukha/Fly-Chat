#if canImport(UIKit)
import AVFoundation
import Photos
import SwiftUI
import UIKit

// MARK: - FCLPickerModal

/// Drives the single unified `fullScreenCover` on ``FCLAttachmentPickerSheet``.
///
/// `.cameraFlow` replaces the former separate `.camera` and `.cameraStack` cases.
/// Both camera and pre-send previewer render inside a single cover via a ZStack,
/// enabling a literal SwiftUI cross-dissolve (both views on-screen simultaneously)
/// rather than a UIKit cover-swap pair.
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

/// The root sheet view for the attachment picker.
///
/// `FCLAttachmentPickerSheet` presents a half/full-height sheet containing a tab-based
/// attachment picker. The bottom bar switches between:
/// - ``FCLPickerTabBar`` when the state is `.browsing` or `.sending` / `.error`
/// - ``FCLPickerInputBar`` when the state is `.gallerySelected`
///
/// The bottom bar transition is animated with an ease-in-out curve.
///
/// A ``FCLPickerCloseButton`` lives inside ``FCLPickerTopToolbar``'s leading slot
/// and dismisses the sheet through SwiftUI's `DismissAction`, routing through the
/// same path used by swipe-down and tap-outside.
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

    /// Focus state for the caption text field hosted by ``FCLPickerInputBar``.
    /// Hoisted to the sheet so the synchronized send path can dismiss the
    /// keyboard immediately before invoking the dismiss animation.
    @FocusState private var isCaptionFocused: Bool

    // MARK: Camera-flow ZStack state
    //
    // These two flags drive which layer is visible inside the `.cameraFlow`
    // cover's ZStack. Both can be `true` simultaneously for the 0.25s
    // cross-dissolve window — that is the literal cross-fade: camera fades
    // out while the previewer fades in with both views on-screen at once.
    //
    // Invariant: `showPreviewer` is only `true` while `modal == .cameraFlow`.
    // `showCamera` is `true` for the full duration the cover is open except
    // when the user returns from the previewer to the camera (Add More path),
    // at which point the swap direction reverses.

    /// Whether the camera bridge (`FCLCameraRouterBridge`) layer is visible.
    @State private var showCamera: Bool = false
    /// Whether the pre-send attachment previewer layer is visible.
    @State private var showPreviewer: Bool = false

    /// Scope-08 relay that publishes the gallery camera cell frame to the
    /// ``FCLCameraRouter`` and coordinates the return pulse-highlight. Held
    /// as `@StateObject` so its identity survives body re-evaluations.
    @StateObject private var cameraSourceRelay = FCLCameraSourceRelay()
    /// Reentrancy guard for send taps. A rapid double-tap on any send button
    /// (camera, asset preview, gallery, file, custom tab) would otherwise
    /// invoke ``performSynchronizedSend`` twice — sending an empty payload on
    /// the camera path or duplicating the bubble on the gallery path. The flag
    /// flips to `true` on entry, all send buttons visually disable, and it
    /// auto-resets after the send animation window so subsequent unrelated
    /// sends stay responsive.
    @State private var isSendInFlight: Bool = false

    /// Hoisted from ``FCLGalleryTabView`` so the top toolbar (source pill) and
    /// permission surface share the same identity across tab switches.
    @StateObject private var authCoordinator = FCLPhotoAuthorizationCoordinator()
    /// Hoisted from ``FCLGalleryTabView`` so the top toolbar's collection
    /// selector pill binds to the same registry that scopes the grid.
    @StateObject private var collectionRegistry = FCLAssetCollectionRegistry()

    private var galleryAuthorizationStatus: PHAuthorizationStatus { authCoordinator.status }

    private var galleryAssetCount: Int { galleryDataSource.assets.count }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether any send button is currently disabled. Send buttons are
    /// disabled while a send is in-flight (local guard) or while the presenter
    /// is in the `.sending` state (remote confirmation).
    private var isSendDisabled: Bool {
        isSendInFlight || presenter.state == .sending
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle. The system sheet drives dismissal on downward
            // drags; this capsule is purely a visual affordance.
            Capsule()
                .fill(FCLPalette.tertiaryLabel)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Scrollable gallery / files content fills all remaining space.
            // The top toolbar and bottom bar float over the content via
            // `.safeAreaInset` so the grid cells are never obscured.
            tabContentZStack
                // Permission surface sits between the toolbar and the grid;
                // pin it as a top inset so it does not displace the floating
                // toolbar but does push the grid down when visible.
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        // Transparent top toolbar (close / source / trailing)
                        // floats over the scrollable area — no opaque background.
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
                // Bottom bar (tab bar or caption+send) floats over the grid.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                }
        }
        // Prototype sheet background: #F2F2F7 = systemGroupedBackground.
        .background(FCLPalette.systemGroupedBackground)
        .onAppear {
            // Apple does not provide an "onPresent" / presentation-complete
            // callback on `.sheet`. 0.55s matches typical iOS sheet present
            // animation duration so the permission request and asset fetch
            // run after the sheet is visually in place. See
            // docs/superpowers/knowledge/2026-04-17-picker-chrome-overhaul.md (Q3).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                presenter.markPresentationComplete()
            }
        }
        .onDisappear {
            // Ensure the presenter's per-asset edit dictionaries do not
            // outlive the sheet itself. Any edit still cached at this point
            // belongs to a session the user is walking away from.
            presenter.clearEditState()
        }
        .fullScreenCover(item: $modal) { currentModal in
            switch currentModal {
            case .cameraFlow:
                // Single ZStack that hosts both the camera bridge and the
                // pre-send previewer. Swapping `showCamera`/`showPreviewer`
                // inside a `withAnimation(.easeInOut(duration: 0.25))` block
                // produces a literal cross-dissolve: both layers are on-screen
                // simultaneously while one fades out and the other fades in.
                //
                // The camera bridge (`FCLCameraRouterBridge`) occupies zIndex 1
                // and the previewer occupies zIndex 2. During the dissolve both
                // are visible; after the dissolve only the target layer remains.
                //
                // The open/close morph (cell → camera and camera → cell) is a
                // UIKit custom transition that `FCLCameraRouter` drives entirely
                // within `FCLCameraRouterBridge`. That mechanism is unaffected
                // by the ZStack — the morph targets the UIKit hosting controller
                // that the bridge presents, not the SwiftUI cover itself.
                ZStack {
                    if showCamera {
                        FCLCameraRouterBridge(
                            configuration: makeCameraConfiguration(),
                            cameraSourceRelay: cameraSourceRelay,
                            onFinish: { results in
                                presenter.appendCameraResults(results)
                                // Cross-dissolve: bring previewer in while
                                // camera is still visible, then remove camera.
                                withAnimation(.easeInOut(
                                    duration: FCLCameraTransitionCurves.crossDissolveDuration
                                )) {
                                    showPreviewer = true
                                    showCamera = false
                                }
                            },
                            onCancel: {
                                if presenter.cameraCaptures.isEmpty {
                                    // No captures — collapse the whole cover.
                                    showCamera = false
                                    showPreviewer = false
                                    modal = nil
                                } else {
                                    // Captures exist — cross-dissolve to previewer.
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
                                // Cross-dissolve back to camera from previewer
                                // ("Add More" path). The relay's isTransitioning
                                // flag keeps the AVCaptureSession alive across
                                // the dissolve so the session does not need to
                                // restart — the camera view never left the ZStack
                                // hierarchy when the previewer was on top.
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
                        // Asset preview send: let the synchronized dismiss block
                        // below drive both `modal = nil` (the preview cover) and
                        // `onDismiss()` (the sheet) inside a single ease-out
                        // animation so the preview and sheet collapse together
                        // instead of the preview popping instantly and the sheet
                        // sliding out afterwards.
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

    /// All tab views live in a `ZStack` so switching between them preserves
    /// state (scroll position, loaded thumbnails, search text) and does not
    /// re-fire `.task` side effects. The visible tab is offset to x=0 and all
    /// others are offset by ± the container width; on `.crossfade` the offset
    /// stays 0 and opacity drives visibility instead.
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
        // Keep the input bar visible during `.sending` so the bottom bar does not
        // regress to the tab-bar row between the send tap and the sheet dismiss
        // animation completing (which would cause a visible tab-bar flash).
        let showInputBar = presenter.state == .gallerySelected || presenter.state == .sending

        // No Divider, no opaque background — the bar floats over the grid per
        // the prototype spec (position: absolute, bottom: 10). The glass
        // surfaces on FCLGlassTextField / FCLGlassToolbar provide visual separation.
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

    /// Performs a send action with a single synchronized dismissal animation.
    ///
    /// Steps on the same UI tick:
    /// 1. Resign first responder so the keyboard collapses alongside the sheet.
    /// 2. Invoke `action`, which hands the staged attachments off to the chat
    ///    presenter. The chat presenter defers the actual bubble insert so the
    ///    chat screen becomes visible first.
    /// 3. In one `withAnimation(.easeOut(duration: 0.22))` block, flip any
    ///    intermediate `fullScreenCover` binding (`modal`) off and invoke
    ///    `onDismiss`, collapsing every modal layer in parallel rather than
    ///    chaining preview → sheet → input bar.
    ///
    /// The 0.22s ease-out matches the system sheet dismiss curve closely and
    /// lines up with the 0.24s delay used by
    /// ``FCLChatPresenter/handleAttachmentsDeferred(_:caption:delay:)`` so the
    /// outgoing bubble slides in immediately after the chat is visible.
    private func performSynchronizedSend(_ action: () -> Void) {
        // Reentrancy guard: double-taps on a send button fire the handler
        // twice before SwiftUI re-renders the disabled state. Short-circuit
        // the second invocation so camera sends don't empty-out and gallery
        // sends don't duplicate the bubble.
        guard !isSendInFlight else { return }
        isSendInFlight = true

        // Drop the keyboard synchronously via the hoisted focus state so the
        // composer keyboard collapses in the same visual transaction as the
        // dismiss animation below.
        isCaptionFocused = false

        action()

        withAnimation(.easeOut(duration: 0.22)) {
            modal = nil
            showCamera = false
            showPreviewer = false
            onDismiss()
        }

        // Release the guard after the dismiss animation window. Any send
        // initiated before this point has already been accepted by the
        // presenter; later taps are a fresh interaction.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSendInFlight = false
        }
    }

    // MARK: - Compress & Send Gallery

    private func compressAndSendGallery() {
        let selectedIDs = presenter.selectedAssets
        let config = presenter.compressionConfig

        presenter.beginSending()

        // Snapshot edits up front so we can DEBUG-assert that every edit the
        // preview committed is actually consumed by this send.
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
                // The sheet has already been dismissed by the synchronized
                // send block — route the error through the chat-facing
                // channel instead of the now-gone sheet UI.
                presenter.reportSendError(error.localizedDescription)
            }
        }
    }

    // MARK: - Export Video

    /// Exports a gallery video `PHAsset` to a temporary MP4 file using
    /// `PHImageManager.requestExportSession(forVideo:options:exportPreset:resultHandler:)`.
    ///
    /// PhotoKit returns a pre-configured `AVAssetExportSession` that owns the
    /// underlying `AVAsset` on its own queue. The session is never handed off to
    /// a separate `Task`; every access to the session happens inside either the
    /// PhotoKit result handler or AVFoundation's own `exportAsynchronously`
    /// completion handler. This avoids the cross-queue `AVAsset` access pattern
    /// that tripped `_dispatch_assert_queue_fail` when an asset fetched with
    /// `requestAVAsset` was passed into a detached `AVAssetExportSession` init
    /// on a different executor.
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
                // `exportAsynchronously`'s completion is `@Sendable` on the
                // iOS 18 SDK, so `AVAssetExportSession` (non-`Sendable`) cannot
                // be captured directly. Wrap the session in `FCLUncheckedBox`
                // so only a documented, single-owner reference crosses into the
                // completion. Safe invariant: PhotoKit owns this session on its
                // own queue, AVFoundation schedules the completion on its
                // internal queue, and no FlyChat-side code touches the session
                // concurrently from anywhere else.
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

    /// Builds an ``FCLCameraConfiguration`` from the current delegate and presenter state.
    ///
    /// - `allowsVideo` maps from `delegate?.isCameraVideoEnabled`.
    /// - `maxAssets` is set to the number of remaining slots available (no existing camera
    ///   captures plus no upper limit when not specified — defaults to a generous maximum).
    private func makeCameraConfiguration() -> FCLCameraConfiguration {
        let allowsVideo = delegate?.isCameraVideoEnabled ?? FCLAttachmentDefaults.isCameraVideoEnabled
        // Remaining slots: allow any additional captures (no hard cap from the delegate yet,
        // so use a generous default of 10 minus how many are already staged).
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

// MARK: - FCLCameraRouterBridge

/// A transparent `UIViewControllerRepresentable` that triggers the full-screen
/// FlyChat camera module via ``FCLCameraRouter``.
///
/// The bridge presents the camera on top of its own hosting `UIViewController`.
/// Using `UIViewControllerRepresentable` lets SwiftUI manage the hosting
/// container while `FCLCameraRouter` handles the `AVCaptureSession`-based UI.
///
/// Presentation is deferred until `viewDidAppear` so the hosting controller is
/// fully embedded in the window hierarchy before `present(_:animated:completion:)`
/// is called (required by UIKit — see `UIViewController.present(_:animated:completion:)`).
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

            // Capture as weak inside the router closures to avoid a retain cycle.
            // The router itself is held strongly by the coordinator for the duration
            // of the camera session.
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

    /// A lightweight, transparent view controller used solely as the UIKit
    /// presenter anchor. Its view is invisible; all presentation happens via
    /// `FCLCameraRouter` on top of it.
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
