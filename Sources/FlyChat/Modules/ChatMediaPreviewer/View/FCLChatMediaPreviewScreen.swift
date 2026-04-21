#if canImport(UIKit)
import Photos
import SwiftUI
import UIKit

// MARK: - Collection Safe Subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - FCLTransparentFullScreenCover

/// Presents `content` over the current view as a transparent full-screen overlay.
/// Unlike `.fullScreenCover`, the backing hosting controller has a clear background,
/// so the underlying chat remains visible during drag-to-dismiss.
///
/// Tracks a single owned hosting controller per coordinator to avoid accidentally
/// dismissing unrelated modals (e.g., sheets from ancestor views) on re-evaluation.
struct FCLTransparentFullScreenCover<CoverContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    /// When `false`, UIKit's default 0.3s cross-dissolve is skipped so call sites
    /// that supply their own SwiftUI transition are not affected. Defaults to `false`;
    /// pass `animated: true` to restore the UIKit fade where no SwiftUI transition exists.
    var animated: Bool = false
    let content: () -> CoverContent

    final class Coordinator {
        weak var ownedHost: UIViewController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let ownedHost = context.coordinator.ownedHost
        if isPresented {
            if let ownedHost, ownedHost.presentingViewController != nil {
                (ownedHost as? UIHostingController<CoverContent>)?.rootView = content()
                return
            }
            guard uiViewController.presentedViewController == nil else { return }
            let host = UIHostingController(rootView: content())
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .crossDissolve
            context.coordinator.ownedHost = host
            uiViewController.present(host, animated: animated)
        } else {
            guard let ownedHost, ownedHost.presentingViewController != nil else { return }
            ownedHost.dismiss(animated: animated)
            context.coordinator.ownedHost = nil
        }
    }
}

extension View {
    func fclTransparentFullScreenCover<CoverContent: View>(
        isPresented: Binding<Bool>,
        animated: Bool = false,
        @ViewBuilder content: @escaping () -> CoverContent
    ) -> some View {
        background(
            FCLTransparentFullScreenCover(
                isPresented: isPresented,
                animated: animated,
                content: content
            )
            .frame(width: 0, height: 0)
        )
    }
}

// MARK: - FCLPageOffsetPreference

/// Per-page x-origin in the TabView coordinate space; the parent derives `pageProgress` from the collection.
private struct FCLPageOffsetPreference: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - PagerProgressModel

/// Holds the live fractional page index so per-frame swipe updates only invalidate
/// the bottom carousel, not the entire `FCLChatMediaPreviewScreen` body.
@MainActor
final class FCLPagerProgressModel: ObservableObject {
    @Published var pageProgress: CGFloat = 0
}

// MARK: - FCLChatMediaPreviewScreen

/// Full-screen media previewer with swipe paging, drag-to-dismiss, chrome toggling,
/// and a message-scoped bottom thumbnail carousel.
struct FCLChatMediaPreviewScreen: View {
    let presenter: any FCLChatMediaPreviewSourceDelegate
    let initialAttachmentID: UUID
    let namespace: Namespace.ID
    let onDismiss: () -> Void
    /// Optional source queried during dismiss to zoom back to the originating cell. When the
    /// source is `nil` or returns `nil` for the current asset, the preview collapses at the
    /// center of the screen instead. Set by the chat screen; defaults to `nil` so existing
    /// presentation paths keep working until wired up.
    weak var source: (any FCLMediaPreviewSource)? = nil

    /// Window-space frame of the source cell at the moment the previewer was opened;
    /// drives the zoom-in present-phase overlay. `nil` when the cell was not visible.
    var sourceFrame: CGRect? = nil

    @State private var currentIndex: Int = 0
    @StateObject private var progressModel = FCLPagerProgressModel()
    @State private var chromeVisible: Bool = true
    /// Black scrim opacity over the transparent UIKit host. Animates to `0` on dismiss.
    @State private var backgroundOpacity: Double = 0.55
    @State private var carouselSelectedID: UUID = UUID()
    /// Non-nil while the zoom-back dismiss animation is running; hides the pager and
    /// drives the shrinking snapshot overlay.
    @State private var dismissTargetFrame: CGRect?
    @State private var dismissSnapshot: UIImage?
    @State private var dismissCollapsed: Bool = false
    @State private var lastContainerGlobalFrame: CGRect = .zero
    @State private var lastSafeAreaInsets: EdgeInsets = .init()

    // MARK: - Present-phase overlay state

    @State private var presentSnapshot: UIImage?
    @State private var presentSourceRect: CGRect?
    @State private var presentFitRect: CGRect?
    /// `true` while the zoom-in present-phase overlay is active and the real pager is hidden.
    @State private var presentPhaseActive: Bool = false
    /// Drives the present-phase animation: `false` = overlay at source rect; `true` = at fit rect.
    @State private var presentAnimated: Bool = false

    // MARK: - Computed helpers

    private var allMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)] {
        presenter.allConversationMedia
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { containerGeo in
            let pageWidth = containerGeo.size.width
            let containerGlobalFrame = containerGeo.frame(in: .global)
            let safeAreaTop = containerGeo.safeAreaInsets.top

            ZStack {
                Color.black.opacity(backgroundOpacity)
                    .ignoresSafeArea()

                if allMedia.isEmpty {
                    ProgressView()
                        .tint(.white)
                } else {
                    pagerAndOverlay(
                        pageWidth: pageWidth,
                        containerGlobalFrame: containerGlobalFrame,
                        safeAreaTop: safeAreaTop
                    )
                    .opacity(presentPhaseActive ? 0 : 1)

                    if presentPhaseActive, let snapshot = presentSnapshot {
                        presentOverlay(
                            snapshot: snapshot,
                            containerGlobalFrame: containerGlobalFrame
                        )
                    }
                }

                // Cache container frame and safe-area into state via onAppear/onChange
                // so dismiss and present paths can compute rects without UIScreen.main.bounds.
                Color.clear
                    .onAppear {
                        lastContainerGlobalFrame = containerGlobalFrame
                        lastSafeAreaInsets = containerGeo.safeAreaInsets
                    }
                    .onChange(of: containerGlobalFrame) { _, newValue in
                        lastContainerGlobalFrame = newValue
                    }
                    .onChange(of: containerGeo.safeAreaInsets) { _, newValue in
                        lastSafeAreaInsets = newValue
                    }

                VStack(spacing: 0) {
                    HStack {
                        FCLGlassIconButton(
                            systemImage: "xmark",
                            size: 40,
                            action: beginDismiss
                        )
                        .accessibilityLabel(Text("Close"))
                        .padding(.leading, 12)
                        .padding(.top, 12)

                        Spacer()
                    }

                    Spacer()
                    bottomCarousel
                }
                .opacity((chromeVisible && dismissTargetFrame == nil) ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: chromeVisible)
                // Second animation modifier required: without it SwiftUI only watches
                // `chromeVisible`, so chrome pops abruptly when `dismissTargetFrame` flips.
                .animation(.easeInOut(duration: 0.2), value: dismissTargetFrame != nil)
                .allowsHitTesting(dismissTargetFrame == nil)
            }
            .onChange(of: currentIndex) { _, newIndex in
                if let id = allMedia[safe: newIndex]?.attachment.id {
                    carouselSelectedID = id
                }
            }
            .onChange(of: carouselSelectedID) { _, newID in
                if let idx = allMedia.firstIndex(where: { $0.attachment.id == newID }),
                   idx != currentIndex {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentIndex = idx
                    }
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            resolveInitialIndex()
            beginPresentPhase()
        }
    }

    // MARK: - Pager + Dismiss Overlay

    /// Renders either the live pager or the dismiss-animation snapshot overlay;
    /// only one branch is active at a time.
    @ViewBuilder
    private func pagerAndOverlay(
        pageWidth: CGFloat,
        containerGlobalFrame: CGRect,
        safeAreaTop: CGFloat
    ) -> some View {
        if dismissTargetFrame == nil {
            livePager(pageWidth: pageWidth, safeAreaTop: safeAreaTop)
        } else if let snapshot = dismissSnapshot,
                  let target = dismissTargetFrame {
            dismissOverlay(
                snapshot: snapshot,
                target: target,
                containerGlobalFrame: containerGlobalFrame
            )
        }
    }

    @ViewBuilder
    private func livePager(pageWidth: CGFloat, safeAreaTop: CGFloat) -> some View {
        ZStack {
            TabView(selection: $currentIndex) {
                        ForEach(Array(allMedia.enumerated()), id: \.element.attachment.id) { index, item in
                            FCLMediaPreviewPage(
                                attachment: item.attachment,
                                namespace: namespace,
                                isCurrentPage: index == currentIndex,
                                safeAreaInsets: lastSafeAreaInsets
                            )
                            .background(
                                GeometryReader { pageGeo in
                                    let minX = pageGeo.frame(in: .named("fclPagerSpace")).minX
                                    Color.clear
                                        .preference(
                                            key: FCLPageOffsetPreference.self,
                                            value: [index: minX]
                                        )
                                }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .coordinateSpace(.named("fclPagerSpace"))
                    .onPreferenceChange(FCLPageOffsetPreference.self) { offsets in
                        guard pageWidth > 0 else { return }
                        if let (index, minX) = offsets.min(by: { abs($0.value) < abs($1.value) }) {
                            let scrollX = CGFloat(index) * pageWidth - minX
                            let progress = scrollX / pageWidth
                            progressModel.pageProgress = progress
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            chromeVisible.toggle()
                        }
                    }
        }
    }

    // MARK: - Present-Phase Overlay

    /// Zoom-in overlay: animates from the source cell's window-space frame to the
    /// asset's aspect-fit destination, then crossfades away as the real pager becomes visible.
    @ViewBuilder
    private func presentOverlay(
        snapshot: UIImage,
        containerGlobalFrame: CGRect
    ) -> some View {
        let sourceRect = presentSourceRect ?? CGRect(
            x: containerGlobalFrame.midX,
            y: containerGlobalFrame.midY,
            width: 0,
            height: 0
        )
        let fitRect = presentFitRect ?? CGRect(
            origin: .zero,
            size: containerGlobalFrame.size
        )
        let currentRect = presentAnimated ? fitRect : sourceRect
        let cornerRadius: CGFloat = presentAnimated ? 0 : 12
        let overlayAlpha: Double = presentAnimated ? 0 : 1

        Image(uiImage: snapshot)
            .resizable()
            .scaledToFill()
            .frame(
                width: max(1, currentRect.width),
                height: max(1, currentRect.height)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .position(x: currentRect.midX, y: currentRect.midY)
            .opacity(overlayAlpha)
            .allowsHitTesting(false)
    }

    // MARK: - Dismiss Overlay

    /// Shrinking snapshot overlay that zooms back to the source cell (or collapses to center
    /// when the source is offscreen). Finalizes via `completionCriteria: .logicallyComplete`.
    @ViewBuilder
    private func dismissOverlay(
        snapshot: UIImage,
        target: CGRect,
        containerGlobalFrame: CGRect
    ) -> some View {
        let aspect = snapshot.size.height > 0
            ? snapshot.size.width / snapshot.size.height
            : 1
        let startRect = fclMediaPreviewAspectFit(
            aspectRatio: aspect,
            in: safeAreaBounds(containerSize: containerGlobalFrame.size)
        )
        let localTarget = CGRect(
            x: target.minX - containerGlobalFrame.minX,
            y: target.minY - containerGlobalFrame.minY,
            width: target.width,
            height: target.height
        )
        let currentRect = dismissCollapsed ? localTarget : startRect
        let cornerRadius: CGFloat = dismissCollapsed ? 12 : 0
        let alpha: Double = dismissCollapsed ? 0 : 1

        Image(uiImage: snapshot)
            .resizable()
            .scaledToFill()
            .frame(width: max(1, currentRect.width), height: max(1, currentRect.height))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .position(x: currentRect.midX, y: currentRect.midY)
            .opacity(alpha)
            .allowsHitTesting(false)
    }

    // MARK: - Present-Phase Coordination

    /// Starts the zoom-in present animation when a source cell frame and thumbnail are available.
    /// Defers the spring trigger one runloop cycle so SwiftUI commits the initial layout
    /// at `presentSourceRect` before animating away from it.
    private func beginPresentPhase() {
        guard let frame = sourceFrame,
              let current = allMedia.first(where: { $0.attachment.id == initialAttachmentID }),
              let thumbData = current.attachment.thumbnailData,
              let snapshot = UIImage(data: thumbData) else {
            return
        }

        let aspectRatio = snapshot.size.height > 0
            ? snapshot.size.width / snapshot.size.height
            : 1

        let containerSize = lastContainerGlobalFrame.size
        let safeBounds = safeAreaBounds(containerSize: containerSize)
        let fitRect = fclMediaPreviewAspectFit(aspectRatio: aspectRatio, in: safeBounds)

        let localSource = CGRect(
            x: frame.minX - lastContainerGlobalFrame.minX,
            y: frame.minY - lastContainerGlobalFrame.minY,
            width: frame.width,
            height: frame.height
        )

        presentSnapshot = snapshot
        presentSourceRect = localSource
        presentFitRect = fitRect
        presentPhaseActive = true
        presentAnimated = false

        DispatchQueue.main.async {
            withAnimation(
                .spring(response: 0.38, dampingFraction: 1.0),
                completionCriteria: .logicallyComplete
            ) {
                presentAnimated = true
            } completion: {
                presentPhaseActive = false
                presentSnapshot = nil
            }
        }
    }

    // MARK: - Dismiss Coordination

    /// Starts a source-aware dismiss animation. Reads the source cell frame at dismiss-time
    /// (not present-time), preferring the delegate protocol with a fallback to `FCLMediaPreviewSource`.
    /// Visible cell: critically-damped spring (response 0.38). Off-screen: easeIn over 0.28 s.
    private func beginDismiss() {
        guard dismissTargetFrame == nil else { return }

        guard let current = allMedia[safe: currentIndex] else {
            onDismiss()
            return
        }

        let currentID = current.attachment.id
        let sourceFrame: CGRect? =
            presenter.currentFrame(forItemID: currentID)
            ?? source?.mediaPreviewFrame(forAssetID: currentID.uuidString)

        let isOffScreen = sourceFrame == nil
        let target = sourceFrame ?? centerCollapseRect(containerGlobalFrame: lastContainerGlobalFrame)

        dismissSnapshot = currentPageImage() ?? onePixelImage()
        dismissTargetFrame = target

        let animation: Animation = isOffScreen
            ? .easeIn(duration: 0.28)
            : .spring(response: 0.38, dampingFraction: 1.0)

        withAnimation(
            animation,
            completionCriteria: .logicallyComplete
        ) {
            dismissCollapsed = true
            backgroundOpacity = 0
        } completion: {
            onDismiss()
        }
    }

    /// Returns a zero-size rect at the container's center used when the source cell is offscreen.
    /// Uses the measured container frame rather than `UIScreen.main.bounds` to correctly handle
    /// multi-window iPad layouts and embedding chrome.
    private func centerCollapseRect(containerGlobalFrame: CGRect) -> CGRect {
        return CGRect(x: containerGlobalFrame.midX, y: containerGlobalFrame.midY, width: 0, height: 0)
    }

    private func currentPageImage() -> UIImage? {
        guard let current = allMedia[safe: currentIndex] else { return nil }
        if let data = current.attachment.thumbnailData, let image = UIImage(data: data) {
            return image
        }
        if let image = UIImage(contentsOfFile: current.attachment.url.path) {
            return image
        }
        return nil
    }

    private func onePixelImage() -> UIImage {
        let size = CGSize(width: 1, height: 1)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        UIColor.clear.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }

    // MARK: - Safe-Area Bounds

    /// Returns the safe-area-reduced bounds rectangle used as the aspect-fit container.
    /// - Parameter containerSize: The full size of the overlay container before safe-area insets.
    private func safeAreaBounds(containerSize: CGSize) -> CGRect {
        let insets = lastSafeAreaInsets
        return CGRect(
            x: insets.leading,
            y: insets.top,
            width: max(1, containerSize.width - insets.leading - insets.trailing),
            height: max(1, containerSize.height - insets.top - insets.bottom)
        )
    }

    // MARK: - Bottom Carousel

    @ViewBuilder
    private var bottomCarousel: some View {
        if let currentMessageID = allMedia[safe: currentIndex]?.messageID {
            let messageMedia = allMedia.filter { $0.messageID == currentMessageID }
            FCLBottomCarouselContainer(
                allMedia: allMedia,
                messageMedia: messageMedia,
                selectedAttachmentID: $carouselSelectedID,
                progressModel: progressModel
            )
            .padding(.bottom, FCLChatPreviewerLayout.carouselBottomSpacing(safeArea: lastSafeAreaInsets))
        }
    }

    /// Translates the global `pageProgress` into an index local to `messageMedia`.
    /// Returns a `CGFloat` in `[0, messageMedia.count - 1]`.
    fileprivate static func localPageProgress(
        global: CGFloat,
        allMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)],
        messageMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)],
        carouselSelectedID: UUID
    ) -> CGFloat {
        guard !messageMedia.isEmpty else { return 0 }
        let clampedGlobal = max(0, min(global, CGFloat(allMedia.count - 1)))
        let floorIndex = Int(clampedGlobal)
        let frac = clampedGlobal - CGFloat(floorIndex)

        func localIdx(forGlobalIndex gi: Int) -> CGFloat? {
            guard let attachment = allMedia[safe: gi]?.attachment else { return nil }
            guard let local = messageMedia.firstIndex(where: { $0.attachment.id == attachment.id })
            else { return nil }
            return CGFloat(local)
        }

        let localFloor = localIdx(forGlobalIndex: floorIndex)
        let localCeil = localIdx(forGlobalIndex: min(floorIndex + 1, allMedia.count - 1))

        switch (localFloor, localCeil) {
        case let (f?, c?):
            return f + (c - f) * frac
        case let (f?, nil):
            return f
        case let (nil, c?):
            return c
        default:
            let fallback = messageMedia.firstIndex(where: { $0.attachment.id == carouselSelectedID })
            return CGFloat(fallback ?? 0)
        }
    }

    // MARK: - Private

    private func resolveInitialIndex() {
        if let index = allMedia.firstIndex(where: { $0.attachment.id == initialAttachmentID }) {
            currentIndex = index
            progressModel.pageProgress = CGFloat(index)
            carouselSelectedID = initialAttachmentID
        }
    }
}

// MARK: - Backward Compatibility Typealias

/// Transitional alias for call sites that still reference the previous view type name.
/// Deprecated: use `FCLChatMediaPreviewScreen` directly.
internal typealias FCLMediaPreviewView = FCLChatMediaPreviewScreen

// MARK: - FCLBottomCarouselContainer

/// Isolated observer of `FCLPagerProgressModel`; confines per-frame swipe invalidation
/// to the carousel alone, keeping `FCLChatMediaPreviewScreen` body out of the update loop.
private struct FCLBottomCarouselContainer: View {
    let allMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]
    let messageMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]
    @Binding var selectedAttachmentID: UUID
    @ObservedObject var progressModel: FCLPagerProgressModel

    var body: some View {
        let localProgress = FCLChatMediaPreviewScreen.localPageProgress(
            global: progressModel.pageProgress,
            allMedia: allMedia,
            messageMedia: messageMedia,
            carouselSelectedID: selectedAttachmentID
        )
        FCLChatPreviewerCarouselStrip(
            items: messageMedia,
            selectedItemID: $selectedAttachmentID,
            pageProgress: localProgress
        )
        .coordinateSpace(.named("fclCarouselSpace"))
        .padding(.horizontal, 12)
    }
}

// MARK: - FCLMediaPreviewPage

/// A single pager page rendering one media attachment at aspect-fit size.
/// Shows the thumbnail immediately; crossfades the full-res image once loaded.
/// `matchedGeometryEffect` uses `isSource: false` but cannot animate across the
/// UIKit boundary — zoom-in is driven by the present-phase overlay instead.
private struct FCLMediaPreviewPage: View {
    let attachment: FCLAttachment
    let namespace: Namespace.ID
    let isCurrentPage: Bool
    let safeAreaInsets: EdgeInsets

    @State private var loadedImage: UIImage?
    @State private var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let fitSize = resolvedFitSize(containerSize: containerSize)

            ZStack {
                if let data = attachment.thumbnailData, let thumb = UIImage(data: data) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fitSize.width, height: fitSize.height)
                        .matchedGeometryEffect(id: attachment.id, in: namespace, isSource: false)
                }

                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fitSize.width, height: fitSize.height)
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }

                if loadedImage == nil,
                   attachment.thumbnailData == nil || UIImage(data: attachment.thumbnailData ?? Data()) == nil {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
        }
        .onAppear { loadFullImage() }
    }

    // MARK: - Aspect-Fit Sizing

    /// Returns the aspect-fit size for the attachment inside `containerSize` respecting safe-area insets.
    /// Uses actual image dimensions when known; falls back to the thumbnail's aspect ratio to prevent
    /// layout jumps before full-res arrives.
    private func resolvedFitSize(containerSize: CGSize) -> CGSize {
        let safeBounds = CGRect(
            x: safeAreaInsets.leading,
            y: safeAreaInsets.top,
            width: max(1, containerSize.width - safeAreaInsets.leading - safeAreaInsets.trailing),
            height: max(1, containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom)
        )

        let aspectRatio: CGFloat
        if imageSize.height > 0 {
            aspectRatio = imageSize.width / imageSize.height
        } else if let data = attachment.thumbnailData,
                  let thumb = UIImage(data: data),
                  thumb.size.height > 0 {
            aspectRatio = thumb.size.width / thumb.size.height
        } else {
            return safeBounds.size
        }

        let fitRect = fclMediaPreviewAspectFit(aspectRatio: aspectRatio, in: safeBounds)
        return fitRect.size
    }

    // MARK: - Image Loading

    /// Loads the full-resolution image for this attachment on a `userInitiated` task
    /// and updates `imageSize` so the aspect-fit computation can use real dimensions.
    private func loadFullImage() {
        guard attachment.type == .image || attachment.type == .video else { return }
        let url = attachment.url
        Task(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                loadedImage = image
                imageSize = image.size
            }
        }
    }
}


// MARK: - Previews

#if DEBUG
// MARK: Preview Helpers

@MainActor
private func fclPreviewImageData(
    width: Int,
    height: Int,
    color: UIColor = .systemBlue
) -> Data? {
    let size = CGSize(width: width, height: height)
    UIGraphicsBeginImageContextWithOptions(size, true, 1)
    defer { UIGraphicsEndImageContext() }
    color.setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    return UIGraphicsGetImageFromCurrentImageContext()?.jpegData(compressionQuality: 0.8)
}

@MainActor
private func fclPreviewAttachment(
    name: String,
    width: Int,
    height: Int,
    color: UIColor = .systemBlue
) -> FCLAttachment {
    let data = fclPreviewImageData(width: width, height: height, color: color)
    return FCLAttachment(
        id: UUID(),
        type: .image,
        url: URL(string: "https://example.com/\(name).jpg")!,
        thumbnailData: data,
        fileName: "\(name).jpg",
        fileSize: nil
    )
}

@MainActor
private final class FCLPreviewDataSourceStub: FCLChatMediaPreviewSourceDelegate {
    var allConversationMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]

    init(attachments: [FCLAttachment] = []) {
        let msgID = UUID()
        self.allConversationMedia = attachments.enumerated().map { idx, att in
            (messageID: msgID, attachmentIndex: idx, attachment: att)
        }
    }
}

// MARK: Preview Wrappers

private struct FCLPreviewWrapperPortraitPhoto: View {
    @Namespace var ns

    var body: some View {
        let attachment = fclPreviewAttachment(name: "portrait", width: 1080, height: 1920, color: .systemIndigo)
        let stub = FCLPreviewDataSourceStub(attachments: [attachment])
        FCLMediaPreviewView(
            presenter: stub,
            initialAttachmentID: attachment.id,
            namespace: ns,
            onDismiss: {}
        )
        .background(Color.black)
    }
}

private struct FCLPreviewWrapperLandscapePhoto: View {
    @Namespace var ns

    var body: some View {
        let attachment = fclPreviewAttachment(name: "landscape", width: 3024, height: 1440, color: .systemTeal)
        let stub = FCLPreviewDataSourceStub(attachments: [attachment])
        FCLMediaPreviewView(
            presenter: stub,
            initialAttachmentID: attachment.id,
            namespace: ns,
            onDismiss: {}
        )
        .background(Color.black)
    }
}

private struct FCLPreviewWrapperVerticalVideo: View {
    @Namespace var ns

    var body: some View {
        let data = fclPreviewImageData(width: 1080, height: 1920, color: .systemOrange)
        let attachment = FCLAttachment(
            id: UUID(),
            type: .video,
            url: URL(string: "https://example.com/vertical.mp4")!,
            thumbnailData: data,
            fileName: "vertical.mp4",
            fileSize: nil
        )
        let stub = FCLPreviewDataSourceStub(attachments: [attachment])
        FCLMediaPreviewView(
            presenter: stub,
            initialAttachmentID: attachment.id,
            namespace: ns,
            onDismiss: {}
        )
        .background(Color.black)
    }
}

private struct FCLPreviewWrapperEmpty: View {
    @Namespace var ns

    var body: some View {
        let stub = FCLPreviewDataSourceStub(attachments: [])
        FCLMediaPreviewView(
            presenter: stub,
            initialAttachmentID: UUID(),
            namespace: ns,
            onDismiss: {}
        )
        .background(Color.black)
    }
}

private struct FCLPreviewWrapperOffScreenCollapse: View {
    @Namespace var ns

    var body: some View {
        let attachment = fclPreviewAttachment(name: "offscreen", width: 1080, height: 1080, color: .systemPurple)
        let stub = FCLPreviewDataSourceStub(attachments: [attachment])
        FCLMediaPreviewView(
            presenter: stub,
            initialAttachmentID: attachment.id,
            namespace: ns,
            onDismiss: {}
        )
        .background(Color.black)
    }
}

// MARK: - FCLChatPreviewerLayout

/// Shared layout constants for the chat media previewer chrome.
enum FCLChatPreviewerLayout {
    /// Clearance in points between the carousel strip's top edge and the bottom safe-area boundary.
    /// Must stay in sync with `FCLChatPreviewerCarouselStrip.stripHeight`; desynchronising
    /// the two shifts the strip's top-edge anchor.
    static let carouselBaseSpacing: CGFloat = 88

    static let stripVisibleHeight: CGFloat = 72

    /// Returns the bottom padding that places the carousel strip's top edge exactly
    /// `carouselBaseSpacing` above the bottom safe-area boundary.
    /// - Parameter safeArea: Container safe-area insets from the enclosing `GeometryReader`.
    static func carouselBottomSpacing(safeArea: EdgeInsets) -> CGFloat {
        safeArea.bottom + (carouselBaseSpacing - stripVisibleHeight)
    }
}

struct FCLChatMediaPreviewScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FCLPreviewWrapperPortraitPhoto()
                .previewDisplayName("Portrait Photo (1080x1920)")
            FCLPreviewWrapperLandscapePhoto()
                .previewDisplayName("Landscape Photo (3024x1440)")
            FCLPreviewWrapperVerticalVideo()
                .previewDisplayName("Vertical Video (1080x1920)")
            FCLPreviewWrapperEmpty()
                .previewDisplayName("Empty — No Media")
            FCLPreviewWrapperOffScreenCollapse()
                .previewDisplayName("Off-Screen Collapse — easeIn 0.28 s")
        }
    }
}
#endif
#endif
