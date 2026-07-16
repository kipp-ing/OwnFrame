// PHKitGateway.swift — the ONLY file in this package that imports Photos (900 R4, FR-900-13).

// The whole adapter is iOS-only: the package also builds for macOS so the logic layer's
// host tests run without a simulator, and on that platform this file compiles away.
#if canImport(Photos) && canImport(UIKit)

import Foundation
import Photos
import PhotoSourceKit
import UIKit

/// The real PhotoKit seam: authorization via the access-level-aware `.readWrite` API only
/// (R5 — the legacy no-argument API reports limited as authorized and is never used here),
/// user albums + iCloud Shared Albums, windowed asset enumeration (descriptors only, R9),
/// final-quality image delivery with network access allowed and a degraded-delivery guard
/// (R6, FR-900-06/07), and library change observation (FR-900-09).
///
/// Deliberately thin: no policy, no state beyond the change observer — every decision lives
/// in `PhotoLibraryProvider`, which is what the unit suite exercises against the fake.
public final class PHKitGateway: NSObject, PhotoLibraryGateway, @unchecked Sendable {

    // Guarded by `handlerLock`; PhotoKit calls `photoLibraryDidChange` off-main.
    private let handlerLock = NSLock()
    private var changeHandler: (@Sendable () -> Void)?
    private var isObserverRegistered = false

    public override init() {
        super.init()
    }

    deinit {
        if isObserverRegistered {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    // MARK: - Authorization (R5)

    public func authorizationStatus() -> PhotoAuthorizationState {
        Self.state(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAuthorization() async -> PhotoAuthorizationState {
        Self.state(from: await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    private static func state(from status: PHAuthorizationStatus) -> PhotoAuthorizationState {
        switch status {
        case .authorized: .full
        case .limited: .limited
        // .restricted (parental controls / MDM) grants no read access — denied semantics.
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    // MARK: - Collections (FR-900-03, R9)

    public func fetchCollections() throws -> [SourceCollection] {
        var collections: [SourceCollection] = []
        // User albums first, iCloud Shared Albums second — the picker's search handles order.
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )
        let sharedAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumCloudShared, options: nil
        )
        for result in [userAlbums, sharedAlbums] {
            result.enumerateObjects { collection, _, _ in
                collections.append(Self.sourceCollection(from: collection))
            }
        }
        return collections
    }

    private static func sourceCollection(from collection: PHAssetCollection) -> SourceCollection {
        // R9: lazy counts — estimatedAssetCount is allowed to be rough; NSNotFound falls
        // back to a real (image-only) count fetch, cover to the first asset.
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let firstAsset = PHAsset.fetchAssets(in: collection, options: fetchOptions).firstObject

        var count = collection.estimatedAssetCount
        if count == NSNotFound {
            count = PHAsset.fetchAssets(in: collection, options: nil).count
        }

        return SourceCollection(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "Untitled",
            assetCount: count,
            coverAssetID: firstAsset?.localIdentifier
        )
    }

    // MARK: - Assets (descriptors only — R9)

    public func fetchAssets(in collectionID: String) throws -> [SourceAsset] {
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [collectionID], options: nil
        )
        guard let collection = collections.firstObject else {
            // Deleted, unshared, or migrated out of PhotoKit's view (iOS 27 upgrade) —
            // the provider turns this into the FR-900-16 vanish state.
            throw PhotoLibraryGatewayError.collectionNotFound
        }
        return Self.sourceAssets(from: PHAsset.fetchAssets(in: collection, options: nil))
    }

    public func fetchGrantedAssets() throws -> [SourceAsset] {
        // The granted pool: everything PhotoKit exposes to this app — under limited access
        // that is exactly the user's selection; under full access, the whole library.
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return Self.sourceAssets(from: PHAsset.fetchAssets(with: options))
    }

    private static func sourceAssets(from result: PHFetchResult<PHAsset>) -> [SourceAsset] {
        // Descriptors only (id + kind): tiny even at 10k assets. PHFetchResult itself pages
        // its backing store; enumerate never materializes image data (R9).
        var assets: [SourceAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(SourceAsset(id: asset.localIdentifier, kind: Self.kind(of: asset)))
        }
        return assets
    }

    private static func kind(of asset: PHAsset) -> MediaKind {
        switch asset.mediaType {
        // Live Photos are mediaType .image — their still renders via the normal image
        // request, exactly the FR-900-08 semantics.
        case .image: .image
        case .video: .video
        default: .other
        }
    }

    // MARK: - Image data (R6, FR-900-06/07)

    public func requestImageData(assetID: String, fidelity: ImageFidelity) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            // A vanished single asset is a per-photo skip, not a source-level failure.
            throw SourceFailure.transient(underlying: PhotoLibraryGatewayError.collectionNotFound)
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true          // FR-900-06: iCloud originals on demand
        options.deliveryMode = .highQualityFormat      // R6: single final-quality delivery
        options.isSynchronous = false
        options.resizeMode = .exact

        switch fidelity {
        case .original:
            return try await requestOriginalData(for: asset, options: options)
        case .preview:
            // Screen-class target: long edge ≈ 2048 keeps parity with Immich previews and
            // the legacy shared-album ceiling (FR-900-15) without decoding full originals.
            return try await requestEncodedImage(for: asset, target: CGSize(width: 2048, height: 2048), options: options)
        case .thumbnail:
            return try await requestEncodedImage(for: asset, target: CGSize(width: 400, height: 400), options: options)
        }
    }

    private func requestOriginalData(for asset: PHAsset, options: PHImageRequestOptions) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                // R6 guard: the degraded-delivery decision is the host-tested ImageDeliveryRules
                // (FR-900-07). With .highQualityFormat the final callback is the only one, so a
                // degraded frame is simply dropped and the continuation waits for the final one.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                switch ImageDeliveryRules.decision(isDegraded: isDegraded, hasPayload: data != nil) {
                case .ignore:
                    return
                case .deliver:
                    // .deliver implies a non-nil payload; the guard keeps this force-unwrap-free.
                    if let data { continuation.resume(returning: data) }
                case .fail:
                    let underlying = info?[PHImageErrorKey] as? NSError
                        ?? NSError(domain: "PHKitGateway", code: 1)
                    continuation.resume(throwing: SourceFailure.transient(underlying: underlying))
                }
            }
        }
    }

    private func requestEncodedImage(for asset: PHAsset, target: CGSize, options: PHImageRequestOptions) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: target, contentMode: .aspectFit, options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                let data = image?.jpegData(compressionQuality: 0.9)
                switch ImageDeliveryRules.decision(isDegraded: isDegraded, hasPayload: data != nil) {
                case .ignore:
                    return
                case .deliver:
                    if let data { continuation.resume(returning: data) }
                case .fail:
                    let underlying = info?[PHImageErrorKey] as? NSError
                        ?? NSError(domain: "PHKitGateway", code: 2)
                    continuation.resume(throwing: SourceFailure.transient(underlying: underlying))
                }
            }
        }
    }

    // MARK: - Metadata (FR-900-10, R7 — no geocoding, coordinates only)

    public func fetchMetadata(assetID: String) throws -> AssetMetadata {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            throw PhotoLibraryGatewayError.collectionNotFound
        }
        return AssetMetadata(
            capturedAt: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            placeName: nil // R7: no reverse geocoding — nothing leaves the device (FR-900-14)
        )
    }

    // MARK: - Change observation (FR-900-09)

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        handlerLock.lock()
        changeHandler = handler
        let needsRegistration = handler != nil && !isObserverRegistered
        let needsUnregistration = handler == nil && isObserverRegistered
        if needsRegistration { isObserverRegistered = true }
        if needsUnregistration { isObserverRegistered = false }
        handlerLock.unlock()

        if needsRegistration {
            PHPhotoLibrary.shared().register(self)
        } else if needsUnregistration {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }
}

extension PHKitGateway: PHPhotoLibraryChangeObserver {
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Coarse by design: any library change nudges the engine's existing refresh path,
        // which re-fetches and reconciles (topic 310 rules). No per-change diffing here.
        handlerLock.lock()
        let handler = changeHandler
        handlerLock.unlock()
        handler?()
    }
}

#endif
