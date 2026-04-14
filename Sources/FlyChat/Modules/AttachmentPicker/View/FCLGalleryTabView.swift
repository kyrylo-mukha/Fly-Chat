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
                    .foregroundColor(Color(.secondaryLabel))
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
            .background(Color(.secondarySystemBackground))

        case .denied, .restricted:
            VStack(spacing: 12) {
                Text("Photo access is required to select images.")
                    .font(.subheadline)
                    .foregroundColor(Color(.secondaryLabel))
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
            FCLGalleryCameraPreviewCell()
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                )
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
            // Body — tap opens preview
            FCLAssetThumbnailView(asset: asset, galleryDataSource: galleryDataSource)
                .aspectRatio(1, contentMode: .fit)
                .contentShape(Rectangle())
                .onTapGesture { onAssetTap(assetID) }

            // Selection circle — 40pt hit target, own tap region
            selectionCircle(isSelected: isSelected, number: selectionIndex.map { $0 + 1 })
                .frame(width: 40, height: 40)
                .padding(.top, 2)
                .padding(.trailing, 2)
                .contentShape(Rectangle())
                .onTapGesture { presenter.toggleAssetSelection(assetID) }
        }
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: 0).stroke(Color.blue, lineWidth: 3)
                : nil
        )
        .overlay(alignment: .bottomTrailing) {
            if asset.mediaType == .video {
                videoDurationBadge(duration: asset.duration)
                    .padding(4)
            }
        }
    }

    // MARK: - Selection Circle

    @ViewBuilder
    private func selectionCircle(isSelected: Bool, number: Int?) -> some View {
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
///
/// Uses `Color` as a sizing base to guarantee a square aspect ratio. The loaded
/// thumbnail image is placed in an `.overlay` with `.scaledToFill()` and `.clipped()`
/// so it fills the square without pushing the cell size.
private struct FCLAssetThumbnailView: View {
    let asset: PHAsset
    let galleryDataSource: FCLGalleryDataSource

    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
            )
            .clipped()
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
        FCLGalleryTabMockPreview(selectedIndices: [])
            .previewDisplayName("Gallery Tab — Browsing")

        FCLGalleryTabMockPreview(selectedIndices: [1, 4])
            .previewDisplayName("Gallery Tab — Multi-Select")
    }
}

/// A self-contained preview that replicates the gallery grid layout using
/// programmatically generated images. This avoids Photos framework access
/// which crashes the Xcode preview agent due to missing TCC entitlements.
private struct FCLGalleryTabMockPreview: View {
    let selectedIndices: Set<Int>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    private static let mockItems: [(Color, Color, Bool, TimeInterval?)] = [
        (.blue,    .cyan,    false, nil),
        (.orange,  .yellow,  false, nil),
        (.green,   .mint,    false, nil),
        (.purple,  .pink,    true,  14),
        (.red,     .orange,  false, nil),
        (.teal,    .blue,    false, nil),
        (.indigo,  .purple,  true,  67),
        (.brown,   .orange,  false, nil),
        (.pink,    .red,     false, nil),
        (.cyan,    .green,   false, nil),
        (.mint,    .teal,    false, nil),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                // Camera cell
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(.secondaryLabel))
                }
                .aspectRatio(1, contentMode: .fit)

                // Mock asset cells
                ForEach(0..<Self.mockItems.count, id: \.self) { index in
                    let item = Self.mockItems[index]
                    let isSelected = selectedIndices.contains(index)
                    let selectionNumber: Int? = {
                        guard isSelected else { return nil }
                        return selectedIndices.sorted().firstIndex(of: index).map { $0 + 1 }
                    }()

                    mockAssetCell(
                        topColor: item.0,
                        bottomColor: item.1,
                        isVideo: item.2,
                        duration: item.3,
                        isSelected: isSelected,
                        selectionNumber: selectionNumber
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func mockAssetCell(
        topColor: Color,
        bottomColor: Color,
        isVideo: Bool,
        duration: TimeInterval?,
        isSelected: Bool,
        selectionNumber: Int?
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [topColor, bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                .aspectRatio(1, contentMode: .fit)

            if isVideo, let duration {
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(3)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            ZStack {
                if isSelected, let selectionNumber {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 24, height: 24)
                    Text("\(selectionNumber)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
            }
            .padding(4)
        }
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: 0).stroke(Color.blue, lineWidth: 3)
                : nil
        )
    }
}
#endif
#endif
