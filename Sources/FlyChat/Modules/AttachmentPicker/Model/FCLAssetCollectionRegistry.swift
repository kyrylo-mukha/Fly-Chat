#if canImport(UIKit)
import Photos
import UIKit
import SwiftUI

// MARK: - FCLAssetCollection

/// A value-type snapshot of a single `PHAssetCollection`.
///
/// Thumbnails are published separately on `FCLAssetCollectionRegistry` to avoid
/// sending a non-Sendable type across isolation boundaries.
struct FCLAssetCollection: Identifiable, Equatable {
    /// Stable identifier matching `PHAssetCollection.localIdentifier`.
    let id: String
    /// Localized title shown in the collection list.
    let title: String
    /// Precise asset count fetched at construction time.
    let assetCount: Int
    /// The underlying subtype, used to prioritize Recents.
    let subtype: PHAssetCollectionSubtype

    static func == (lhs: FCLAssetCollection, rhs: FCLAssetCollection) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - FCLAssetCollectionRegistry

/// Discovers, orders, and thumbnail-caches the user's photo collections.
///
/// Call `load()` once after `.authorized` status is confirmed. Not safe to call
/// in `.limited` mode — the collection selector is hidden in that state.
@MainActor
final class FCLAssetCollectionRegistry: ObservableObject {

    // MARK: - Published State

    /// Ordered list: Recents first, then remaining smart albums, then user albums.
    @Published private(set) var collections: [FCLAssetCollection] = []

    /// Thumbnails keyed by `FCLAssetCollection.id`.
    @Published private(set) var thumbnails: [String: UIImage] = [:]

    /// Currently selected collection. `nil` means the flat all-photos fallback.
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

    /// Smart-album subtypes surfaced in the collection selector. Subtypes outside
    /// this set (e.g. `smartAlbumAllHidden`) are filtered during discovery.
    private static let allowedSmartAlbumSubtypes: Set<PHAssetCollectionSubtype> = [
        .smartAlbumRecentlyAdded,
        .smartAlbumFavorites,
        .smartAlbumVideos,
        .smartAlbumPanoramas,
        .smartAlbumScreenshots,
        .smartAlbumDepthEffect,     // "Portrait" in the Photos app sidebar
        .smartAlbumLivePhotos,
        .smartAlbumSelfPortraits,
        .smartAlbumBursts,
        .smartAlbumTimelapses
    ]

    /// Discovers all collections and preloads key-asset thumbnails. Idempotent.
    func load() {
        guard !Self.isRunningInPreview, !didLoad else { return }
        didLoad = true

        var result: [FCLAssetCollection] = []

        // Smart albums in system order; makeItem(from:) filters to allowedSmartAlbumSubtypes.
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

        // User albums in default (creation-date) order.
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

        // Promote Recents to index 0 when present; otherwise leave selectedCollectionID
        // nil so the data source falls back to a flat all-photos fetch.
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
        let subtype = collection.assetCollectionSubtype
        if collection.assetCollectionType == .smartAlbum,
           !allowedSmartAlbumSubtypes.contains(subtype) {
            return nil
        }
        let count = PHAsset.fetchAssets(in: collection, options: nil).count
        guard count > 0 else { return nil }
        return FCLAssetCollection(
            id: collection.localIdentifier,
            title: title,
            assetCount: count,
            subtype: subtype
        )
    }

    // MARK: - Lookup

    /// Returns the `PHAssetCollection` for the given identifier, or `nil`.
    func phCollection(for id: String) -> PHAssetCollection? {
        let fetch = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [id],
            options: nil
        )
        return fetch.firstObject
    }

    // MARK: - Defaults

    /// Identifier of the Recents smart album, or `nil` when unavailable.
    var defaultCollectionID: String? {
        collections.first(where: { $0.subtype == .smartAlbumRecentlyAdded })?.id
    }
}

// MARK: - Preview Support

#if DEBUG
extension FCLAssetCollectionRegistry {
    /// Populates the registry with mock data for Xcode Previews.
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
