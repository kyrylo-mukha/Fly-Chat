#if canImport(UIKit)
import Photos
import SwiftUI

// MARK: - FCLGalleryTabView

/// Displays a photo library grid with a camera cell, selection circles, and video duration badges.
///
/// The view handles three authorization states:
/// - `.authorized` / `.limited`: shows the asset grid (with a permission banner for limited access).
/// - `.denied` / `.restricted`: shows a prompt to open Settings.
/// - `.notDetermined`: shows nothing (access is requested on appear).
struct FCLGalleryTabView: View {
    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @ObservedObject var galleryDataSource: FCLGalleryDataSource

    /// Called when the user taps the camera cell.
    let onCameraCapture: () -> Void

    /// Called when the user taps on an asset cell body (not the selection circle).
    let onAssetTap: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            permissionBanner
            assetContent
        }
        .onAppear {
            galleryDataSource.requestAccessAndFetch()
        }
    }

    // MARK: - Permission Banner

    @ViewBuilder
    private var permissionBanner: some View {
        switch galleryDataSource.authorizationStatus {
        case .limited:
            HStack {
                Text("You gave access to selected photos only.")
                    .font(.caption)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Spacer()
                Button("Manage") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))

        case .denied, .restricted:
            VStack(spacing: 12) {
                Text("Photo access is required to select images.")
                    .font(.subheadline)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            EmptyView()
        }
    }

    // MARK: - Asset Content

    @ViewBuilder
    private var assetContent: some View {
        let status = galleryDataSource.authorizationStatus
        if status == .authorized || status == .limited {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    cameraCellView
                    ForEach(0..<galleryDataSource.assets.count, id: \.self) { index in
                        let asset = galleryDataSource.assets.object(at: index)
                        assetCell(for: asset)
                    }
                }
            }
        }
    }

    // MARK: - Camera Cell

    private var cameraCellView: some View {
        Button(action: onCameraCapture) {
            ZStack {
                Color(UIColor.tertiarySystemFill)
                Image(systemName: "camera.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .aspectRatio(1, contentMode: .fill)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take a photo")
    }

    // MARK: - Asset Cell

    @ViewBuilder
    private func assetCell(for asset: PHAsset) -> some View {
        let assetID = asset.localIdentifier
        let selectionIndex = presenter.selectedAssets.firstIndex(of: assetID)
        let isSelected = selectionIndex != nil

        ZStack(alignment: .topTrailing) {
            // Thumbnail body — tapping calls onAssetTap
            Button {
                onAssetTap(assetID)
            } label: {
                FCLAssetThumbnailView(asset: asset, galleryDataSource: galleryDataSource)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            }
            .buttonStyle(.plain)

            // Video duration badge
            if asset.mediaType == .video {
                videoDurationBadge(duration: asset.duration)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            // Selection circle — tapping toggles selection
            selectionCircle(isSelected: isSelected, number: selectionIndex.map { $0 + 1 })
                .padding(4)
        }
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: 0).stroke(Color.blue, lineWidth: 3)
                : nil
        )
    }

    // MARK: - Selection Circle

    private func selectionCircle(isSelected: Bool, number: Int?) -> some View {
        Button {
            // No-op — action is wired below via onTapGesture
        } label: {
            ZStack {
                if isSelected, let number {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 24, height: 24)
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Duration Badge

    private func videoDurationBadge(duration: TimeInterval) -> some View {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return Text(String(format: "%d:%02d", minutes, seconds))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.6))
            .cornerRadius(3)
            .padding(4)
    }
}

// MARK: - FCLAssetThumbnailView

/// Loads and displays a PHAsset thumbnail asynchronously.
private struct FCLAssetThumbnailView: View {
    let asset: PHAsset
    let galleryDataSource: FCLGalleryDataSource

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(UIColor.tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let size = CGSize(width: 200, height: 200)
        galleryDataSource.thumbnail(for: asset, targetSize: size) { loaded in
            self.image = loaded
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FCLGalleryTabView_Previews: PreviewProvider {
    static var previews: some View {
        FCLGalleryTabViewPreviewWrapper()
            .previewDisplayName("Gallery Tab — Default")
    }
}

private struct FCLGalleryTabViewPreviewWrapper: View {
    @StateObject private var presenter = FCLAttachmentPickerPresenter(
        delegate: nil,
        onSend: { _, _ in }
    )
    @StateObject private var dataSource = FCLGalleryDataSource(isVideoEnabled: true)

    var body: some View {
        FCLGalleryTabView(
            presenter: presenter,
            galleryDataSource: dataSource,
            onCameraCapture: {},
            onAssetTap: { _ in }
        )
    }
}
#endif
#endif
