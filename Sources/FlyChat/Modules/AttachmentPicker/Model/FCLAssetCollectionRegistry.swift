#if canImport(UIKit)
import Photos
import UIKit
import SwiftUI

// MARK: - FCLAssetCollection

/// A value-type snapshot of a single `PHAssetCollection`.
///
/// Conforms to `Identifiable` via the collection's stable `localIdentifier`.
/// `UIImage` is intentionally kept out of this struct — thumbnail images are
/// published separately on `FCLAssetCollectionRegistry` to avoid sending a
/// non-Sendable type across isolation boundaries.
struct FCLAssetCollection: Identifiable, Equatable {
    /// Stable identifier — matches `PHAssetCollection.localIdentifier`.
    let id: String
    /// Localized title shown in the collection list.
    let title: String
    /// Precise asset count. `PHCollection.estimatedAssetCount` is `NSNotFound`
    /// for smart albums, so we store a fetched count at construction time.
    let assetCount: Int
    /// The underlying `PHAssetCollection` subtype, used to prioritize Recents.
    let subtype: PHAssetCollectionSubtype

    static func == (lhs: FCLAssetCollection, rhs: FCLAssetCollection) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - FCLAssetCollectionRegistry

/// Discovers, orders, and thumbnail-caches the user's photo collections.
///
/// ## Lifecycle
/// Call `load()` once after photo library authorization is confirmed `.authorized`.
/// The registry stays alive for the session; do NOT call `load()` in `.limited`
/// state (the collection selector is hidden in that mode per PRD item 5).
///
/// ## Concurrency
/// `@MainActor` throughout. PhotoKit fetch calls are synchronous and are safe on
/// the main thread for metadata-only reads (no I/O). Thumbnail I/O runs through
/// `PHCachingImageManager` with a result handler that already hops back to the
/// main queue via `DispatchQueue.main.async` before mutating `@Published` state.
///
/// ## Session persistence
/// `selectedCollectionID` is in-memory only and resets when the registry is
/// deallocated (i.e. when the picker sheet is dismissed). It is never written to
/// UserDefaults.
@MainActor
final class FCLAssetCollectionRegistry: ObservableObject {

    // MARK: - Published State

    /// Ordered list: Recents first, then remaining smart albums in system order,
    /// then user albums ordered by creation date.
    @Published private(set) var collections: [FCLAssetCollection] = []

    /// Thumbnail images keyed by `FCLAssetCollection.id`. Published so observers
    /// can react when an image finishes loading without re-rendering the whole list.
    @Published private(set) var thumbnails: [String: UIImage] = [:]

    /// The collection that is currently selected. `nil` means "all photos" (the
    /// synthetic Recents fallback built from `PHAsset.fetchAssets(with:)`).
    @Published var selectedCollectionID: String?

    // MARK: - Private

    private let imageManager = PHCachingImageManager()
    private var didLoad = false

    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    // MARK: - Init

    init() {}

    // MARK: - API

    /// User-meaningful smart-album subtypes. Everything outside this list
    /// (e.g. `smartAlbumAllHidden`, `smartAlbumSlomoVideos`,
    /// `smartAlbumGeneric`) is filtered out during discovery so the selector
    /// list only shows collections a user would recognize from the Photos
    /// app. Keep the order aligned with the Photos-app sidebar.
    private static let allowedSmartAlbumSubtypes: Set<PHAssetCollectionSubtype> = [
        .smartAlbumRecentlyAdded,
        .smartAlbumFavorites,
        .smartAlbumVideos,
        .smartAlbumPanoramas,
        .smartAlbumScreenshots,
        // Portrait-mode album — the PhotoKit enum case is `smartAlbumDepthEffect`,
        // not `smartAlbumPortrait`; the latter does not exist.
        .smartAlbumDepthEffect,
        .smartAlbumLivePhotos,
        .smartAlbumSelfPortraits,
        .smartAlbumBursts,
        .smartAlbumTimelapses
    ]

    /// Discovers all available collections and preloads key-asset thumbnails.
    ///
    /// Safe to call repeatedly; subsequent calls after the first are no-ops.
    func load() {
        guard !Self.isRunningInPreview, !didLoad else { return }
        didLoad = true

        var result: [FCLAssetCollection] = []

        // 1. Smart albums in Photos-app system order (default PHFetchOptions ordering).
        //    `.any` returns every subtype including internal / developer-only
        //    ones (`smartAlbumAllHidden`, `smartAlbumSlomoVideos`, …); the
        //    `makeItem(from:)` helper rejects subtypes outside
        //    `allowedSmartAlbumSubtypes` so only user-meaningful albums reach
        //    the selector.
        let smartFetch = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        smartFetch.enumerateObjects { collection, _, _ in
            if let item = Self.makeItem(from: collection) {
                result.append(item)
            }
        }

        // 2. User albums in default (creation-date) order.
        let userFetch = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        userFetch.enumerateObjects { collection, _, _ in
            if let item = Self.makeItem(from: collection) {
                result.append(item)
            }
        }

        // Promote Recents (smartAlbumRecentlyAdded) to index 0 if present and
        // pre-select it as the default collection. When the device does not
        // expose a `smartAlbumRecentlyAdded` (possible on early-state
        // libraries or custom OS configurations), leave
        // `selectedCollectionID` at `nil` so the data source falls back to a
        // flat `PHAsset.fetchAssets(with:)` — a "Recents"-equivalent view
        // across the entire library — instead of picking whichever allow-listed
        // album happens to sort first.
        if let recentsIndex = result.firstIndex(where: { $0.subtype == .smartAlbumRecentlyAdded }),
           recentsIndex != 0 {
            let recents = result.remove(at: recentsIndex)
            result.insert(recents, at: 0)
        }

        collections = result

        if let recents = result.first, recents.subtype == .smartAlbumRecentlyAdded {
            selectedCollectionID = recents.id
        } else {
            selectedCollectionID = nil
        }

        // Kick off thumbnail loads.
        result.forEach { loadThumbnail(for: $0) }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail(for item: FCLAssetCollection) {
        // Fetch the key asset for the collection.
        let collectionFetch: PHFetchResult<PHAssetCollection> =
            PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [item.id],
                options: nil
            )
        guard let collection = collectionFetch.firstObject else { return }

        let assetOptions = PHFetchOptions()
        assetOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        assetOptions.fetchLimit = 1
        let assetFetch = PHAsset.fetchAssets(in: collection, options: assetOptions)
        guard let keyAsset = assetFetch.firstObject else { return }

        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: 120 * scale, height: 120 * scale)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        // PHCachingImageManager result handler fires on an arbitrary queue.
        // We hop back to MainActor before mutating @Published state.
        let collectionID = item.id
        imageManager.requestImage(
            for: keyAsset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                self?.thumbnails[collectionID] = image
            }
        }
    }

    // MARK: - Helpers

    private static func makeItem(from collection: PHAssetCollection) -> FCLAssetCollection? {
        guard let title = collection.localizedTitle, !title.isEmpty else { return nil }
        // Smart-album allow-list. User albums (`.album` / `.albumRegular`)
        // bypass this filter so the user's named folders keep surfacing
        // regardless of subtype.
        let subtype = collection.assetCollectionSubtype
        if collection.assetCollectionType == .smartAlbum,
           !allowedSmartAlbumSubtypes.contains(subtype) {
            return nil
        }
        // Count assets accurately (estimatedAssetCount is NSNotFound for smart albums).
        let count = PHAsset.fetchAssets(in: collection, options: nil).count
        // Skip empty albums.
        guard count > 0 else { return nil }
        return FCLAssetCollection(
            id: collection.localIdentifier,
            title: title,
            assetCount: count,
            subtype: subtype
        )
    }

    // MARK: - Lookup

    /// Returns the `PHAssetCollection` for the given identifier, or `nil` for
    /// the synthetic all-photos fallback.
    func phCollection(for id: String) -> PHAssetCollection? {
        let fetch = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [id],
            options: nil
        )
        return fetch.firstObject
    }

    // MARK: - Defaults

    /// The identifier of the preferred default collection, or `nil` when the
    /// spec's preferred default (`smartAlbumRecentlyAdded`) is not available
    /// on this device. A `nil` return instructs ``FCLGalleryDataSource`` to
    /// fall back to the flat all-photos fetch, which still yields a
    /// "Recents"-equivalent view ordered by creation date descending.
    var defaultCollectionID: String? {
        collections.first(where: { $0.subtype == .smartAlbumRecentlyAdded })?.id
    }
}

// MARK: - Preview Support

#if DEBUG
extension FCLAssetCollectionRegistry {
    /// Populates the registry with mock data suitable for Xcode Previews.
    /// Bypasses the real PhotoKit APIs which are unavailable in preview agents.
    func loadMockData(selecting selectedIndex: Int = 0) {
        let items: [(String, String, Int, PHAssetCollectionSubtype)] = [
            ("recents-id",    "Recents",    1392, .smartAlbumRecentlyAdded),
            ("videos-id",     "Videos",      74,  .smartAlbumVideos),
            ("selfies-id",    "Selfies",     54,  .smartAlbumSelfPortraits),
            ("livephotos-id", "Live Photos", 563, .smartAlbumLivePhotos),
            ("portrait-id",   "Portrait",    49,  .smartAlbumDepthEffect),
            ("panoramas-id",  "Panoramas",   12,  .smartAlbumPanoramas),
            ("screenshots-id","Screenshots", 88,  .smartAlbumScreenshots),
            ("vacation-id",   "Vacation 2024", 203, .albumRegular),
            ("family-id",     "Family",      87,  .albumRegular),
        ]
        collections = items.map { id, title, count, subtype in
            FCLAssetCollection(id: id, title: title, assetCount: count, subtype: subtype)
        }
        selectedCollectionID = collections.indices.contains(selectedIndex)
            ? collections[selectedIndex].id
            : collections.first?.id
    }
}
#endif

// MARK: - Previews

#if DEBUG
#Preview("Registry — loaded") {
    FCLAssetCollectionRegistryPreview()
}

private struct FCLAssetCollectionRegistryPreview: View {
    @StateObject private var registry = FCLAssetCollectionRegistry()

    var body: some View {
        List(registry.collections) { collection in
            HStack(spacing: 12) {
                if let thumb = registry.thumbnails[collection.id] {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FCLPalette.tertiarySystemFill)
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title).font(.body)
                    Text("\(collection.assetCount)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            registry.loadMockData()
        }
    }
}
#endif
#endif
