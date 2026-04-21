#if canImport(UIKit)
import SwiftUI

// MARK: - FCLChatPreviewerCarouselStrip

/// A horizontally scrolling thumbnail strip for the chat media previewer.
///
/// `selectedItemID` is a two-way binding: pager settlement scrolls the strip;
/// thumbnail taps animate the pager. Scale and parallax are computed per-thumb
/// via a named `"fclCarouselSpace"` coordinate space; RTL and reduce-motion
/// environments are handled automatically.
struct FCLChatPreviewerCarouselStrip: View {

    // MARK: - Input

    /// All media items belonging to the current message. The strip is hidden when this contains fewer than 2 items.
    let items: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)]

    /// Two-way binding to the currently selected attachment ID; drives strip scroll and pager navigation.
    @Binding var selectedItemID: UUID

    /// Live fractional page index from the pager used for per-thumbnail parallax computation.
    let pageProgress: CGFloat

    // MARK: - Constants

    private let thumbSize: CGFloat = 52
    private let stripHeight: CGFloat = 72
    private let cornerRadius: CGFloat = 8
    private let selectionBorderWidth: CGFloat = 2.5
    private let parallaxStrength: CGFloat = 0.15
    private var parallaxClamp: CGFloat { thumbSize / 2 }

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    // MARK: - State

    @State private var scrollPositionID: UUID?

    // MARK: - Body

    @ViewBuilder
    var body: some View {
        if items.count > 1 {
            stripBody
        }
    }

    // MARK: - Strip Body

    private var stripBody: some View {
        GeometryReader { containerGeo in
            let stripWidth = containerGeo.size.width
            let edgePad = max(0, (stripWidth - thumbSize) / 2)

            FCLGlassContainer(cornerRadius: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
            let thumbCenterX = thumbGeo.frame(in: .named("fclCarouselSpace")).midX
            let screenCenterX = stripWidth / 2
            let baseOffset = thumbCenterX - screenCenterX
            // RTL: mirror offset direction so parallax slides the correct way.
            let rawOffset: CGFloat = (layoutDirection == .rightToLeft) ? -baseOffset : baseOffset

            let fadeDistance = max(1, stripWidth / 2)
            let scaleFraction = min(abs(rawOffset) / fadeDistance, 0.35)
            let scale = 1.0 - scaleFraction

            let rawParallax = -rawOffset * parallaxStrength
            let parallaxOffset: CGFloat = reduceMotion
                ? 0
                : max(-parallaxClamp, min(parallaxClamp, rawParallax))

            let cellOpacity: Double = isFocused ? 1.0 : 0.5

            FCLCarouselThumbCell(
                attachment: item.attachment,
                isFocused: isFocused,
                thumbSize: thumbSize,
                cornerRadius: cornerRadius,
                selectionBorderWidth: selectionBorderWidth
            )
            .scaleEffect(scale)
            .opacity(cellOpacity)
            .offset(x: parallaxOffset)
            .frame(width: thumbSize, height: thumbSize)
            .onTapGesture {
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

#Preview("1 thumbnail — strip hidden") {
    let mid = UUID()
    let items = [makeCarouselItem(messageID: mid, index: 0, color: .systemBlue)]
    return CarouselStripPreviewContainer(items: items, initialIndex: 0)
}

#Preview("3 thumbnails — first selected") {
    let mid = UUID()
    let items = (0..<3).map { makeCarouselItem(messageID: mid, index: $0, color: carouselColors[$0]) }
    return CarouselStripPreviewContainer(items: items, initialIndex: 0)
}

#Preview("10 thumbnails — middle (index 4) selected") {
    let mid = UUID()
    let items = (0..<10).map { makeCarouselItem(messageID: mid, index: $0, color: carouselColors[$0]) }
    return CarouselStripPreviewContainer(items: items, initialIndex: 4)
}

#endif
#endif
