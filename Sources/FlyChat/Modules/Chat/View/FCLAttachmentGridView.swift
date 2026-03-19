import Foundation
import SwiftUI

// MARK: - Grid Layout (platform-independent)

/// Utility that computes a row-based grid layout for attachment thumbnails.
///
/// The layout algorithm arranges items in rows of up to two,
/// with a special case for three items (one on top, two on bottom).
enum FCLAttachmentGridLayout {
    /// Returns row-based layout as array of arrays of indices.
    /// - 1 item: [[0]]
    /// - 2 items: [[0, 1]]
    /// - 3 items: [[0], [1, 2]]
    /// - 4 items: [[0, 1], [2, 3]]
    /// - 5 items: [[0, 1], [2, 3], [4]]
    ///
    /// - Parameter count: The total number of items to lay out.
    /// - Returns: An array of rows, where each row is an array of item indices.
    static func grid(for count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        if count == 1 { return [[0]] }
        if count == 2 { return [[0, 1]] }
        if count == 3 { return [[0], [1, 2]] }
        var rows: [[Int]] = []
        var i = 0
        while i < count {
            if i + 1 < count {
                rows.append([i, i + 1])
                i += 2
            } else {
                rows.append([i])
                i += 1
            }
        }
        return rows
    }
}

// MARK: - Attachment Grid View

#if canImport(UIKit)
import UIKit

/// Renders a grid of image and video attachment thumbnails inside a chat bubble.
///
/// Media attachments are laid out using ``FCLAttachmentGridLayout``. Each cell shows
/// either the thumbnail image (when available) or a gray placeholder. Video attachments
/// display a centered play button overlay.
struct FCLAttachmentGridView: View {
    /// The media attachments to display (filtered to `.image` and `.video` types only).
    let attachments: [FCLAttachment]
    /// The maximum width of the grid, matching the bubble's max width.
    let maxWidth: CGFloat

    var body: some View {
        let layout = FCLAttachmentGridLayout.grid(for: attachments.count)
        VStack(spacing: 2) {
            ForEach(Array(layout.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { index in
                        attachmentCell(attachments[index])
                    }
                }
            }
        }
    }

    /// Renders a single attachment cell with a thumbnail or placeholder and an optional video overlay.
    @ViewBuilder
    private func attachmentCell(_ attachment: FCLAttachment) -> some View {
        ZStack {
            if let data = attachment.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }

            // Play overlay for video
            if attachment.type == .video {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                    )
            }
        }
        .frame(height: 120)
        .clipped()
        .cornerRadius(4)
    }
}

// MARK: - Previews

#if DEBUG
struct FCLAttachmentGridView_Previews: PreviewProvider {
    static var previews: some View {
        previewContent
    }

    @ViewBuilder
    private static var previewContent: some View {
        FCLAttachmentGridView(
            attachments: [
                FCLAttachment(type: .image, url: URL(string: "file:///tmp/1.jpg")!, fileName: "photo1.jpg")
            ],
            maxWidth: 280
        )
        .previewDisplayName("1 Image (No Thumbnail)")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLAttachmentGridView(
            attachments: [
                FCLAttachment(type: .image, url: URL(string: "file:///tmp/1.jpg")!, fileName: "photo1.jpg"),
                FCLAttachment(type: .image, url: URL(string: "file:///tmp/2.jpg")!, fileName: "photo2.jpg")
            ],
            maxWidth: 280
        )
        .previewDisplayName("2 Images")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLAttachmentGridView(
            attachments: [
                FCLAttachment(type: .image, url: URL(string: "file:///tmp/1.jpg")!, fileName: "photo1.jpg"),
                FCLAttachment(type: .image, url: URL(string: "file:///tmp/2.jpg")!, fileName: "photo2.jpg"),
                FCLAttachment(type: .image, url: URL(string: "file:///tmp/3.jpg")!, fileName: "photo3.jpg")
            ],
            maxWidth: 280
        )
        .previewDisplayName("3 Images")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLAttachmentGridView(
            attachments: [
                FCLAttachment(type: .video, url: URL(string: "file:///tmp/video.mp4")!, fileName: "video.mp4")
            ],
            maxWidth: 280
        )
        .previewDisplayName("Video with Play Overlay")
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
#endif
