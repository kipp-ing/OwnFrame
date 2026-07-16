//
//  StubPhotoSource.swift
//  PhotoSourceTestSupport
//
//  900 — the scriptable `PhotoSourceProviding` fake for the engine suites, replacing
//  `StubImmichAPI` (R1). Feature-parity with it: per-call scripted results and errors,
//  an optional artificial delay, and recorded call counts / arguments. Lock-guarded so
//  it is safe to drive from parallel Swift Testing async tests.
//

import Foundation
import PhotoSourceKit

/// A hand-scriptable `PhotoSourceProviding` for downstream suites.
///
/// Migration map from `StubImmichAPI`:
/// `setAssets(_:for:)` → same; `setPreviewData`/`setOriginalData` → `setImageData(_:for:fidelity:)`
/// with `.preview`/`.original`; `serverVersion` gate → `setEnsureReadyError`; `*CallCount`
/// accessors carry over one-for-one.
public final class StubPhotoSource: PhotoSourceProviding, @unchecked Sendable {

    /// Keys image scripting by asset + tier. A `nil` fidelity entry is the per-asset
    /// fallback that answers any tier the exact `(asset, fidelity)` slot doesn't.
    private struct ImageKey: Hashable {
        let assetID: String
        let fidelity: ImageFidelity?
    }

    private struct State {
        // Scripted results
        var collections: [SourceCollection] = []
        var assetsByCollectionID: [String: [SourceAsset]] = [:]
        var imageDataByKey: [ImageKey: Data] = [:]
        var metadataByAssetID: [String: AssetMetadata] = [:]

        // Scripted errors
        var ensureReadyError: (any Error)?
        var collectionsError: (any Error)?
        var assetsErrorByCollectionID: [String: any Error] = [:]
        var imageErrorByKey: [ImageKey: any Error] = [:]
        var metadataErrorByAssetID: [String: any Error] = [:]

        // Behavior knobs
        var artificialDelay: Duration?

        // Recorded call counts / arguments
        var ensureReadyCallCount = 0
        var collectionsCallCount = 0
        var assetsCallCount = 0
        var assetsCallCountByCollectionID: [String: Int] = [:]
        var imageDataCallCount = 0
        var imageDataCallCountByAssetID: [String: Int] = [:]
        var metadataCallCount = 0
        var metadataCallCountByAssetID: [String: Int] = [:]
        var recordedImageRequests: [(assetID: String, fidelity: ImageFidelity)] = []
    }

    private let lock = NSLock()
    private var state = State()

    public init() {}

    // MARK: - Scripting: results

    public func setCollections(_ collections: [SourceCollection]) {
        lock.withLock {
            state.collections = collections
            state.collectionsError = nil
        }
    }

    public func setAssets(_ assets: [SourceAsset], for collectionID: String) {
        lock.withLock {
            state.assetsByCollectionID[collectionID] = assets
            state.assetsErrorByCollectionID[collectionID] = nil
        }
    }

    /// Scripts image bytes for an asset. Pass `fidelity` to answer only that tier; pass
    /// `nil` (default) to answer every tier not covered by a more specific entry.
    public func setImageData(_ data: Data, for assetID: String, fidelity: ImageFidelity? = nil) {
        let key = ImageKey(assetID: assetID, fidelity: fidelity)
        lock.withLock {
            state.imageDataByKey[key] = data
            state.imageErrorByKey[key] = nil
        }
    }

    public func setMetadata(_ metadata: AssetMetadata, for assetID: String) {
        lock.withLock {
            state.metadataByAssetID[assetID] = metadata
            state.metadataErrorByAssetID[assetID] = nil
        }
    }

    // MARK: - Scripting: errors

    public func setEnsureReadyError(_ error: any Error) {
        lock.withLock { state.ensureReadyError = error }
    }

    public func setCollectionsError(_ error: any Error) {
        lock.withLock {
            state.collectionsError = error
            state.collections = []
        }
    }

    public func setAssetsError(_ error: any Error, for collectionID: String) {
        lock.withLock {
            state.assetsErrorByCollectionID[collectionID] = error
            state.assetsByCollectionID[collectionID] = nil
        }
    }

    public func setImageError(_ error: any Error, for assetID: String, fidelity: ImageFidelity? = nil) {
        let key = ImageKey(assetID: assetID, fidelity: fidelity)
        lock.withLock {
            state.imageErrorByKey[key] = error
            state.imageDataByKey[key] = nil
        }
    }

    public func setMetadataError(_ error: any Error, for assetID: String) {
        lock.withLock {
            state.metadataErrorByAssetID[assetID] = error
            state.metadataByAssetID[assetID] = nil
        }
    }

    // MARK: - Scripting: behavior

    /// Injects an artificial delay before each call returns (default: none). Lets suites
    /// exercise slow-source / prefetch timing without a real backend.
    public func setArtificialDelay(_ delay: Duration?) {
        lock.withLock { state.artificialDelay = delay }
    }

    // MARK: - PhotoSourceProviding

    public func ensureReady() async throws {
        try await applyDelay()
        try lock.withLock {
            state.ensureReadyCallCount += 1
            if let error = state.ensureReadyError { throw error }
        }
    }

    public func collections() async throws -> [SourceCollection] {
        try await applyDelay()
        return try lock.withLock {
            state.collectionsCallCount += 1
            if let error = state.collectionsError { throw error }
            return state.collections
        }
    }

    public func assets(in collectionID: String) async throws -> [SourceAsset] {
        try await applyDelay()
        return try lock.withLock {
            state.assetsCallCount += 1
            state.assetsCallCountByCollectionID[collectionID, default: 0] += 1
            if let error = state.assetsErrorByCollectionID[collectionID] { throw error }
            return state.assetsByCollectionID[collectionID] ?? []
        }
    }

    public func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data {
        try await applyDelay()
        return try lock.withLock {
            state.imageDataCallCount += 1
            state.imageDataCallCountByAssetID[assetID, default: 0] += 1
            state.recordedImageRequests.append((assetID, fidelity))

            let exact = ImageKey(assetID: assetID, fidelity: fidelity)
            let fallback = ImageKey(assetID: assetID, fidelity: nil)

            if let error = state.imageErrorByKey[exact] ?? state.imageErrorByKey[fallback] {
                throw error
            }
            if let data = state.imageDataByKey[exact] ?? state.imageDataByKey[fallback] {
                return data
            }
            // Deterministic default so callers that don't script bytes still get stable,
            // asset-distinct data (mirrors StubImmichAPI's `Data(assetID.utf8)` default).
            return Data("\(fidelity.rawValue):\(assetID)".utf8)
        }
    }

    public func metadata(for assetID: String) async throws -> AssetMetadata {
        try await applyDelay()
        return try lock.withLock {
            state.metadataCallCount += 1
            state.metadataCallCountByAssetID[assetID, default: 0] += 1
            if let error = state.metadataErrorByAssetID[assetID] { throw error }
            return state.metadataByAssetID[assetID]
                ?? AssetMetadata(capturedAt: nil, latitude: nil, longitude: nil, placeName: nil)
        }
    }

    // MARK: - Recorded call counts / arguments

    public var ensureReadyCallCount: Int { lock.withLock { state.ensureReadyCallCount } }
    public var collectionsCallCount: Int { lock.withLock { state.collectionsCallCount } }

    public var assetsCallCount: Int { lock.withLock { state.assetsCallCount } }
    public func assetsCallCount(for collectionID: String) -> Int {
        lock.withLock { state.assetsCallCountByCollectionID[collectionID, default: 0] }
    }

    public var imageDataCallCount: Int { lock.withLock { state.imageDataCallCount } }
    public func imageDataCallCount(for assetID: String) -> Int {
        lock.withLock { state.imageDataCallCountByAssetID[assetID, default: 0] }
    }

    /// Every `imageData(for:fidelity:)` request in call order — argument capture for
    /// suites asserting which tier the engine prefetched.
    public var recordedImageRequests: [(assetID: String, fidelity: ImageFidelity)] {
        lock.withLock { state.recordedImageRequests }
    }

    public var metadataCallCount: Int { lock.withLock { state.metadataCallCount } }
    public func metadataCallCount(for assetID: String) -> Int {
        lock.withLock { state.metadataCallCountByAssetID[assetID, default: 0] }
    }

    // MARK: - Private

    private func applyDelay() async throws {
        let delay = lock.withLock { state.artificialDelay }
        if let delay { try await Task.sleep(for: delay) }
    }
}
