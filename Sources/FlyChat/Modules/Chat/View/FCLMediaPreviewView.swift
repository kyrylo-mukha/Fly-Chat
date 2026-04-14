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
/// The helper tracks a single hosting controller it owns via the coordinator. It only
/// dismisses that specific controller; it never touches unrelated `presentedViewController`
/// modals (e.g., sheets presented from ancestors), which previously caused accidental
/// dismissal of the attachment picker sheet when this helper re-evaluated.
struct FCLTransparentFullScreenCover<CoverContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    /// When `false`, the underlying UIKit `present(_:animated:)` and
    /// matching `dismiss(animated:)` calls run without UIKit's default
    /// 0.3s cross-dissolve. Use this from call sites that drive their own
    /// SwiftUI transition (e.g. a custom matched-geometry zoom) so the
    /// UIKit fade does not chain on top and produce a 600ms perceived
    /// dismiss. Defaults to `false` because every existing call site in
    /// the package supplies its own transition; opt back in with
    /// `animated: true` if a callsite ever needs the UIKit fade.
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
            // Already presenting our own host — update its rootView and bail out.
            if let ownedHost, ownedHost.presentingViewController != nil {
                (ownedHost as? UIHostingController<CoverContent>)?.rootView = content()
                return
            }
            // Do not compete with an unrelated modal on the same anchor; wait for next update.
            guard uiViewController.presentedViewController == nil else { return }
            let host = UIHostingController(rootView: content())
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .crossDissolve
            context.coordinator.ownedHost = host
            uiViewController.present(host, animated: animated)
        } else {
            // Dismiss ONLY the host we own. Never touch unrelated presented view controllers.
            guard let ownedHost, ownedHost.presentingViewController != nil else { return }
            ownedHost.dismiss(animated: animated)
            context.coordinator.ownedHost = nil
        }
    }
}

extension View {
    /// - Parameter animated: forwarded to the underlying UIKit
    ///   `present`/`dismiss` calls. Defaults to `false` because every call
    ///   site in the package owns its own SwiftUI transition (matched
    ///   geometry, custom zoom, etc.); chaining UIKit's 0.3s cross-dissolve
    ///   on top doubled the perceived duration. Pass `animated: true` to
    ///   restore the UIKit fade if a future call site has no SwiftUI
    ///   transition of its own.
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

/// Carries the x-origin of a single page measured in the TabView's coordinate space.
/// Each page reports its own origin; the parent derives `pageProgress` from the collection.
private struct FCLPageOffsetPreference: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - PagerProgressModel

/// Holds the live fractional `pageProgress` derived from the `TabView` pager's
/// `PreferenceKey` pipeline. Isolating this value into a small `ObservableObject`
/// instead of a `@State` on `FCLMediaPreviewView` prevents the entire preview
/// body from recomputing on every frame of a swipe. Only the bottom carousel —
/// the single subview that actually depends on `pageProgress` — observes it.
@MainActor
final class FCLPagerProgressModel: ObservableObject {
    @Published var pageProgress: CGFloat = 0
}

// MARK: - FCLMediaPreviewView

/// A full-screen media preview that displays all conversation attachments with horizontal swipe
/// navigation, drag-to-dismiss, chrome toggling, and a message-scoped bottom thumbnail carousel.
///
/// `pageProgress` is a `CGFloat` fractional page index derived from the `TabView` pager's
/// live scroll position using a `GeometryReader` / `PreferenceKey` pipeline. It is exposed
/// internally so ``FCLPreviewThumbCarousel`` can apply Photos-like parallax to thumbnails.
struct FCLMediaPreviewView: View {
    let presenter: FCLChatPresenter
    let initialAttachmentID: UUID
    let namespace: Namespace.ID
    let onDismiss: () -> Void
    /// Optional source queried during dismiss to zoom back to the originating cell. When the
    /// source is `nil` or returns `nil` for the current asset, the preview collapses at the
    /// center of the screen instead. Set by the chat screen; defaults to `nil` so existing
    /// presentation paths keep working until wired up.
    weak var source: (any FCLMediaPreviewSource)? = nil

    @State private var currentIndex: Int = 0
    /// Fractional page index in [0, count-1] updated in real time as the `TabView` scrolls.
    /// Integer values mean fully-settled pages; fractional values appear mid-swipe.
    /// Stored on a dedicated `@StateObject` so per-frame writes do not invalidate
    /// the entire `FCLMediaPreviewView` body — only the bottom carousel, which
    /// observes the model directly, re-renders.
    @StateObject private var progressModel = FCLPagerProgressModel()
    @State private var chromeVisible: Bool = true
    @State private var dragOffset: CGSize = .zero
    @State private var backgroundOpacity: Double = 1.0
    /// Carousel selection kept in sync with `currentIndex` and drives `FCLPreviewThumbCarousel`.
    @State private var carouselSelectedID: UUID = UUID()
    /// When non-nil, the preview is running its zoom-back dismiss animation toward this
    /// window-space rectangle. The pager is hidden and a shrinking snapshot overlay
    /// interpolates from the current on-screen content frame to `dismissTargetFrame`.
    /// Once the animation completes the outer `onDismiss` callback is invoked.
    @State private var dismissTargetFrame: CGRect?
    /// Image used by the dismiss-animation overlay. Resolved from the current page's
    /// loaded or thumbnail image at the moment dismiss begins.
    @State private var dismissSnapshot: UIImage?
    /// Controls whether the overlay is rendered at the "collapsed" target frame.
    /// Flipped inside a `withAnimation` block to drive the shrink.
    @State private var dismissCollapsed: Bool = false
    /// Latches `true` as soon as the active drag is judged to be primarily
    /// horizontal so further updates are ignored until the gesture ends. This
    /// prevents the drag-down strip from stealing ownership of a horizontal
    /// swipe that really belongs to the underlying `TabView` pager.
    @State private var dragCancelled: Bool = false
    /// Cached global frame of the preview's outer container, refreshed on
    /// every `GeometryReader` pass. Used by `beginDismiss` to derive the
    /// fall-back center-collapse rect without reaching for
    /// `UIScreen.main.bounds`.
    @State private var lastContainerGlobalFrame: CGRect = .zero

    // MARK: - Computed helpers

    private var allMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)] {
        presenter.allConversationMedia
    }

    private var dragProgress: Double {
        min(abs(dragOffset.height) / 300, 1)
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
                }

                // Mirror the latest global container frame into state so the
                // dismiss path can compute a center-collapse rect
                // without reaching for `UIScreen.main.bounds`. The write is
                // deferred to a microtask to satisfy SwiftUI's "no state
                // mutation during view update" rule.
                Color.clear
                    .onAppear { lastContainerGlobalFrame = containerGlobalFrame }
                    .onChange(of: containerGlobalFrame) { _, newValue in
                        lastContainerGlobalFrame = newValue
                    }

                // Chrome overlay
                VStack(spacing: 0) {
                    // Top chrome: close button
                    HStack {
                        Spacer()
                        Button(action: beginDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(16)
                        }
                    }

                    Spacer()

                    // Bottom chrome: message-scoped thumbnail carousel (centered, with parallax).
                    bottomCarousel
                }
                .opacity((chromeVisible && dismissTargetFrame == nil) ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: chromeVisible)
                // Also animate the opacity collapse driven by
                // `dismissTargetFrame` flipping to non-nil. Without this
                // second `.animation(_:value:)` SwiftUI only watches
                // `chromeVisible` for the implicit transition, so the chrome
                // would pop out abruptly the instant a dismiss begins. The
                // chained modifier keeps the fade smooth across both
                // triggers.
                .animation(.easeInOut(duration: 0.2), value: dismissTargetFrame != nil)
                .allowsHitTesting(dismissTargetFrame == nil)
            }
            // Keep carouselSelectedID in sync whenever the pager settles on a new page.
            .onChange(of: currentIndex) { _, newIndex in
                if let id = allMedia[safe: newIndex]?.attachment.id {
                    carouselSelectedID = id
                }
            }
            // Tapping a carousel thumbnail drives currentIndex from carouselSelectedID.
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
        .onAppear { resolveInitialIndex() }
    }

    // MARK: - Pager + Dismiss Overlay

    /// The pager (`TabView`) plus the top drag strip, plus the dismiss-animation overlay.
    /// Extracted to keep the main `body` readable and to isolate the conditional rendering
    /// between the live pager and the shrinking dismiss snapshot.
    @ViewBuilder
    private func pagerAndOverlay(
        pageWidth: CGFloat,
        containerGlobalFrame: CGRect,
        safeAreaTop: CGFloat
    ) -> some View {
        // Only one of these branches is active at a time, so the outer
        // ZStack added a redundant layer to the hit-test hierarchy. Returning
        // the chosen branch directly flattens by one level while keeping
        // gesture priorities identical (the conditional itself is the only
        // real branching the parent body needs).
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

    /// The scrollable preview pager with its top drag-down-to-dismiss strip.
    @ViewBuilder
    private func livePager(pageWidth: CGFloat, safeAreaTop: CGFloat) -> some View {
        ZStack {
            TabView(selection: $currentIndex) {
                        ForEach(Array(allMedia.enumerated()), id: \.element.attachment.id) { index, item in
                            FCLMediaPreviewPage(
                                attachment: item.attachment,
                                namespace: namespace,
                                isCurrentPage: index == currentIndex
                            )
                            // Measure each page's x-origin in the TabView coordinate space
                            // so we can derive a live fractional pageProgress value.
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
                        // Each page at rest lives at index * pageWidth.
                        // Derive pageProgress from the page whose offset is closest to zero
                        // (i.e. the page currently most visible on screen).
                        // offset for page i = (i * pageWidth) - scrollX
                        // => scrollX = i * pageWidth - offset
                        // => pageProgress = scrollX / pageWidth
                        if let (index, minX) = offsets.min(by: { abs($0.value) < abs($1.value) }) {
                            let scrollX = CGFloat(index) * pageWidth - minX
                            let progress = scrollX / pageWidth
                            progressModel.pageProgress = progress
                        }
                    }
                    .offset(dragOffset)
                    .scaleEffect(1 - dragProgress * 0.15)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            chromeVisible.toggle()
                        }
                    }

                    // Top drag-down strip. Restricted to the top ~80pt so it never competes
                    // with horizontal paging on the TabView or with the bottom thumbnail carousel.
                    // Uses `simultaneousGesture` so the TabView's paging gesture still receives
                    // the touch and wins for horizontal swipes — our handler independently
                    // self-cancels once it detects the motion is primarily horizontal.
                    // Extend the strip below the device's top safe-area
                    // inset by a fixed 80pt window. On Dynamic Island devices,
                    // hardcoding the strip to 80pt total left only ~21pt of
                    // usable touch area below the island; basing it on
                    // `safeAreaTop + 80` restores a uniform 80pt below any
                    // status overlay across notch/island/no-notch layouts.
                    VStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(height: safeAreaTop + 80)
                            .simultaneousGesture(dragDownDismissGesture)
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(true)
        }
    }

    // MARK: - Dismiss Overlay

    /// Renders a shrinking snapshot that animates from the current on-screen content
    /// frame to the source cell's window-space rectangle (or a center point when the
    /// source is offscreen). The shrink is driven by `dismissCollapsed` flipping inside
    /// `withAnimation(_:completionCriteria:_:completion:)` so dismissal finalizes only
    /// after the spring settles.
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
            in: CGRect(origin: .zero, size: containerGlobalFrame.size)
        )
        // Convert the window-space target frame into the container's local space.
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

    // MARK: - Dismiss Coordination

    /// Initiates a source-aware dismiss animation from every entry point (close button,
    /// drag-past-threshold). When the chat screen's ``FCLMediaPreviewSource`` returns a
    /// visible frame for the current asset the preview zooms back into that cell;
    /// otherwise the snapshot collapses to a zero-size point at the screen center.
    private func beginDismiss() {
        guard dismissTargetFrame == nil else { return }

        // Resolve the current asset's source frame in window coordinates.
        guard let current = allMedia[safe: currentIndex] else {
            onDismiss()
            return
        }
        let id = current.attachment.id.uuidString
        let sourceFrame = source?.mediaPreviewFrame(forAssetID: id)
        let target = sourceFrame ?? centerCollapseRect(containerGlobalFrame: lastContainerGlobalFrame)

        // Snapshot the current page's image so the overlay can render it during shrink.
        dismissSnapshot = currentPageImage() ?? onePixelImage()
        dismissTargetFrame = target

        // Drive the shrink via a state toggle so SwiftUI can interpolate frame/alpha/corner.
        // Critical damping (1.0) reaches the target without overshoot while
        // preserving a natural approach duration, matching the deceleration
        // curve of the system Photos dismiss. A lower damping fraction
        // overshoots the target rect and produces a visible bounce as the
        // snapshot settles into the source cell.
        withAnimation(
            .spring(response: 0.38, dampingFraction: 1.0),
            completionCriteria: .logicallyComplete
        ) {
            dismissCollapsed = true
            backgroundOpacity = 0
        } completion: {
            onDismiss()
        }
    }

    /// Returns a zero-size rect at the container's center used when the source cell is offscreen.
    /// Derive the collapse point from the container's measured global
    /// frame (passed in by the body's `GeometryReader`) rather than the
    /// deprecated `UIScreen.main.bounds`. The container frame already accounts
    /// for the active `UIWindowScene`, multi-window iPad layouts, and any
    /// embedding chrome — `UIScreen.main.bounds` ignores all of these.
    private func centerCollapseRect(containerGlobalFrame: CGRect) -> CGRect {
        return CGRect(x: containerGlobalFrame.midX, y: containerGlobalFrame.midY, width: 0, height: 0)
    }

    /// Resolves a displayable `UIImage` for the current page: the edited/loaded image
    /// if available, otherwise the attachment's inline thumbnail data.
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

    /// Fallback 1×1 transparent image used when no snapshot is available.
    private func onePixelImage() -> UIImage {
        let size = CGSize(width: 1, height: 1)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        UIColor.clear.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }

    // MARK: - Drag-Down Dismiss Gesture

    /// Vertical-only drag gesture attached to a thin strip at the top of the preview. Pulls the
    /// preview downward with rubber-banding and dismisses past a velocity/distance threshold.
    /// Because it is attached to a bounded strip it cannot collide with the horizontal paging
    /// gesture on the underlying `TabView` or the horizontal thumbnail carousel.
    private var dragDownDismissGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                // If an earlier sample in this drag was already judged horizontal,
                // ignore the rest of the stream. The latch resets in `.onEnded`.
                if dragCancelled { return }
                // Horizontal motions belong to the TabView pager. As soon as the
                // drag's horizontal component meaningfully outruns its vertical
                // component, latch and stay out of the way for the remainder of
                // this gesture.
                if abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                    dragCancelled = true
                    if dragOffset != .zero || backgroundOpacity != 1.0 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dragOffset = .zero
                            backgroundOpacity = 1.0
                        }
                    }
                    return
                }
                // Only consume downward motion; upward drifts shouldn't shift the page.
                guard value.translation.height > 0 else { return }
                // Rubber-band: soften dragging beyond a reasonable pull.
                let y = rubberBanded(value.translation.height)
                dragOffset = CGSize(width: 0, height: y)
                let progress = min(y / 300, 1)
                backgroundOpacity = 1 - progress
            }
            .onEnded { value in
                defer { dragCancelled = false }
                if dragCancelled {
                    // Ended as a horizontal swipe we yielded to the pager — nothing
                    // to unwind; the state was already restored on cancellation.
                    return
                }
                let distance = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let shouldDismiss = distance > 120 || predicted > 260
                if shouldDismiss {
                    beginDismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragOffset = .zero
                        backgroundOpacity = 1.0
                    }
                }
            }
    }

    /// Applies a simple rubber-band curve to a pull distance so the content resists
    /// unbounded motion during the drag.
    private func rubberBanded(_ distance: CGFloat) -> CGFloat {
        let limit: CGFloat = 600
        let x = max(distance, 0)
        return limit * (1 - 1 / (x / limit + 1))
    }

    // MARK: - Bottom Carousel

    @ViewBuilder
    private var bottomCarousel: some View {
        if let currentMessageID = allMedia[safe: currentIndex]?.messageID {
            let messageMedia = allMedia.filter { $0.messageID == currentMessageID }
            // Hand the live progress model to a dedicated subview so per-frame
            // page-progress updates do not invalidate FCLMediaPreviewView's body.
            FCLBottomCarouselContainer(
                allMedia: allMedia,
                messageMedia: messageMedia,
                selectedAttachmentID: $carouselSelectedID,
                progressModel: progressModel
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
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
        // Map the global page index to the local message-relative index.
        // pageProgress is fractional, so we interpolate between adjacent message items.
        let clampedGlobal = max(0, min(global, CGFloat(allMedia.count - 1)))
        let floorIndex = Int(clampedGlobal)
        let frac = clampedGlobal - CGFloat(floorIndex)

        // Find the local index for the floor and ceil global pages.
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
            // Fall back to integer index of selected item within message media.
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

// MARK: - FCLBottomCarouselContainer

/// Thin observer wrapper around `FCLPreviewThumbCarousel` that subscribes to
/// `FCLPagerProgressModel` and recomputes the local page-progress only inside
/// its own body. Hosting this in a separate `View` confines per-frame
/// invalidation to the carousel during a swipe.
private struct FCLBottomCarouselContainer: View {
    let allMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]
    let messageMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]
    @Binding var selectedAttachmentID: UUID
    @ObservedObject var progressModel: FCLPagerProgressModel

    var body: some View {
        let localProgress = FCLMediaPreviewView.localPageProgress(
            global: progressModel.pageProgress,
            allMedia: allMedia,
            messageMedia: messageMedia,
            carouselSelectedID: selectedAttachmentID
        )
        FCLPreviewThumbCarousel(
            items: messageMedia,
            selectedAttachmentID: $selectedAttachmentID,
            pageProgress: localProgress
        )
    }
}

// MARK: - FCLMediaPreviewPage

private struct FCLMediaPreviewPage: View {
    let attachment: FCLAttachment
    let namespace: Namespace.ID
    let isCurrentPage: Bool

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: attachment.id, in: namespace, isSource: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = attachment.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: attachment.id, in: namespace, isSource: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFullImage() }
    }

    private func loadFullImage() {
        guard attachment.type == .image || attachment.type == .video else { return }
        let url = attachment.url
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                self.loadedImage = image
            }
        }
    }
}

// MARK: - FCLPickerAssetPreview

/// Full-screen preview for gallery assets in the attachment picker. Allows browsing all assets,
/// toggling selection, rotating images, adding a caption, and sending.
struct FCLPickerAssetPreview: View {
    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @ObservedObject var galleryDataSource: FCLGalleryDataSource
    let initialAssetID: String
    let onSend: () -> Void
    let onDismiss: () -> Void

    @State private var currentIndex: Int = 0
    @State private var rotationByID: [String: Int] = [:]
    @FocusState private var captionFocused: Bool
    @State private var isEditorPresented: Bool = false
    @State private var editorSourceImage: UIImage?

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if galleryDataSource.assets.count > 0 {
                TabView(selection: $currentIndex) {
                    ForEach(0 ..< galleryDataSource.assets.count, id: \.self) { index in
                        let asset = galleryDataSource.assets[index]
                        FCLPickerAssetPageView(
                            asset: asset,
                            galleryDataSource: galleryDataSource,
                            rotationSteps: rotationByID[asset.localIdentifier] ?? 0,
                            editedImage: presenter.editedImage(for: asset.localIdentifier)
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Chrome overlay
            VStack(spacing: 0) {
                topChrome
                Spacer()
            }

            // Send button fixed at bottom-trailing
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onSend) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(presenter.selectedAssets.isEmpty ? Color.gray : Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(presenter.selectedAssets.isEmpty)
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomCaptionBar
        }
        .statusBarHidden(true)
        .onAppear { resolveInitialIndex() }
        // Attach as `.simultaneousGesture` so the underlying TabView
        // pager keeps receiving horizontal drag samples. The previous
        // `.gesture(...)` attachment installed a higher-priority recognizer
        // at the ZStack root that intercepted every drag, including the
        // horizontal pan that should reach the pager — making swipe between
        // assets feel sluggish or completely blocked.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    // Light downward swipe while keyboard is open dismisses keyboard only
                    if captionFocused,
                       value.translation.height > 20,
                       value.translation.height < 60,
                       abs(value.velocity.height) < 800 {
                        captionFocused = false
                    }
                }
        )
        .onTapGesture {
            if captionFocused {
                captionFocused = false
            }
        }
        .overlay {
            // In-place editor replacement for the legacy fullScreenCover path.
            // The gallery preview currently exposes only the rotate/crop tool
            // via this entry point; markup routing from the gallery-picker
            // preview is a follow-up.
            if isEditorPresented, let sourceImage = editorSourceImage, let assetID = currentAssetID {
                FCLRotateCropEditor(
                    original: sourceImage,
                    onCommit: { edited in
                        presenter.setEditedImage(edited, for: assetID)
                        isEditorPresented = false
                    },
                    onCancel: {
                        isEditorPresented = false
                    }
                )
                .id(assetID)
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditorPresented)
    }

    // MARK: - Top Chrome

    private var topChrome: some View {
        HStack(spacing: 12) {
            // Selection indicator (top-left)
            selectionIndicator
                .padding(.leading, 16)

            Spacer()

            // Close button (top-right)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.trailing, 16)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        let assetID = currentAssetID
        if let assetID {
            let selectionIndex = presenter.selectedAssets.firstIndex(of: assetID)
            Button {
                presenter.toggleAssetSelection(assetID)
            } label: {
                if let order = selectionIndex {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 30, height: 30)
                        Text("\(order + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 30, height: 30)
                }
            }
        }
    }

    // MARK: - Bottom Caption Bar

    private var bottomCaptionBar: some View {
        HStack(spacing: 8) {
            // Rotate button (bottom-left)
            Button {
                if let assetID = currentAssetID {
                    rotationByID[assetID] = ((rotationByID[assetID] ?? 0) + 1) % 4
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }

            // Edit button
            Button {
                openEditor()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        currentAssetID.flatMap { presenter.editedImage(for: $0) } != nil
                            ? Color.yellow.opacity(0.5)
                            : Color.white.opacity(0.2)
                    )
                    .clipShape(Circle())
            }

            // Caption field
            TextField("Add a caption…", text: $presenter.captionText)
                .focused($captionFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            // Spacer so send button overlay stays visible
            Spacer()
                .frame(width: 52) // matches send button width + trailing padding
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Open Editor

    private func openEditor() {
        guard let assetID = currentAssetID else { return }
        // Prefer edited image as source if already edited, otherwise load fresh
        if let edited = presenter.editedImage(for: assetID) {
            editorSourceImage = edited
            isEditorPresented = true
        } else {
            guard galleryDataSource.assets.count > currentIndex else { return }
            let asset = galleryDataSource.assets[currentIndex]
            Task {
                let image = try? await galleryDataSource.fullSizeImage(for: asset)
                editorSourceImage = image
                isEditorPresented = image != nil
            }
        }
    }

    // MARK: - Private

    private var currentAssetID: String? {
        guard galleryDataSource.assets.count > currentIndex else { return nil }
        return galleryDataSource.assets[currentIndex].localIdentifier
    }

    private func resolveInitialIndex() {
        for i in 0 ..< galleryDataSource.assets.count {
            if galleryDataSource.assets[i].localIdentifier == initialAssetID {
                currentIndex = i
                return
            }
        }
    }
}

// MARK: - FCLPickerAssetPageView

private struct FCLPickerAssetPageView: View {
    let asset: PHAsset
    let galleryDataSource: FCLGalleryDataSource
    let rotationSteps: Int
    /// When non-nil, displayed in place of the gallery-loaded full-size image.
    let editedImage: UIImage?

    @State private var loadedImage: UIImage?

    /// The image to display: edited override takes precedence over gallery-loaded.
    private var displayImage: UIImage? {
        editedImage ?? loadedImage
    }

    var body: some View {
        ZStack {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // Only apply visual rotation when using the gallery image (not the already-rendered edit).
                    .rotationEffect(.degrees(editedImage == nil ? Double(rotationSteps) * 90 : 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadAsset() }
    }

    private func loadAsset() async {
        guard loadedImage == nil else { return }
        let image = try? await galleryDataSource.fullSizeImage(for: asset)
        loadedImage = image
    }
}

// MARK: - Previews

#if DEBUG
struct FCLMediaPreviewView_Previews: PreviewProvider {
    @Namespace static var namespace

    static var previews: some View {
        FCLMediaPreviewPreviewWrapper()
            .previewDisplayName("Media Preview — Empty")

        FCLPickerAssetPreviewWrapper()
            .previewDisplayName("Picker Asset Preview")
    }
}

private struct FCLMediaPreviewPreviewWrapper: View {
    @Namespace var namespace

    var body: some View {
        let sender = FCLChatMessageSender(id: "user1", displayName: "Alice")
        let presenter = FCLChatPresenter(
            messages: [],
            currentUser: sender
        )
        FCLMediaPreviewView(
            presenter: presenter,
            initialAttachmentID: UUID(),
            namespace: namespace,
            onDismiss: {}
        )
        .background(Color.black)
    }
}

private struct FCLPickerAssetPreviewWrapper: View {
    var body: some View {
        let pickerPresenter = FCLAttachmentPickerPresenter(delegate: nil, onSend: { _, _ in })
        let dataSource = FCLGalleryDataSource(isVideoEnabled: true)
        FCLPickerAssetPreview(
            presenter: pickerPresenter,
            galleryDataSource: dataSource,
            initialAssetID: "",
            onSend: {},
            onDismiss: {}
        )
    }
}
#endif
#endif
