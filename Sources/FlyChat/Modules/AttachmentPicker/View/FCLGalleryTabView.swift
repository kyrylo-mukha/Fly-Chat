#if canImport(UIKit)
import Photos
import SwiftUI

// MARK: - FCLGalleryTabView

/// Displays a photo library grid with a camera cell, selection circles, and video duration badges.
///
/// Authorization is driven by ``FCLPhotoAuthorizationCoordinator``, which handles
/// the initial access request and live status refresh on scene-active return. The
/// gallery handles four states:
/// - `.authorized`: shows the full asset grid.
/// - `.limited`: shows a "Manage selected photos" banner above the grid (via
///   ``FCLPickerPermissionBanner``) so the user can adjust access without leaving.
/// - `.denied` / `.restricted`: shows ``FCLPickerDeniedView`` with an "Open Settings"
///   button.
/// - `.notDetermined`: access is requested on appear via the coordinator.
struct FCLGalleryTabView: View {
    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @ObservedObject var galleryDataSource: FCLGalleryDataSource

    /// Authorization coordinator that owns the permission state and refresh logic.
    @StateObject private var authCoordinator = FCLPhotoAuthorizationCoordinator()

    /// Registry that discovers and orders photo collections.
    /// Only loaded in `.authorized` state per PRD item 5.
    @StateObject private var collectionRegistry = FCLAssetCollectionRegistry()

    /// Scene phase, observed to refresh authorization when the user returns from Settings.
    @Environment(\.scenePhase) private var scenePhase

    /// Called when the user taps the camera cell.
    let onCameraCapture: () -> Void

    /// Called when the user taps on an asset cell body (not the selection circle).
    let onAssetTap: (String) -> Void

    /// Optional scope-08 relay used to publish the camera cell's window-space
    /// frame and to drive the return pulse-highlight. When `nil` the cell
    /// renders without frame publishing and without pulse support.
    var cameraSourceRelay: FCLCameraSourceRelay? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            permissionContent
        }
        .task {
            await authCoordinator.requestAccessIfNeeded()
            // After the coordinator obtains or confirms access, sync the gallery
            // data source so it fetches assets using the up-to-date status.
            syncDataSourceAfterAuth()
        }
        // iOS 17+ two-argument onChange: fires when scenePhase transitions to
        // .active so any permission change made in Settings is picked up immediately.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            authCoordinator.refresh()
            syncDataSourceAfterAuth()
        }
        // Propagate the selected collection ID from the registry into the data source.
        .onChange(of: collectionRegistry.selectedCollectionID) { _, newID in
            galleryDataSource.collectionID = newID
        }
    }

    // MARK: - Permission Content

    @ViewBuilder
    private var permissionContent: some View {
        switch authCoordinator.status {
        case .authorized:
            // In full-access mode show the collection selector pill above the grid.
            VStack(spacing: 0) {
                collectionSelectorBar
                assetContent
            }

        case .limited:
            VStack(spacing: 0) {
                // Thread the current staged selection count and the total
                // assets the user granted access to into the banner so the
                // label reads "N of M selected" when both counts are known.
                FCLPickerPermissionBanner(
                    selectedCount: presenter.selectedAssets.count,
                    totalCount: galleryDataSource.assets.count
                )
                assetContent
            }

        case .denied, .restricted:
            FCLPickerDeniedView()

        case .notDetermined:
            // Blank while the request dialog is in flight; the .task modifier
            // fires the request so we never stay here long.
            Color.clear

        @unknown default:
            Color.clear
        }
    }

    // MARK: - Collection Selector Bar

    /// The "Recents ▾" pill chip shown only in `.authorized` state.
    private var collectionSelectorBar: some View {
        HStack {
            Spacer()
            FCLCollectionSelectorView(registry: collectionRegistry)
            Spacer()
        }
        .padding(.vertical, 8)
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
            // Load the registry (no-op if already loaded).
            collectionRegistry.load()
            // Set the initial collection ID from the registry's default selection.
            galleryDataSource.collectionID = collectionRegistry.selectedCollectionID
            galleryDataSource.requestAccessAndFetch()
        } else if status == .limited {
            // In limited mode: flat fetch, no collection selector.
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
                    // Pulse overlay — a subtle white tint that animates in and
                    // out in 0.35s total when the relay tick increments.
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
