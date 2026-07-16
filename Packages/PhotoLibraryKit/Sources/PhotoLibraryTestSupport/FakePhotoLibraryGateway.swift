// FakePhotoLibraryGateway.swift — scriptable PhotoLibraryGateway for the provider unit tests
// and the cross-backend engine gate (spec 900, T014/T026). Zero PhotoKit.
//
// Promoted from the PhotoLibraryKit test target into the public `PhotoLibraryTestSupport`
// product so downstream suites (the SlideshowKit dual-backend gate, SC-900-03) can drive a
// real `PhotoLibraryProvider` over it — mirroring how `PhotoSourceTestSupport.StubPhotoSource`
// is shared. No behavior changed in the move, only access levels.

import Foundation
import PhotoSourceKit
import PhotoLibraryKit

/// A hand-scriptable `PhotoLibraryGateway`. Every call is counted and every result/error is
/// scriptable, so the pure-logic provider can be driven through the whole authorization matrix
/// — and the whole engine rotation — without ever touching PhotoKit. Lock-guarded so it is safe
/// to drive from parallel Swift Testing async tests (house pattern, mirrors `StubPhotoSource`).
public final class FakePhotoLibraryGateway: PhotoLibraryGateway, @unchecked Sendable {

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
        var presentManageSelectionCallCount = 0
    }

    private let lock = NSLock()
    private var state = State()

    public init() {}

    // MARK: - Scripting

    public func setAuthorization(_ status: PhotoAuthorizationState) {
        lock.withLock { state.authorization = status }
    }

    public func setRequestAuthorizationResult(_ status: PhotoAuthorizationState) {
        lock.withLock { state.requestAuthorizationResult = status }
    }

    public func setCollections(_ collections: [SourceCollection]) {
        lock.withLock { state.collections = collections; state.collectionsError = nil }
    }

    public func setCollectionsError(_ error: any Error) {
        lock.withLock { state.collectionsError = error }
    }

    public func setAssets(_ assets: [SourceAsset], for collectionID: String) {
        lock.withLock {
            state.assetsByCollectionID[collectionID] = assets
            state.assetsErrorByCollectionID[collectionID] = nil
        }
    }

    public func setAssetsError(_ error: any Error, for collectionID: String) {
        lock.withLock { state.assetsErrorByCollectionID[collectionID] = error }
    }

    public func setGrantedAssets(_ assets: [SourceAsset]) {
        lock.withLock { state.grantedAssets = assets; state.grantedAssetsError = nil }
    }

    public func setGrantedAssetsError(_ error: any Error) {
        lock.withLock { state.grantedAssetsError = error }
    }

    public func setImageData(_ data: Data, for assetID: String) {
        lock.withLock { state.imageDataByAssetID[assetID] = data; state.imageErrorByAssetID[assetID] = nil }
    }

    public func setImageError(_ error: any Error, for assetID: String) {
        lock.withLock { state.imageErrorByAssetID[assetID] = error }
    }

    public func setMetadata(_ metadata: AssetMetadata, for assetID: String) {
        lock.withLock { state.metadataByAssetID[assetID] = metadata; state.metadataErrorByAssetID[assetID] = nil }
    }

    public func setMetadataError(_ error: any Error, for assetID: String) {
        lock.withLock { state.metadataErrorByAssetID[assetID] = error }
    }

    // MARK: - PhotoLibraryGateway

    public func authorizationStatus() -> PhotoAuthorizationState {
        lock.withLock {
            state.authorizationStatusCallCount += 1
            return state.authorization
        }
    }

    public func requestAuthorization() async -> PhotoAuthorizationState {
        lock.withLock {
            state.requestAuthorizationCallCount += 1
            return state.requestAuthorizationResult
        }
    }

    public func fetchCollections() throws -> [SourceCollection] {
        try lock.withLock {
            state.fetchCollectionsCallCount += 1
            if let error = state.collectionsError { throw error }
            return state.collections
        }
    }

    public func fetchAssets(in collectionID: String) throws -> [SourceAsset] {
        try lock.withLock {
            state.fetchAssetsCallCountByCollectionID[collectionID, default: 0] += 1
            if let error = state.assetsErrorByCollectionID[collectionID] { throw error }
            return state.assetsByCollectionID[collectionID] ?? []
        }
    }

    public func fetchGrantedAssets() throws -> [SourceAsset] {
        try lock.withLock {
            state.fetchGrantedAssetsCallCount += 1
            if let error = state.grantedAssetsError { throw error }
            return state.grantedAssets
        }
    }

    public func requestImageData(assetID: String, fidelity: ImageFidelity) async throws -> Data {
        try lock.withLock {
            state.requestImageDataCallCount += 1
            if let error = state.imageErrorByAssetID[assetID] { throw error }
            return state.imageDataByAssetID[assetID] ?? Data("\(fidelity.rawValue):\(assetID)".utf8)
        }
    }

    public func fetchMetadata(assetID: String) throws -> AssetMetadata {
        try lock.withLock {
            state.fetchMetadataCallCount += 1
            if let error = state.metadataErrorByAssetID[assetID] { throw error }
            return state.metadataByAssetID[assetID]
                ?? AssetMetadata(capturedAt: nil, latitude: nil, longitude: nil, placeName: nil)
        }
    }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.withLock {
            state.setChangeHandlerCallCount += 1
            state.changeHandler = handler
        }
    }

    @MainActor
    public func presentManageSelection() {
        lock.withLock { state.presentManageSelectionCallCount += 1 }
    }

    // MARK: - Recorded call counts / observers

    public var authorizationStatusCallCount: Int { lock.withLock { state.authorizationStatusCallCount } }
    public var requestAuthorizationCallCount: Int { lock.withLock { state.requestAuthorizationCallCount } }
    public var fetchCollectionsCallCount: Int { lock.withLock { state.fetchCollectionsCallCount } }
    public func fetchAssetsCallCount(for collectionID: String) -> Int {
        lock.withLock { state.fetchAssetsCallCountByCollectionID[collectionID, default: 0] }
    }
    public var fetchGrantedAssetsCallCount: Int { lock.withLock { state.fetchGrantedAssetsCallCount } }
    public var requestImageDataCallCount: Int { lock.withLock { state.requestImageDataCallCount } }
    public var fetchMetadataCallCount: Int { lock.withLock { state.fetchMetadataCallCount } }
    public var setChangeHandlerCallCount: Int { lock.withLock { state.setChangeHandlerCallCount } }
    public var presentManageSelectionCallCount: Int { lock.withLock { state.presentManageSelectionCallCount } }
    public var capturedChangeHandler: (@Sendable () -> Void)? { lock.withLock { state.changeHandler } }

    /// Invokes the captured change handler, mimicking a PhotoKit library-change callback.
    public func fireChange() {
        let handler = lock.withLock { state.changeHandler }
        handler?()
    }
}
