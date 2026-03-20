#if canImport(UIKit)
import Photos
import SwiftUI
import UIKit

// MARK: - FCLMediaPreviewView

/// A full-screen media preview that displays message attachments with horizontal swipe navigation.
///
/// Presented as a `.fullScreenCover` when the user taps an image or video thumbnail
/// in a chat message bubble. Supports swiping between multiple media attachments
/// within the same message.
struct FCLMediaPreviewView: View {
    let attachments: [FCLAttachment]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int

    init(attachments: [FCLAttachment], initialIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.attachments = attachments
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    FCLMediaPreviewPage(attachment: attachment)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .automatic : .never))

            VStack {
                HStack {
                    if attachments.count > 1 {
                        Text("\(currentIndex + 1)/\(attachments.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.leading, 16)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(16)
                    }
                }
                Spacer()

                if currentIndex < attachments.count {
                    let attachment = attachments[currentIndex]
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
        }
        .statusBarHidden(true)
    }
}

// MARK: - FCLMediaPreviewPage

/// A single page within the media preview TabView showing one attachment.
private struct FCLMediaPreviewPage: View {
    let attachment: FCLAttachment

    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
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
        }
        .onAppear { loadFullImage() }
    }

    private func loadFullImage() {
        guard attachment.type == .image || attachment.type == .video else { return }
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

// MARK: - FCLCameraCapturePreview

/// Preview screen shown after camera capture, allowing the user to send, retake, or cancel.
struct FCLCameraCapturePreview: View {
    let attachment: FCLAttachment
    let onSend: () -> Void
    let onRetake: () -> Void
    let onCancel: () -> Void

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(16)
                    Spacer()
                }
                Spacer()

                HStack(spacing: 40) {
                    Button(action: onRetake) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Retake")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    Button(action: onSend) {
                        VStack(spacing: 4) {
                            Image(systemName: "paperplane.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.blue)
                            Text("Send")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear { loadImage() }
        .statusBarHidden(true)
    }

    private func loadImage() {
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

// MARK: - FCLPickerAssetPreview

/// Full-screen preview for a gallery asset tapped in the attachment picker.
struct FCLPickerAssetPreview: View {
    let assetID: String
    let galleryDataSource: FCLGalleryDataSource
    let onDismiss: () -> Void

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = loadedImage {
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
            }
        }
        .onAppear { loadAsset() }
        .statusBarHidden(true)
    }

    private func loadAsset() {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = result.firstObject else { return }

        Task {
            do {
                let image = try await galleryDataSource.fullSizeImage(for: asset)
                self.loadedImage = image
            } catch {}
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FCLMediaPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        FCLMediaPreviewView(
            attachments: [
                FCLAttachment(
                    type: .image,
                    url: URL(string: "file:///tmp/photo.jpg")!,
                    fileName: "vacation_photo.jpg",
                    fileSize: 2_457_600
                )
            ],
            onDismiss: {}
        )
        .previewDisplayName("Single Image Preview")

        FCLCameraCapturePreview(
            attachment: FCLAttachment(
                type: .image,
                url: URL(string: "file:///tmp/camera.jpg")!,
                fileName: "Camera_ABC123.jpg",
                fileSize: 1_024_000
            ),
            onSend: {},
            onRetake: {},
            onCancel: {}
        )
        .previewDisplayName("Camera Capture Preview")
    }
}
#endif
#endif
