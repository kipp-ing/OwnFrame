// FakePhotoLibraryGateway.swift — scriptable PhotoLibraryGateway for the provider unit tests (spec 900, T014). Zero PhotoKit.

import Foundation
import PhotoSourceKit
import PhotoLibraryKit

/// A hand-scriptable `PhotoLibraryGateway` for `PhotoLibraryProviderTests`. Every call is
/// counted and every result/error is scriptable, so the pure-logic provider can be driven
/// through the whole authorization matrix without ever touching PhotoKit. Lock-guarded so
/// it is safe to drive from parallel Swift Testing async tests (house pattern, mirrors
/// `StubPhotoSource`).
final class FakePhotoLibraryGateway: PhotoLibraryGateway, @unchecked Sendable {

    private struct State {
        // Scripted results
        var authorization: PhotoAuthorizationState = .full
        var requestAuthorizationResult: PhotoAuthorizationState = .full
        var collections: [SourceCollection] = []
        var assetsByCollectionID: [String: [SourceAsset]] = [:]
        var grantedAssets: [SourceAsset] = []
        var imageDataByAssetID: [String: Data] = [:]
        var metadataByAssetID: [String: AssetMetadata] = [:]
        var changeHandler: (@Sendable () -> Void)?

        // Scripted errors
        var collectionsError: (any Error)?
        var assetsErrorByCollectionID: [String: any Error] = [:]
        var grantedAssetsError: (any Error)?
        var imageErrorByAssetID: [String: any Error] = [:]
        var metadataErrorByAssetID: [String: any Error] = [:]

        // Recorded call counts
        var authorizationStatusCallCount = 0
        var requestAuthorizationCallCount = 0
        var fetchCollectionsCallCount = 0
        var fetchAssetsCallCountByCollectionID: [String: Int] = [:]
        var fetchGrantedAssetsCallCount = 0
        var requestImageDataCallCount = 0
        var fetchMetadataCallCount = 0
        var setChangeHandlerCallCount = 0
    }

    private let lock = NSLock()
    private var state = State()

    init() {}

    // MARK: - Scripting

    func setAuthorization(_ status: PhotoAuthorizationState) {
        lock.withLock { state.authorization = status }
    }

    func setRequestAuthorizationResult(_ status: PhotoAuthorizationState) {
        lock.withLock { state.requestAuthorizationResult = status }
    }

    func setCollections(_ collections: [SourceCollection]) {
        lock.withLock { state.collections = collections; state.collectionsError = nil }
    }

    func setCollectionsError(_ error: any Error) {
        lock.withLock { state.collectionsError = error }
    }

    func setAssets(_ assets: [SourceAsset], for collectionID: String) {
        lock.withLock {
            state.assetsByCollectionID[collectionID] = assets
            state.assetsErrorByCollectionID[collectionID] = nil
        }
    }

    func setAssetsError(_ error: any Error, for collectionID: String) {
        lock.withLock { state.assetsErrorByCollectionID[collectionID] = error }
    }

    func setGrantedAssets(_ assets: [SourceAsset]) {
        lock.withLock { state.grantedAssets = assets; state.grantedAssetsError = nil }
    }

    func setGrantedAssetsError(_ error: any Error) {
        lock.withLock { state.grantedAssetsError = error }
    }

    func setImageData(_ data: Data, for assetID: String) {
        lock.withLock { state.imageDataByAssetID[assetID] = data; state.imageErrorByAssetID[assetID] = nil }
    }

    func setImageError(_ error: any Error, for assetID: String) {
        lock.withLock { state.imageErrorByAssetID[assetID] = error }
    }

    func setMetadata(_ metadata: AssetMetadata, for assetID: String) {
        lock.withLock { state.metadataByAssetID[assetID] = metadata; state.metadataErrorByAssetID[assetID] = nil }
    }

    func setMetadataError(_ error: any Error, for assetID: String) {
        lock.withLock { state.metadataErrorByAssetID[assetID] = error }
    }

    // MARK: - PhotoLibraryGateway

    func authorizationStatus() -> PhotoAuthorizationState {
        lock.withLock {
            state.authorizationStatusCallCount += 1
            return state.authorization
        }
    }

    func requestAuthorization() async -> PhotoAuthorizationState {
        lock.withLock {
            state.requestAuthorizationCallCount += 1
            return state.requestAuthorizationResult
        }
    }

    func fetchCollections() throws -> [SourceCollection] {
        try lock.withLock {
            state.fetchCollectionsCallCount += 1
            if let error = state.collectionsError { throw error }
            return state.collections
        }
    }

    func fetchAssets(in collectionID: String) throws -> [SourceAsset] {
        try lock.withLock {
            state.fetchAssetsCallCountByCollectionID[collectionID, default: 0] += 1
            if let error = state.assetsErrorByCollectionID[collectionID] { throw error }
            return state.assetsByCollectionID[collectionID] ?? []
        }
    }

    func fetchGrantedAssets() throws -> [SourceAsset] {
        try lock.withLock {
            state.fetchGrantedAssetsCallCount += 1
            if let error = state.grantedAssetsError { throw error }
            return state.grantedAssets
        }
    }

    func requestImageData(assetID: String, fidelity: ImageFidelity) async throws -> Data {
        try lock.withLock {
            state.requestImageDataCallCount += 1
            if let error = state.imageErrorByAssetID[assetID] { throw error }
            return state.imageDataByAssetID[assetID] ?? Data("\(fidelity.rawValue):\(assetID)".utf8)
        }
    }

    func fetchMetadata(assetID: String) throws -> AssetMetadata {
        try lock.withLock {
            state.fetchMetadataCallCount += 1
            if let error = state.metadataErrorByAssetID[assetID] { throw error }
            return state.metadataByAssetID[assetID]
                ?? AssetMetadata(capturedAt: nil, latitude: nil, longitude: nil, placeName: nil)
        }
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.withLock {
            state.setChangeHandlerCallCount += 1
            state.changeHandler = handler
        }
    }

    // MARK: - Recorded call counts / observers

    var authorizationStatusCallCount: Int { lock.withLock { state.authorizationStatusCallCount } }
    var requestAuthorizationCallCount: Int { lock.withLock { state.requestAuthorizationCallCount } }
    var fetchCollectionsCallCount: Int { lock.withLock { state.fetchCollectionsCallCount } }
    func fetchAssetsCallCount(for collectionID: String) -> Int {
        lock.withLock { state.fetchAssetsCallCountByCollectionID[collectionID, default: 0] }
    }
    var fetchGrantedAssetsCallCount: Int { lock.withLock { state.fetchGrantedAssetsCallCount } }
    var requestImageDataCallCount: Int { lock.withLock { state.requestImageDataCallCount } }
    var fetchMetadataCallCount: Int { lock.withLock { state.fetchMetadataCallCount } }
    var setChangeHandlerCallCount: Int { lock.withLock { state.setChangeHandlerCallCount } }
    var capturedChangeHandler: (@Sendable () -> Void)? { lock.withLock { state.changeHandler } }

    /// Invokes the captured change handler, mimicking a PhotoKit library-change callback.
    func fireChange() {
        let handler = lock.withLock { state.changeHandler }
        handler?()
    }
}
