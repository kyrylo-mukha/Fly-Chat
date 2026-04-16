#if canImport(UIKit)
import SwiftUI

// MARK: - FCLChatPreviewerCarouselStrip

/// A horizontally scrolling thumbnail strip for the chat media previewer.
///
/// Replaces the legacy ``FCLPreviewThumbCarousel`` at the previewer call site.
/// ``FCLPreviewThumbCarousel`` is retained as-is for the attachment picker
/// (``FCLAttachmentPreviewScreen``), which has its own scroll / selection model.
///
/// ## Selection binding
/// `selectedItemID` is a two-way binding: writing it from the outside (e.g. when the
/// pager settles on a new page) scrolls the strip to that thumbnail; tapping a thumbnail
/// writes back the new selection and animates the main pager via the same binding.
///
/// `.scrollPosition(id:anchor:)` (iOS 17+) drives the strip scroll position directly
/// from `selectedItemID`, so no `ScrollViewReader` / `scrollTo` call is needed. The
/// modifier keeps the selected thumbnail pinned to the center of the strip.
///
/// ## Scale and parallax
/// Each thumbnail computes its offset from the strip's center using a `GeometryReader`
/// inside the named `"fclCarouselSpace"` coordinate space. From that offset:
///
/// - `fadeDistance` = container width / 2 (no magic constant; derived from visible area).
/// - `scale = 1 - clamp(|centerOffset| / fadeDistance, 0, 0.35)` — center thumb is 1.0×,
///   edge thumbs are 0.65×.
/// - Parallax x-offset = `centerOffset * 0.15` applied **opposite** to the scroll direction
///   (i.e. negative of the natural direction), so thumbs "slide slightly under" the
///   centered position as the user scrolls. Clamped to ±`thumbSize / 2` so no thumb
///   ever crosses the center snap line.
/// - Under `accessibilityReduceMotion` the parallax offset is disabled; scale remains.
/// - Under RTL layout the sign of `centerOffset` is flipped before computing the parallax
///   offset so the sliding direction mirrors correctly.
///
/// ## Short-list centering
/// Leading and trailing padding on the `HStack` = `(stripWidth - thumbSize) / 2` so the
/// first and last thumbnail can reach the visual center of the strip when selected.
struct FCLChatPreviewerCarouselStrip: View {

    // MARK: - Input

    /// All media items belonging to the current message. The strip is hidden when
    /// this contains fewer than 2 items.
    let items: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]

    /// The attachment ID currently selected in the previewer pager.
    /// Writes from the pager update the strip scroll position; taps on the strip
    /// write back to animate the pager.
    @Binding var selectedItemID: UUID

    /// Live fractional page index from the pager's `FCLPagerProgressModel`.
    /// Used for the parallax computation on each thumbnail.
    let pageProgress: CGFloat

    // MARK: - Constants

    private let thumbSize: CGFloat = 52
    private let stripHeight: CGFloat = 72
    private let cornerRadius: CGFloat = 8
    private let selectionBorderWidth: CGFloat = 2.5
    /// Parallax strength: thumb shifts by this fraction of its distance from center.
    private let parallaxStrength: CGFloat = 0.15
    /// Maximum parallax shift: clamp to half the thumb size so no thumb
    /// crosses the center snap line.
    private var parallaxClamp: CGFloat { thumbSize / 2 }

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    // MARK: - State

    /// Drives `.scrollPosition(id:)`. Written when `selectedItemID` changes from
    /// outside so the strip scrolls to the new selection. Also updated on tap so
    /// the binding propagates back to the pager.
    @State private var scrollPositionID: UUID?

    // MARK: - Body

    var body: some View {
        guard items.count > 1 else { return AnyView(EmptyView()) }
        return AnyView(stripBody)
    }

    // MARK: - Strip Body

    private var stripBody: some View {
        GeometryReader { containerGeo in
            let stripWidth = containerGeo.size.width
            // Leading and trailing padding so the first and last thumbnails can
            // scroll to the visual center of the strip when selected.
            let edgePad = max(0, (stripWidth - thumbSize) / 2)

            FCLGlassContainer(cornerRadius: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Fixed-width spacer keeps layout deterministic regardless
                        // of item count (avoids Spacer + minLength ambiguity).
                        Color.clear.frame(width: edgePad, height: 1)

                        ForEach(Array(items.enumerated()), id: \.element.attachment.id) { index, item in
                            thumbView(
                                item: item,
                                index: index,
                                stripWidth: stripWidth
                            )
                        }

                        Color.clear.frame(width: edgePad, height: 1)
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollPositionID, anchor: .center)
            }
            .frame(height: stripHeight)
        }
        .frame(height: stripHeight)
        // Keep scrollPositionID in sync with the externally-driven selectedItemID.
        .onChange(of: selectedItemID) { _, newID in
            scrollPositionID = newID
        }
        .onAppear {
            scrollPositionID = selectedItemID
        }
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private func thumbView(
        item: (messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment),
        index: Int,
        stripWidth: CGFloat
    ) -> some View {
        let isFocused = item.attachment.id == selectedItemID

        GeometryReader { thumbGeo in
            // Measure the thumb's center relative to the strip's coordinate space.
            let thumbCenterX = thumbGeo.frame(in: .named("fclCarouselSpace")).midX
            let screenCenterX = stripWidth / 2
            var rawOffset = thumbCenterX - screenCenterX

            // RTL: mirror the offset direction so parallax slides the correct way.
            if layoutDirection == .rightToLeft {
                rawOffset = -rawOffset
            }

            // fadeDistance derived from visible strip half-width — no magic constant.
            let fadeDistance = max(1, stripWidth / 2)

            // Scale: centered thumb = 1.0, edge thumbs clamp at 0.65.
            let scaleFraction = min(abs(rawOffset) / fadeDistance, 0.35)
            let scale = 1.0 - scaleFraction

            // Parallax: thumb shifts opposite to scroll direction. Clamped to half
            // thumb size so it never crosses the center snap line.
            let rawParallax = -rawOffset * parallaxStrength
            let parallaxOffset: CGFloat = reduceMotion
                ? 0
                : max(-parallaxClamp, min(parallaxClamp, rawParallax))

            FCLCarouselThumbCell(
                attachment: item.attachment,
                isFocused: isFocused,
                thumbSize: thumbSize,
                cornerRadius: cornerRadius,
                selectionBorderWidth: selectionBorderWidth
            )
            // Scale effect: centered thumb at 1.0, peripheral thumbs shrink.
            .scaleEffect(scale)
            // Parallax horizontal shift.
            .offset(x: parallaxOffset)
            .frame(width: thumbSize, height: thumbSize)
            .onTapGesture {
                // Animate the pager to this index via the shared selectedItemID binding.
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedItemID = item.attachment.id
                }
                scrollPositionID = item.attachment.id
            }
        }
        .id(item.attachment.id)
        .frame(width: thumbSize, height: thumbSize)
    }
}

// MARK: - FCLCarouselThumbCell

/// A single thumbnail cell inside ``FCLChatPreviewerCarouselStrip``.
///
/// Loads the thumbnail image asynchronously via ``FCLAsyncThumbnailLoader`` and shows a
/// placeholder while loading. The selection state drives the white stroke overlay.
private struct FCLCarouselThumbCell: View {
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

private func makeCarouselAttachment(index: Int, color: UIColor) -> FCLAttachment {
    let size = CGSize(width: 200, height: 200)
    UIGraphicsBeginImageContextWithOptions(size, true, 1)
    color.setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    let img = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    let data = img?.jpegData(compressionQuality: 0.8)
    return FCLAttachment(
        id: UUID(),
        type: .image,
        url: URL(string: "https://example.com/asset\(index).jpg")!,
        thumbnailData: data,
        fileName: "asset\(index).jpg",
        fileSize: nil
    )
}

private func makeCarouselItem(
    messageID: UUID = UUID(),
    index: Int,
    color: UIColor
) -> (messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment) {
    (messageID: messageID, attachmentIndex: index, attachment: makeCarouselAttachment(index: index, color: color))
}

private let carouselColors: [UIColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemGreen,
    .systemTeal, .systemBlue, .systemIndigo, .systemPurple,
    .systemPink, .systemBrown
]

private struct CarouselStripPreviewContainer: View {
    let items: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]
    let initialIndex: Int

    @State private var selectedID: UUID

    init(
        items: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)],
        initialIndex: Int = 0
    ) {
        self.items = items
        self.initialIndex = initialIndex
        _selectedID = State(initialValue: items[initialIndex].attachment.id)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(white: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                FCLChatPreviewerCarouselStrip(
                    items: items,
                    selectedItemID: $selectedID,
                    pageProgress: CGFloat(initialIndex)
                )
                .coordinateSpace(.named("fclCarouselSpace"))
                .padding(.horizontal, 12)
                .padding(.bottom, 88)
            }
        }
    }
}

/// Single-asset message: strip must be hidden entirely.
#Preview("1 thumbnail — strip hidden") {
    let mid = UUID()
    let items = [makeCarouselItem(messageID: mid, index: 0, color: .systemBlue)]
    return CarouselStripPreviewContainer(items: items, initialIndex: 0)
        .previewDisplayName("1 Thumbnail — Strip Hidden")
}

/// Short list: first and last thumbnails must be reachable at strip center.
#Preview("3 thumbnails — first selected") {
    let mid = UUID()
    let items = (0..<3).map { makeCarouselItem(messageID: mid, index: $0, color: carouselColors[$0]) }
    return CarouselStripPreviewContainer(items: items, initialIndex: 0)
        .previewDisplayName("3 Thumbnails — First Selected")
}

/// Long list: middle thumbnail selected, verifies scale + parallax on surrounding items.
#Preview("10 thumbnails — middle (index 4) selected") {
    let mid = UUID()
    let items = (0..<10).map { makeCarouselItem(messageID: mid, index: $0, color: carouselColors[$0]) }
    return CarouselStripPreviewContainer(items: items, initialIndex: 4)
        .previewDisplayName("10 Thumbnails — Middle (Index 4) Selected")
}

#endif
#endif
