#if canImport(UIKit)
import SwiftUI
import UIKit

/// A horizontally scrollable strip of attachment thumbnail previews displayed above the input bar.
///
/// Each attachment is shown as a small thumbnail (or a file-type icon for non-image types)
/// with a remove button and truncated filename. The strip hides itself when there are no attachments.
struct FCLAttachmentPreviewStrip: View {
    /// The list of attachments currently queued for sending.
    let attachments: [FCLAttachment]
    /// The size (in points) of each thumbnail image within a cell.
    let thumbnailSize: CGFloat
    /// Callback invoked with the index of the attachment to remove.
    let onRemove: (Int) -> Void

    /// The fixed width/height of each cell container (slightly larger than the thumbnail to allow spacing).
    private let cellSize: CGFloat = 56

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        attachmentCell(attachment: attachment, index: index)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    /// Renders a single attachment cell with a thumbnail, remove button, and filename label.
    ///
    /// - Parameters:
    ///   - attachment: The attachment to display.
    ///   - index: The position index used for the remove callback.
    private func attachmentCell(attachment: FCLAttachment, index: Int) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                thumbnailView(for: attachment)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: cellSize, height: cellSize)

                Button(action: { onRemove(index) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white).frame(width: 14, height: 14))
                }
                .offset(x: 4, y: -4)
                .accessibilityLabel("Remove \(attachment.fileName)")
            }

            Text(attachment.fileName)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: cellSize)
        }
    }

    /// Renders either the attachment's thumbnail image or a generic file icon placeholder.
    @ViewBuilder
    private func thumbnailView(for attachment: FCLAttachment) -> some View {
        if let image = attachment.thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            fileIconView(for: attachment)
        }
    }

    /// Renders a generic file icon with the file extension label for attachments without thumbnails.
    private func fileIconView(for attachment: FCLAttachment) -> some View {
        VStack(spacing: 2) {
            Image(systemName: iconName(for: attachment.type))
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            Text(fileExtension(from: attachment.fileName))
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.secondarySystemFill))
    }

    /// Returns the SF Symbol name for the given attachment type.
    private func iconName(for type: FCLAttachmentType) -> String {
        switch type {
        case .image: return "photo"
        case .video: return "film"
        case .file: return "doc"
        }
    }

    /// Extracts and uppercases the file extension from a filename, defaulting to "FILE".
    private func fileExtension(from fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }
}

// MARK: - Previews

#if DEBUG
struct FCLAttachmentPreviewStrip_Previews: PreviewProvider {
    static var previews: some View {
        previewContent
    }

    @ViewBuilder
    private static var previewContent: some View {
        FCLAttachmentPreviewStrip(
            attachments: [
                FCLAttachment(type: .image, url: URL(string: "file:///tmp/photo.jpg")!, fileName: "photo.jpg"),
                FCLAttachment(type: .file, url: URL(string: "file:///tmp/doc.pdf")!, fileName: "report.pdf", fileSize: 1_234_567),
                FCLAttachment(type: .video, url: URL(string: "file:///tmp/clip.mp4")!, fileName: "clip.mp4"),
            ],
            thumbnailSize: FCLInputDefaults.attachmentThumbnailSize,
            onRemove: { _ in }
        )
        .previewDisplayName("Mixed Attachments")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLAttachmentPreviewStrip(
            attachments: [
                FCLAttachment(type: .file, url: URL(string: "file:///tmp/a.pdf")!, fileName: "a.pdf"),
            ],
            thumbnailSize: FCLInputDefaults.attachmentThumbnailSize,
            onRemove: { _ in }
        )
        .previewDisplayName("Single File")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLAttachmentPreviewStrip(
            attachments: [],
            thumbnailSize: FCLInputDefaults.attachmentThumbnailSize,
            onRemove: { _ in }
        )
        .previewDisplayName("Empty (Hidden)")
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
#endif
