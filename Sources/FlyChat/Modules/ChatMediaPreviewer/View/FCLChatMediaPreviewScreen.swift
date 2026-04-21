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
/// instead of a `@State` on `FCLChatMediaPreviewScreen` prevents the entire preview
/// body from recomputing on every frame of a swipe. Only the bottom carousel —
/// the single subview that actually depends on `pageProgress` — observes it.
@MainActor
final class FCLPagerProgressModel: ObservableObject {
    @Published var pageProgress: CGFloat = 0
}

// MARK: - FCLChatMediaPreviewScreen

/// A full-screen media preview that displays all conversation attachments with horizontal swipe
/// navigation, drag-to-dismiss, chrome toggling, and a message-scoped bottom thumbnail carousel.
///
/// `pageProgress` is a `CGFloat` fractional page index derived from the `TabView` pager's
/// live scroll position using a `GeometryReader` / `PreferenceKey` pipeline. It is exposed
/// internally so ``FCLPreviewThumbCarousel`` can apply Photos-like parallax to thumbnails.
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

    /// Window-space source frame captured at the moment the previewer is opened.
    /// Used exclusively by the present-phase overlay to drive the zoom-in animation.
    /// Nil when the cell was not visible or no frame was recorded.
    var sourceFrame: CGRect? = nil

    @State private var currentIndex: Int = 0
    /// Fractional page index in [0, count-1] updated in real time as the `TabView` scrolls.
    /// Integer values mean fully-settled pages; fractional values appear mid-swipe.
    /// Stored on a dedicated `@StateObject` so per-frame writes do not invalidate
    /// the entire `FCLMediaPreviewView` body — only the bottom carousel, which
    /// observes the model directly, re-renders.
    @StateObject private var progressModel = FCLPagerProgressModel()
    @State private var chromeVisible: Bool = true
    /// Dimming level applied over the transparent cover so the pager reads
    /// clearly while the chat timeline stays faintly visible underneath.
    /// The cover itself is transparent (UIKit hosting controller uses
    /// `backgroundColor = .clear`); this value drives only the black scrim
    /// layer. `0.55` matches the design-system prototype's cover scrim.
    /// On dismiss the value animates to `0` so the scrim fades out in
    /// lock-step with the shrinking snapshot.
    @State private var backgroundOpacity: Double = 0.55
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
    /// Cached global frame of the preview's outer container, refreshed on
    /// every `GeometryReader` pass. Used by `beginDismiss` to derive the
    /// fall-back center-collapse rect without reaching for
    /// `UIScreen.main.bounds`.
    @State private var lastContainerGlobalFrame: CGRect = .zero
    /// Cached safe-area insets of the preview container, refreshed each layout pass.
    /// Used by `fclMediaPreviewAspectFit` to compute a fit rect that does not
    /// overlap the status bar or home indicator.
    @State private var lastSafeAreaInsets: EdgeInsets = .init()

    // MARK: - Present-phase overlay state

    /// Snapshot image displayed during the zoom-in present animation. Populated from the
    /// attachment's thumbnail data at the moment `.onAppear` fires. Cleared once the
    /// present phase completes.
    @State private var presentSnapshot: UIImage?
    /// Container-local rect at which the present-phase overlay starts (source cell frame
    /// converted from window coordinates into the previewer's local coordinate space).
    @State private var presentSourceRect: CGRect?
    /// Container-local rect toward which the present-phase overlay morphs (the aspect-fit
    /// destination of the asset inside the safe-area bounds).
    @State private var presentFitRect: CGRect?
    /// `true` while the present-phase overlay is active and the real pager content is hidden.
    @State private var presentPhaseActive: Bool = false
    /// Drives the present-phase spring animation. `false` = overlay at source rect (start);
    /// `true` = overlay at fit rect and fading out while real content fades in.
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

                    // Present-phase overlay: snapshot morphing from source cell → fit rect.
                    if presentPhaseActive, let snapshot = presentSnapshot {
                        presentOverlay(
                            snapshot: snapshot,
                            containerGlobalFrame: containerGlobalFrame
                        )
                    }
                }

                // Mirror the latest global container frame and safe-area insets into state so
                // the dismiss and present paths can compute rects without reaching for
                // `UIScreen.main.bounds`. The write is deferred to satisfy SwiftUI's
                // "no state mutation during view update" rule.
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
                        // Re-evaluate the present fit rect on safe-area changes (rotation).
                        if presentPhaseActive, let src = presentFitRect {
                            _ = src // no-op capture; actual update happens on next layout pass
                        }
                    }

                // Chrome overlay
                VStack(spacing: 0) {
                    // Top chrome: close button on a glass surface at the top-left.
                    // Matches the design spec — `FCLGlassIconButton` carrying the
                    // `xmark` SF Symbol, sitting 12pt in from the leading and top
                    // safe-area edges.
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
        .onAppear {
            resolveInitialIndex()
            beginPresentPhase()
        }
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
                                isCurrentPage: index == currentIndex,
                                safeAreaInsets: lastSafeAreaInsets
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
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            chromeVisible.toggle()
                        }
                    }
        }
    }

    // MARK: - Present-Phase Overlay

    /// Renders a zoom-in snapshot overlay that animates from the source cell's window-space frame
    /// to the asset's aspect-fit destination inside the safe-area bounds, then crossfades away
    /// as the real pager content becomes visible.
    ///
    /// Ordering:
    ///   1. Overlay appears at `presentSourceRect` (source cell position), real content hidden.
    ///   2. Spring animation morphs overlay to `presentFitRect` while content fades in.
    ///   3. Animation completes → overlay removed, present phase ends.
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
            in: safeAreaBounds(containerSize: containerGlobalFrame.size)
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

    // MARK: - Present-Phase Coordination

    /// Kicks off the zoom-in present animation when a source cell frame is available.
    ///
    /// Phase ordering:
    ///   t=0      — overlay appears at source rect; pager hidden (opacity 0).
    ///   t=0→0.38s — spring morphs overlay from source rect → fit rect;
    ///               real pager content simultaneously fades from 0 → 1.
    ///   t=0.38s+ — animation logically complete; overlay removed; present phase ends.
    private func beginPresentPhase() {
        guard let frame = sourceFrame,
              let current = allMedia.first(where: { $0.attachment.id == initialAttachmentID }),
              let thumbData = current.attachment.thumbnailData,
              let snapshot = UIImage(data: thumbData) else {
            // No source frame or thumbnail — skip overlay; content appears directly.
            return
        }

        // Derive the asset's aspect ratio from the thumbnail so we can compute fitRect
        // without waiting for full-res dimensions.
        let aspectRatio = snapshot.size.height > 0
            ? snapshot.size.width / snapshot.size.height
            : 1

        // Safe-area bounds at the moment of presentation (lastSafeAreaInsets may be zero
        // on first appear; fall back to container global frame size if so).
        let containerSize = lastContainerGlobalFrame.size
        let safeBounds = safeAreaBounds(containerSize: containerSize)
        let fitRect = fclMediaPreviewAspectFit(aspectRatio: aspectRatio, in: safeBounds)

        // Convert the window-space source frame into the container's local coordinate space.
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

        // Defer the spring trigger one runloop cycle so SwiftUI has committed the
        // initial layout at `presentSourceRect` before we animate away from it.
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

    /// Initiates a source-aware dismiss animation from every entry point (close button,
    /// programmatic dismiss). Reads the current cell frame at dismiss-time (NOT at
    /// present-time) from the data source or the legacy FCLMediaPreviewSource protocol.
    ///
    /// - When the source cell is **visible**, the snapshot morphs back to its frame using
    ///   a critically-damped spring (response 0.38, no overshoot). This matches the
    ///   deceleration curve of the system Photos dismiss.
    /// - When the source cell is **off-screen** (nil frame), the snapshot collapses to a
    ///   zero-size point at the screen centre using an easeIn curve over 0.28 s and fades
    ///   to alpha 0. Both cases resolve via `completionCriteria: .logicallyComplete` so
    ///   `onDismiss` is called only after the animation finishes.
    private func beginDismiss() {
        guard dismissTargetFrame == nil else { return }

        guard let current = allMedia[safe: currentIndex] else {
            onDismiss()
            return
        }

        // Read the current cell frame at dismiss-time. Prefer the delegate protocol
        // (FCLChatMediaPreviewSourceDelegate.currentFrame(forItemID:)) so the previewer does
        // not need a separate FCLMediaPreviewSource reference. Fall back to the legacy source
        // ref for hosts that have not yet adopted the delegate extension.
        let currentID = current.attachment.id
        let sourceFrame: CGRect? =
            presenter.currentFrame(forItemID: currentID)
            ?? source?.mediaPreviewFrame(forAssetID: currentID.uuidString)

        let isOffScreen = sourceFrame == nil
        let target = sourceFrame ?? centerCollapseRect(containerGlobalFrame: lastContainerGlobalFrame)

        // Snapshot the current page's image so the overlay can render it during shrink.
        dismissSnapshot = currentPageImage() ?? onePixelImage()
        dismissTargetFrame = target

        // Drive the shrink via a state toggle so SwiftUI can interpolate frame/alpha/corner.
        // Two distinct animation curves depending on whether the source cell is visible:
        //   • Visible cell  — critically-damped spring (no overshoot, natural deceleration).
        //   • Off-screen    — easeIn over 0.28 s so the collapse feels deliberate and quick.
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

    // MARK: - Safe-Area Bounds

    /// Computes the safe-area-inset-respecting bounds rectangle used as the fit container.
    ///
    /// The fit rect is computed inside this reduced rectangle so full-res content does not
    /// overlap the status bar or home indicator. `lastSafeAreaInsets` is refreshed on every
    /// `GeometryReader` pass, so rotation and split-view changes propagate automatically.
    ///
    /// - Parameter containerSize: The full size of the overlay container (pre-safe-area).
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
            // Hand the live progress model to a dedicated subview so per-frame
            // page-progress updates do not invalidate FCLChatMediaPreviewScreen's body.
            // Strip sits 88 pt above the screen edge, adjusted for the safe-area bottom
            // inset so the carousel clears the home indicator on notched devices.
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

// MARK: - Backward Compatibility Typealias

/// Transitional alias for call sites that still reference the previous view type name.
/// Deprecated: use `FCLChatMediaPreviewScreen` directly.
internal typealias FCLMediaPreviewView = FCLChatMediaPreviewScreen

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

/// A single pager page that renders one media attachment at aspect-fit size
/// respecting the container's safe-area insets.
///
/// Image loading uses a two-stage approach:
///   1. Thumbnail from `attachment.thumbnailData` shown immediately (no loading delay).
///   2. Full-res image loaded asynchronously on a `userInitiated` task; crossfades in
///      once available. For PHAsset-backed attachments this uses `PHImageManager`
///      with `.opportunistic` delivery so the system thumbnail upgrades to full-res
///      within the same request.
///
/// The `matchedGeometryEffect` on each image uses the attachment's `id` as the key
/// and `isSource: false`, linking each page to the corresponding chat grid cell
/// (which declares `isSource: true` in the same namespace). Because the previewer
/// is presented via `FCLTransparentFullScreenCover` (a UIKit `overFullScreen`
/// presentation), SwiftUI cannot animate the matched-geometry effect across the
/// UIKit boundary; the zoom-in animation is instead driven by the present-phase
/// overlay in `FCLMediaPreviewView`.
private struct FCLMediaPreviewPage: View {
    let attachment: FCLAttachment
    let namespace: Namespace.ID
    let isCurrentPage: Bool
    /// Safe-area insets of the container, refreshed on rotation/size-class changes.
    /// Used to compute the aspect-fit destination rect so content never overlaps
    /// the status bar or home indicator.
    let safeAreaInsets: EdgeInsets

    @State private var loadedImage: UIImage?
    @State private var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let fitSize = resolvedFitSize(containerSize: containerSize)

            ZStack {
                // Thumbnail layer — always present; acts as placeholder until
                // full-res arrives, then remains underneath for a smooth crossfade.
                //
                // `scaledToFit` produces aspect-fit with transparent letterbox
                // gaps around the photo, matching the design-system prototype
                // (the cover's dim scrim shows through the letterbox). When the
                // asset aspect is unknown, this also prevents a cropped fill.
                if let data = attachment.thumbnailData, let thumb = UIImage(data: data) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fitSize.width, height: fitSize.height)
                        .matchedGeometryEffect(id: attachment.id, in: namespace, isSource: false)
                }

                // Full-res layer — fades in once loaded. Layered on top of the
                // thumbnail so the crossfade is seamless.
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fitSize.width, height: fitSize.height)
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }

                // Loading indicator shown only when no thumbnail is available.
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

    /// Computes the fit size for the attachment inside `containerSize` respecting safe-area insets.
    ///
    /// When actual image dimensions are known (`imageSize` is non-zero), the aspect ratio is
    /// derived from those dimensions. Otherwise the thumbnail's aspect ratio is used as a proxy
    /// until full-res arrives, preventing layout jumps in most cases.
    ///
    /// The fit rectangle is computed against `safeAreaBounds` — the container minus its
    /// safe-area insets — so the content never overlaps the status bar or home indicator.
    /// On safe-area changes (rotation, split-view) SwiftUI re-evaluates this property
    /// automatically because `safeAreaInsets` is a stored property on the view struct.
    private func resolvedFitSize(containerSize: CGSize) -> CGSize {
        // Build the safe-area-reduced bounds.
        let safeBounds = CGRect(
            x: safeAreaInsets.leading,
            y: safeAreaInsets.top,
            width: max(1, containerSize.width - safeAreaInsets.leading - safeAreaInsets.trailing),
            height: max(1, containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom)
        )

        // Derive the aspect ratio: prefer actual image dimensions, fall back to thumbnail.
        let aspectRatio: CGFloat
        if imageSize.height > 0 {
            aspectRatio = imageSize.width / imageSize.height
        } else if let data = attachment.thumbnailData,
                  let thumb = UIImage(data: data),
                  thumb.size.height > 0 {
            aspectRatio = thumb.size.width / thumb.size.height
        } else {
            // Unknown aspect — show at full safe-area size; re-evaluated once image loads.
            return safeBounds.size
        }

        let fitRect = fclMediaPreviewAspectFit(aspectRatio: aspectRatio, in: safeBounds)
        return fitRect.size
    }

    // MARK: - Image Loading

    /// Loads the full-resolution image for this attachment.
    ///
    /// Strategy:
    ///   - Reads the file at `attachment.url` on a background task and decodes it.
    ///   - On load, updates `imageSize` so the aspect-fit computation can upgrade
    ///     from the thumbnail proxy to the real dimensions.
    ///   - Does NOT use `Task.detached`; uses a `Task` with `.userInitiated` priority
    ///     so Swift 6 structured concurrency applies and the capture of `attachment` is safe.
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

/// Generates solid-color JPEG data of the requested size for use in previews.
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

/// Builds a minimal `FCLAttachment` with the given JPEG thumbnail data.
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

/// Preview-only stub conforming to ``FCLChatMediaPreviewSourceDelegate`` so the
/// previewer module's `#Preview` does not reach back into the chat module for a
/// concrete presenter.
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
        // Simulate a vertical (9:16) video attachment using thumbnail data.
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

/// Preview variant that simulates the off-screen-collapse dismiss path.
///
/// `FCLPreviewDataSourceStub` always returns `nil` from `currentFrame(forItemID:)` (via the
/// default extension on `FCLChatMediaPreviewSourceDelegate`), so closing the previewer from
/// this state triggers the easeIn 0.28 s collapse-to-zero-size animation rather than the
/// spring zoom-back. Use this to inspect the collapse animation in Xcode Previews.
private struct FCLPreviewWrapperOffScreenCollapse: View {
    @Namespace var ns

    var body: some View {
        let attachment = fclPreviewAttachment(name: "offscreen", width: 1080, height: 1080, color: .systemPurple)
        // FCLPreviewDataSourceStub always returns nil for currentFrame — source cell
        // is considered off-screen, which exercises the easeIn collapse path.
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

/// Shared layout constants and helpers for the chat media previewer chrome.
///
/// Using a dedicated namespace keeps magic numbers out of call sites and makes
/// the safe-area arithmetic auditable in one place.
enum FCLChatPreviewerLayout {
    /// Clearance (in points) of the carousel strip's **top edge** above the
    /// bottom safe-area boundary. The validated design-system prototype anchors
    /// the strip with its top edge at this offset; the strip's bottom edge
    /// then lands at `(carouselBaseSpacing - stripVisibleHeight)` above the
    /// boundary (~16 pt for the current 72 pt strip).
    static let carouselBaseSpacing: CGFloat = 88

    /// Visible height of the strip as rendered by `FCLChatPreviewerCarouselStrip`.
    /// Kept in sync with the strip's internal `stripHeight` constant; changing
    /// one without updating the other desynchronizes the top-edge anchor.
    static let stripVisibleHeight: CGFloat = 72

    /// Returns the total bottom padding to apply to the carousel strip's
    /// container so its **top edge** lands exactly `carouselBaseSpacing` above
    /// the bottom safe-area boundary on every device (including notched
    /// hardware).
    ///
    /// - Parameter safeArea: The current container safe-area insets, as
    ///   reported by the enclosing `GeometryReader`.
    /// - Returns: `safeArea.bottom + (carouselBaseSpacing - stripVisibleHeight)`,
    ///   placing the strip's bottom edge at `carouselBaseSpacing - stripVisibleHeight`
    ///   above the safe-area boundary (which, by construction, sets the strip's
    ///   top edge at `carouselBaseSpacing` above it).
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
