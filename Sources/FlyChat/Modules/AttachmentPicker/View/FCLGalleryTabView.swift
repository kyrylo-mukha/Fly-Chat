#if canImport(UIKit)
import Photos
import SwiftUI

// MARK: - FCLGalleryTabView

/// Displays a photo library grid with a camera cell, selection circles, and video duration badges.
struct FCLGalleryTabView: View {
    @ObservedObject var authCoordinator: FCLPhotoAuthorizationCoordinator
    @ObservedObject var collectionRegistry: FCLAssetCollectionRegistry

    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @ObservedObject var galleryDataSource: FCLGalleryDataSource

    @Environment(\.scenePhase) private var scenePhase

    let onCameraCapture: () -> Void
    let onAssetTap: (String) -> Void
    var cameraSourceRelay: FCLCameraSourceRelay? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            contentForStatus
        }
        .onChange(of: presenter.isPresentationComplete, initial: false) { _, isComplete in
            guard isComplete else { return }
            Task {
                await authCoordinator.requestAccessIfNeeded()
                syncDataSourceAfterAuth()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            authCoordinator.refresh()
            syncDataSourceAfterAuth()
        }
        .onChange(of: collectionRegistry.selectedCollectionID) { _, newID in
            galleryDataSource.collectionID = newID
        }
    }

    // MARK: - Content by status

    @ViewBuilder
    private var contentForStatus: some View {
        switch authCoordinator.status {
        case .authorized, .limited:
            assetContent
        case .denied, .restricted, .notDetermined:
            Color.clear
        @unknown default:
            Color.clear
        }
    }

    // MARK: - Asset Content

    @ViewBuilder
    private var assetContent: some View {
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

    // MARK: - Data Source Sync

    /// Bridges the coordinator's resolved status back into ``FCLGalleryDataSource``
    /// so asset fetching and photo library observation are wired up correctly.
    /// Also loads the collection registry when full access is confirmed.
    private func syncDataSourceAfterAuth() {
        let status = authCoordinator.status
        if status == .authorized {
            collectionRegistry.load()
            galleryDataSource.collectionID = collectionRegistry.selectedCollectionID
            galleryDataSource.requestAccessAndFetch()
        } else if status == .limited {
            galleryDataSource.collectionID = nil
            galleryDataSource.requestAccessAndFetch()
        }
    }

    // MARK: - Camera Cell

    private var cameraCellView: some View {
        FCLGalleryCameraCellContainer(
            onTap: onCameraCapture,
            relay: cameraSourceRelay
        )
    }

    // MARK: - Asset Cell

    @ViewBuilder
    private func assetCell(for asset: PHAsset) -> some View {
        let assetID = asset.localIdentifier
        let selectionIndex = presenter.selectedAssets.firstIndex(of: assetID)
        let isSelected = selectionIndex != nil

        ZStack(alignment: .topTrailing) {
            FCLAssetThumbnailView(asset: asset, galleryDataSource: galleryDataSource)
                .aspectRatio(1, contentMode: .fit)
                .contentShape(Rectangle())
                .onTapGesture { onAssetTap(assetID) }

            if isSelected {
                Color.blue.opacity(0.18)
                    .allowsHitTesting(false)
            }

            selectionCircle(isSelected: isSelected, number: selectionIndex.map { $0 + 1 })
                .frame(width: 40, height: 40)
                .padding(.top, 2)
                .padding(.trailing, 2)
                .contentShape(Rectangle())
                .onTapGesture { presenter.toggleAssetSelection(assetID) }
        }
        .overlay(alignment: .bottomLeading) {
            if asset.mediaType == .video {
                videoDurationBadge(duration: asset.duration)
                    .padding(.leading, 6)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Selection Circle

    @ViewBuilder
    private func selectionCircle(isSelected: Bool, number: Int?) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.blue : Color.black.opacity(0.18))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isSelected ? 1.0 : 0.9), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(isSelected ? 0.25 : 0.08), radius: isSelected ? 3 : 0.5, x: 0, y: 1)

            if isSelected, let number {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
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
            .background(Color.black.opacity(0.45))
            .cornerRadius(4)
    }
}

// MARK: - FCLGalleryCameraCellContainer

/// Gallery camera cell with scope-08 frame publishing and return pulse.
///
/// Publishes its window-space frame to the supplied ``FCLCameraSourceRelay``
/// on appear and on scroll (via the `GeometryReader`-driven `onChange` of the
/// global frame). Observes the relay's `pulseTick` to play a single 0.35s
/// ease-in-out pulse-highlight when the camera closes back to it.
private struct FCLGalleryCameraCellContainer: View {
    let onTap: () -> Void
    let relay: FCLCameraSourceRelay?

    @State private var pulseOpacity: Double = 0

    var body: some View {
        Button(action: onTap) {
            FCLGalleryCameraPreviewCell()
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(pulseOpacity))
                        .allowsHitTesting(false)
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                relay?.sourceFrame = proxy.frame(in: .global)
                            }
                            .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                                relay?.sourceFrame = newFrame
                            }
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take a photo")
        .onChange(of: relay?.pulseTick ?? 0) { _, _ in
            runPulse()
        }
    }

    private func runPulse() {
        let half = FCLCameraTransitionCurves.pulseDuration / 2
        withAnimation(.easeInOut(duration: half)) {
            pulseOpacity = 0.35
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + half) {
            withAnimation(.easeInOut(duration: half)) {
                pulseOpacity = 0
            }
        }
    }
}

// MARK: - FCLAssetThumbnailView

/// Loads and displays a PHAsset thumbnail asynchronously.
private struct FCLAssetThumbnailView: View {
    let asset: PHAsset
    let galleryDataSource: FCLGalleryDataSource

    @State private var image: UIImage?

    var body: some View {
        FCLPalette.tertiarySystemFill
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

private struct FCLGalleryTabMockPreview: View {
    let selectedIndices: Set<Int>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

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
                    FCLPalette.tertiarySystemFill
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(FCLPalette.secondaryLabel)
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

            if isSelected {
                Color.blue.opacity(0.18)
                    .allowsHitTesting(false)
            }

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 6)
                    .padding(.bottom, 6)
            }

            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.black.opacity(0.18))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isSelected ? 1.0 : 0.9), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.25 : 0.08), radius: isSelected ? 3 : 0.5, x: 0, y: 1)

                if isSelected, let selectionNumber {
                    Text("\(selectionNumber)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(4)
        }
    }
}
#endif
#endif
