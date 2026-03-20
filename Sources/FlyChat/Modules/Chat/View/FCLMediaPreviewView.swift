#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLMediaPreviewView

/// A full-screen media preview that displays an image attachment with zoom and dismiss controls.
///
/// Presented as a `.fullScreenCover` when the user taps an image or video thumbnail
/// in a chat message bubble. Shows the image loaded from the attachment URL or
/// thumbnail data.
struct FCLMediaPreviewView: View {
    /// The attachment to preview.
    let attachment: FCLAttachment

    /// Callback to dismiss the preview.
    let onDismiss: () -> Void

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let data = attachment.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(16)
                    }
                }
                Spacer()

                HStack {
                    Text(attachment.fileName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let sizeText = FCLFileSizeFormatter.format(bytes: attachment.fileSize) {
                        Text(sizeText)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .onAppear { loadFullImage() }
        .statusBarHidden(true)
    }

    private func loadFullImage() {
        guard attachment.type == .image else { return }
        let url = attachment.url
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.loadedImage = image
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FCLMediaPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        FCLMediaPreviewView(
            attachment: FCLAttachment(
                type: .image,
                url: URL(string: "file:///tmp/photo.jpg")!,
                fileName: "vacation_photo.jpg",
                fileSize: 2_457_600
            ),
            onDismiss: {}
        )
        .previewDisplayName("Image Preview — No Data")
    }
}
#endif
#endif
