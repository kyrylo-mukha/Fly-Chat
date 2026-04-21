#if canImport(UIKit)
import SwiftUI

// MARK: - FCLPreviewThumbCarousel

/// Horizontally-scrolling thumbnail strip for ``FCLMediaPreviewView``.
///
/// The selected thumb is scaled up (56pt) and the strip scrolls to keep it centered.
/// Thumbnails translate with a parallax factor as the user pages through full-screen previews.
/// The strip is hidden when there is only one media item.
struct FCLPreviewThumbCarousel: View {

    // MARK: - Input

    let items: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]
    @Binding var selectedAttachmentID: UUID
    /// Fractional page index from the full-screen pager (e.g. `2.5` = mid-swipe between pages 2 and 3).
    let pageProgress: CGFloat

    /// Tracks the most recently tapped thumbnail ID. Only tap-originated selection changes
    /// trigger an explicit `scrollTo` call; pager-driven changes skip it to avoid competing
    /// scroll animations while the parallax offset is still settling.
    @State private var lastTapSource: UUID?

    // MARK: - Constants

    private let thumbSizeDefault: CGFloat = 40
    private let thumbSizeSelected: CGFloat = 56
    private let spacing: CGFloat = 6
    private let cornerRadius: CGFloat = 6
    /// Tuned to approximate the iOS Photos thumbnail strip parallax depth cue.
    private let parallaxFactor: CGFloat = 0.22
    private let selectionBorderWidth: CGFloat = 2.5

    // MARK: - Body

    var body: some View {
        guard items.count > 1 else { return AnyView(EmptyView()) }
        return AnyView(carouselBody)
    }

    // MARK: - Carousel Body

    private var carouselBody: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            let edgePadFloor = min(containerWidth / 2, thumbSizeSelected / 2)
            let edgePad = max((containerWidth - thumbSizeSelected) / 2, edgePadFloor)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: spacing) {
                        /// Fixed-width spacer instead of `Spacer` so layout stays deterministic regardless of item count.
                        Color.clear.frame(width: edgePad, height: 1)

                        ForEach(Array(items.enumerated()), id: \.element.attachment.id) { index, item in
                            let isFocused = item.attachment.id == selectedAttachmentID
                            let thumbSize = isFocused ? thumbSizeSelected : thumbSizeDefault
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

                        Color.clear.frame(width: edgePad, height: 1)
                    }
                }
                .onChange(of: selectedAttachmentID) { _, newID in
                    guard lastTapSource == newID else { return }
                    lastTapSource = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedAttachmentID, anchor: .center)
                }
            }
        }
        .frame(height: thumbSizeSelected + selectionBorderWidth * 2 + 4)
    }

    // MARK: - Parallax Calculation

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
        /// Gating the stroke overlay on `isFocused` avoids a transparent rasterization pass on every unfocused thumb during a live swipe.
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
