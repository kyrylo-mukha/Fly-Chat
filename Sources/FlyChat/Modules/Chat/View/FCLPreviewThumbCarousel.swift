#if canImport(UIKit)
import SwiftUI

// MARK: - FCLPreviewThumbCarousel

/// A horizontally centered thumbnail strip for ``FCLMediaPreviewView``.
///
/// Displays all media items belonging to the message that owns the currently-visible asset.
/// The selected thumbnail centers and all other thumbnails translate with a small parallax
/// factor as the user swipes between full-screen pages — matching iOS Photos strip behavior
/// where thumbnails move more slowly than the full-screen pager, producing a gentle depth cue.
///
/// ## Layout
/// - Default thumb size: 40 × 40 pt.
/// - Selected thumb size: 56 × 56 pt, with a smooth scale animation.
/// - The strip is horizontally centered inside its container.
/// - Single-item messages suppress the strip entirely (no strip for single assets).
///
/// ## Parallax
/// Parallax is driven by `pageProgress: CGFloat`, which the parent exposes as the fractional
/// page index of the full-screen pager. A value of `1.5` means the pager is midway between
/// page 1 and page 2. Each thumbnail at index `i` receives an x-offset of:
/// ```
/// (CGFloat(i) - pageProgress) * thumbStride * parallaxFactor
/// ```
/// where `parallaxFactor` = 0.12 and `thumbStride` = unselected thumb width + spacing.
/// This causes thumbs to drift slower than the page swipe, matching Photos.
///
/// ## Usage
/// ```swift
/// FCLPreviewThumbCarousel(
///     items: messageMedia,
///     selectedAttachmentID: $selectedID,
///     pageProgress: pageProgress
/// )
/// ```
struct FCLPreviewThumbCarousel: View {

    // MARK: - Input

    /// All media items to display in the carousel. Scoped to the current message's attachments.
    let items: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]
    /// The attachment whose thumbnail should appear as selected (highlighted + enlarged).
    @Binding var selectedAttachmentID: UUID
    /// Fractional page index from the full-screen pager. An integer value (e.g. `2.0`) means
    /// a page is fully settled; a mid-value (e.g. `2.5`) means mid-swipe. Used for parallax.
    let pageProgress: CGFloat

    /// Tracks the most recent thumbnail the user tapped directly. Only taps
    /// trigger an explicit `scrollTo(anchor: .center)` call — selection
    /// changes that originate from the underlying pager settling on a new
    /// page would otherwise produce a competing scroll animation that makes
    /// the whole strip jump while the parallax offset is still collapsing
    /// back to zero. The value is consumed and cleared once applied.
    @State private var lastTapSource: UUID?

    // MARK: - Constants

    private let thumbSizeDefault: CGFloat = 40
    private let thumbSizeSelected: CGFloat = 56
    private let spacing: CGFloat = 6
    private let cornerRadius: CGFloat = 6
    /// How many pixels of scroll-view content correspond to one page in the big pager.
    /// Thumbs translate at this fraction of a full page stride, creating the parallax illusion.
    // Tuned to 0.22 to match the iOS Photos thumbnail strip, which produces
    // a strong depth cue while still translating slower than the full pager.
    private let parallaxFactor: CGFloat = 0.22
    private let selectionBorderWidth: CGFloat = 2.5

    // MARK: - Body

    var body: some View {
        // Hide the strip when there is only one asset — nothing to navigate.
        guard items.count > 1 else { return AnyView(EmptyView()) }
        return AnyView(carouselBody)
    }

    // MARK: - Carousel Body

    private var carouselBody: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            // Guarantee the first/last thumb can always center, even on very
            // narrow widths (iPad split-view, compact previews). The computed
            // centering pad collapses to zero once containerWidth shrinks
            // below thumbSizeSelected, which leaves the first thumb flush
            // against the leading edge. Floor the pad with the smaller of
            // half the container or half a selected thumb so the strip always
            // retains breathing room on both sides.
            let edgePadFloor = min(containerWidth / 2, thumbSizeSelected / 2)
            let edgePad = max((containerWidth - thumbSizeSelected) / 2, edgePadFloor)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: spacing) {
                        // Use a fixed-width Color.clear instead of
                        // Spacer(minLength:) inside an HStack with frame
                        // minWidth: the Spacer + minWidth combination yields
                        // indeterminate layout when item count is small
                        // (HStack can't decide whether to grow the spacer or
                        // honor the minimum). A concrete .frame(width:) keeps
                        // layout deterministic regardless of count.
                        Color.clear.frame(width: edgePad, height: 1)

                        ForEach(Array(items.enumerated()), id: \.element.attachment.id) { index, item in
                            let isFocused = item.attachment.id == selectedAttachmentID
                            let thumbSize = isFocused ? thumbSizeSelected : thumbSizeDefault
                            // Parallax offset: thumb at `index` moves proportionally slower
                            // than the page swipe, creating depth separation.
                            let parallaxOffset = parallaxOffsetForThumb(at: index)

                            FCLPreviewThumbCell(
                                attachment: item.attachment,
                                isFocused: isFocused,
                                thumbSize: thumbSize,
                                cornerRadius: cornerRadius,
                                selectionBorderWidth: selectionBorderWidth
                            )
                            .id(item.attachment.id)
                            .offset(x: parallaxOffset)
                            .onTapGesture {
                                // Tapping a thumbnail is an explicit user request to
                                // recenter the strip on this item. Mark the source so
                                // the onChange handler below accepts the scroll.
                                lastTapSource = item.attachment.id
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    selectedAttachmentID = item.attachment.id
                                }
                            }
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.75),
                                value: isFocused
                            )
                        }

                        // Trailing padding mirrors leading to keep last thumb centerable.
                        Color.clear.frame(width: edgePad, height: 1)
                    }
                }
                .onChange(of: selectedAttachmentID) { _, newID in
                    // Only recenter when the change originated from an explicit
                    // thumbnail tap. Pager-driven changes arrive while the
                    // parallax offset is still settling toward zero; letting
                    // the scroll view run a competing 0.2s ease-in-out animation
                    // at the same moment produces a visible jump.
                    guard lastTapSource == newID else { return }
                    lastTapSource = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
                .onAppear {
                    // Snap immediately to the initial selection without animation.
                    proxy.scrollTo(selectedAttachmentID, anchor: .center)
                }
            }
        }
        // Height accommodates the largest possible thumb plus border.
        .frame(height: thumbSizeSelected + selectionBorderWidth * 2 + 4)
    }

    // MARK: - Parallax Calculation

    /// Returns the horizontal parallax translation for the thumbnail at `index`.
    ///
    /// The logic maps the fractional `pageProgress` offset from the thumb's resting position
    /// to a movement that is `parallaxFactor` times the full page stride. When `pageProgress`
    /// equals `index` exactly, the offset is zero. As the user swipes one full page away, the
    /// thumb moves by `parallaxFactor * thumbStride` pixels — noticeably less than the pager.
    ///
    /// - Parameter index: Zero-based thumb index.
    private func parallaxOffsetForThumb(at index: Int) -> CGFloat {
        let thumbStride = thumbSizeDefault + spacing
        let delta = CGFloat(index) - pageProgress
        return -(delta * thumbStride * parallaxFactor)
    }
}

// MARK: - FCLPreviewThumbCell

/// A single thumbnail cell in ``FCLPreviewThumbCarousel``.
///
/// Loads its image asynchronously via ``FCLAsyncThumbnailLoader`` and shows a placeholder
/// while loading. Scales to `thumbSize` with smooth animation driven by the parent.
private struct FCLPreviewThumbCell: View {
    let attachment: FCLAttachment
    let isFocused: Bool
    let thumbSize: CGFloat
    let cornerRadius: CGFloat
    let selectionBorderWidth: CGFloat

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbSize, height: thumbSize)
                    .clipped()
            } else {
                Color.white.opacity(0.15)
                    .frame(width: thumbSize, height: thumbSize)
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.6)
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Only mount the stroke overlay when the cell is focused.
        // A `lineWidth: 0` stroke still rasterizes a transparent pass on
        // every redraw; gating the modifier avoids the no-op cost on the
        // strip's many unfocused thumbs during a live swipe.
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white, lineWidth: selectionBorderWidth)
            }
        }
        .task {
            thumbnail = await FCLAsyncThumbnailLoader.shared.thumbnail(
                for: attachment,
                targetSize: CGSize(width: 120, height: 120)
            )
        }
    }
}

// MARK: - Previews

#if DEBUG

private func makeAttachment(index: Int) -> FCLAttachment {
    FCLAttachment(
        id: UUID(),
        type: .image,
        url: URL(string: "https://picsum.photos/seed/\(index)/400/400")!,
        thumbnailData: nil,
        fileName: "photo_\(index).jpg"
    )
}

private func makeItem(
    messageID: UUID = UUID(),
    index: Int
) -> (messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment) {
    (messageID: messageID, attachmentIndex: index, attachment: makeAttachment(index: index))
}

private struct CarouselPreviewContainer: View {
    let items: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]
    let initialIndex: Int
    let pageProgress: CGFloat

    @State private var selectedID: UUID

    init(
        items: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)],
        initialIndex: Int = 0,
        pageProgress: CGFloat = 0
    ) {
        self.items = items
        self.initialIndex = initialIndex
        self.pageProgress = pageProgress
        _selectedID = State(initialValue: items[safe: initialIndex]?.attachment.id ?? items[0].attachment.id)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                FCLPreviewThumbCarousel(
                    items: items,
                    selectedAttachmentID: $selectedID,
                    pageProgress: pageProgress
                )
                .padding(.bottom, 24)
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("3 assets — index 0 selected") {
    let mid = UUID()
    let items = (0 ..< 3).map { makeItem(messageID: mid, index: $0) }
    CarouselPreviewContainer(items: items, initialIndex: 0)
}

#Preview("10 assets — index 0 selected") {
    let mid = UUID()
    let items = (0 ..< 10).map { makeItem(messageID: mid, index: $0) }
    CarouselPreviewContainer(items: items, initialIndex: 0)
}

#Preview("Single asset — strip hidden") {
    let mid = UUID()
    let items = [makeItem(messageID: mid, index: 0)]
    CarouselPreviewContainer(items: items, initialIndex: 0)
}

#Preview("10 assets — index 3 selected, mid-swipe parallax (progress 3.4)") {
    let mid = UUID()
    let items = (0 ..< 10).map { makeItem(messageID: mid, index: $0) }
    CarouselPreviewContainer(items: items, initialIndex: 3, pageProgress: 3.4)
}

#endif
#endif
