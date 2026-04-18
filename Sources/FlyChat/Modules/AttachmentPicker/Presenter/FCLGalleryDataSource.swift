#if canImport(UIKit)
import Foundation
import Photos
import UIKit

@MainActor
final class FCLGalleryDataSource: NSObject, ObservableObject {
    @Published private(set) var assets: PHFetchResult<PHAsset> = .init()
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private let imageManager = PHCachingImageManager()
    private let isVideoEnabled: Bool

    /// The collection to display. `nil` fetches all photos (flat camera-roll view
    /// used in `.limited` mode and as the "Recents" fallback when no smart album
    /// is available). Setting this property re-fetches assets immediately if the
    /// data source is already in an authorized state.
    var collectionID: String? {
        didSet {
            guard collectionID != oldValue,
                  authorizationStatus == .authorized || authorizationStatus == .limited
            else { return }
            fetchAssets()
        }
    }

    /// Whether the code is running inside an Xcode preview. Privacy-sensitive APIs
    /// (Photos, Camera) must not be called in this context because the preview agent
    /// lacks the required Info.plist usage descriptions and will crash with a TCC violation.
    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init(isVideoEnabled: Bool, collectionID: String? = nil) {
        self.isVideoEnabled = isVideoEnabled
        self.collectionID = collectionID
        super.init()
        guard !Self.isRunningInPreview else { return }
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccessAndFetch() {
        guard !Self.isRunningInPreview else { return }
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // Sync the published status even if no fetch can run yet — SwiftUI
        // views observing `authorizationStatus` should always see the latest
        // system reading.
        authorizationStatus = currentStatus
        if currentStatus == .authorized || currentStatus == .limited {
            fetchAssets()
            registerObserver()
            return
        }
        // `.notDetermined` is intentionally **not** handled here. The sole
        // authorization request path lives on ``FCLPhotoAuthorizationCoordinator``
        // so exactly one system prompt can ever fire, and its resolved status
        // propagates into this data source via ``FCLGalleryTabView``'s
        // `syncDataSourceAfterAuth()` once the user has chosen. Issuing a
        // second `PHPhotoLibrary.requestAuthorization(for:)` here would race
        // the coordinator's own request and could display two system dialogs
        // on cold launch.
        #if DEBUG
        // Defensive assertion: this data source must only be asked to fetch
        // after the coordinator has resolved `.notDetermined`. If a future
        // call site forgets to gate on the coordinator's status, surface the
        // misuse loudly in debug builds instead of silently doing nothing.
        if currentStatus == .notDetermined {
            assertionFailure(
                "FCLGalleryDataSource.requestAccessAndFetch called with status = .notDetermined. Authorization must be resolved by FCLPhotoAuthorizationCoordinator before the gallery data source fetches; calling this here would duplicate the system prompt."
            )
        }
        #endif
    }

    func thumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            completion(image)
        }
    }

    func fullSizeImage(for asset: PHAsset) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            imageManager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: FCLCompressionError.jpegEncodingFailed)
                }
            }
        }
    }

    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if isVideoEnabled {
            options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                            PHAssetMediaType.image.rawValue,
                                            PHAssetMediaType.video.rawValue)
        } else {
            options.predicate = NSPredicate(format: "mediaType == %d",
                                            PHAssetMediaType.image.rawValue)
        }

        // When a collectionID is set, scope the fetch to that collection.
        // Fall back to a flat all-photos fetch when nil (limited mode or Recents fallback).
        if let collectionID,
           let collection = phCollection(for: collectionID) {
            assets = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: options)
        }
    }

    // MARK: - Collection Lookup

    private func phCollection(for id: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [id],
            options: nil
        ).firstObject
    }

    private func registerObserver() {
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}

extension FCLGalleryDataSource: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let changes = changeInstance.changeDetails(for: self.assets) {
                self.assets = changes.fetchResultAfterChanges
            }
        }
    }
}
#endif
