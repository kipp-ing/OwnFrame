// AuthorizationTests.swift — the COMPLETE PhotoAuthorizationState matrix + its live transitions (spec 900, T027). Zero PhotoKit.
//
// Companion to PhotoLibraryProviderTests: that suite pins the per-cell statics it happened to
// touch; this suite closes the remaining data-model cells and — the real point of US3 — pins
// the TRANSITIONS. The provider re-reads authorization on EVERY call and never caches, so a
// mid-session downgrade/upgrade must change behavior on the same provider instance. That
// re-read is the contract under test here.

import Foundation
import Testing
import PhotoSourceKit
import PhotoLibraryTestSupport
@testable import PhotoLibraryKit

@Suite struct AuthorizationTests {

    // MARK: - Matrix cells not covered by PhotoLibraryProviderTests

    // Album source · assets(in:) · notDetermined → calm auth gate, gateway never asked.
    @Test func assetsForRegularCollectionUnderNotDeterminedThrowsAuthentication() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        gateway.setAssets([SourceAsset(id: "a1", kind: .image)], for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: "album-1") }

        #expect(failure?.isAuthentication == true)
        #expect(gateway.fetchAssetsCallCount(for: "album-1") == 0)
    }

    // Album source · assets(in:) · denied → calm auth gate, gateway never asked.
    @Test func assetsForRegularCollectionUnderDeniedThrowsAuthentication() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.denied)
        gateway.setAssets([SourceAsset(id: "a1", kind: .image)], for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: "album-1") }

        #expect(failure?.isAuthentication == true)
        #expect(gateway.fetchAssetsCallCount(for: "album-1") == 0)
    }

    // Selected-Photos source · assets(in:) · notDetermined → calm auth gate, pool never fetched.
    @Test func assetsForSelectedPhotosUnderNotDeterminedThrowsAuthentication() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: PhotoLibrarySource.selectedPhotosID) }

        #expect(failure?.isAuthentication == true)
        #expect(gateway.fetchGrantedAssetsCallCount == 0)
    }

    // Selected-Photos source · ensureReady() · full → ready (the pool equals the whole grant).
    @Test func ensureReadyForSelectedPhotosUnderFullIsOk() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: PhotoLibrarySource.selectedPhotosID)

        try await provider.ensureReady()  // must not throw
    }

    // Selected-Photos source · ensureReady() · notDetermined → calm auth gate.
    @Test func ensureReadyForSelectedPhotosUnderNotDeterminedThrowsAuthentication() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: PhotoLibrarySource.selectedPhotosID)

        let failure = await captureFailure { try await provider.ensureReady() }

        #expect(failure?.isAuthentication == true)
    }

    // Selected-Photos source · ensureReady() · denied → calm auth gate.
    @Test func ensureReadyForSelectedPhotosUnderDeniedThrowsAuthentication() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.denied)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: PhotoLibrarySource.selectedPhotosID)

        let failure = await captureFailure { try await provider.ensureReady() }

        #expect(failure?.isAuthentication == true)
    }

    // MARK: - Transition: full → limited downgrade (US3-4)

    /// Mid-session downgrade full → limited while serving an ALBUM source: readiness and asset
    /// fetches that worked a moment ago start failing `.authentication` on the SAME instance,
    /// and the now-forbidden album is not enumerated again (gate closes before the gateway).
    @Test func downgradeFullToLimitedFailsAlbumSourceMidSession() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let album = [SourceAsset(id: "a1", kind: .image), SourceAsset(id: "a2", kind: .image)]
        gateway.setAssets(album, for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album-1")

        // Full: both calls serve.
        try await provider.ensureReady()
        #expect(try await provider.assets(in: "album-1") == album)
        #expect(gateway.fetchAssetsCallCount(for: "album-1") == 1)

        // The user narrows to limited access from iOS Settings between calls.
        gateway.setAuthorization(.limited)

        let readyFailure = await captureFailure { try await provider.ensureReady() }
        #expect(readyFailure?.isAuthentication == true)
        let assetsFailure = await captureFailure { try await provider.assets(in: "album-1") }
        #expect(assetsFailure?.isAuthentication == true)
        // The forbidden album is not re-enumerated: still exactly the one full-access fetch.
        #expect(gateway.fetchAssetsCallCount(for: "album-1") == 1)
    }

    /// The same full → limited downgrade leaves a Selected-Photos provider serving: the
    /// granted-assets pool is the one source that survives narrowing to limited access.
    @Test func downgradeFullToLimitedKeepsSelectedPhotosServing() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let pool = [SourceAsset(id: "g1", kind: .image), SourceAsset(id: "g2", kind: .image)]
        gateway.setGrantedAssets(pool)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: PhotoLibrarySource.selectedPhotosID)

        try await provider.ensureReady()
        #expect(try await provider.assets(in: PhotoLibrarySource.selectedPhotosID) == pool)

        gateway.setAuthorization(.limited)

        try await provider.ensureReady()  // still ready under limited
        #expect(try await provider.assets(in: PhotoLibrarySource.selectedPhotosID) == pool)
        #expect(gateway.fetchGrantedAssetsCallCount == 2)
    }

    // MARK: - Transition: full → denied revoke while active (US3-3)

    /// Access revoked mid-slideshow (full → denied): both an album source and the
    /// Selected-Photos source fail with the typed `.authentication` — a calm gate, never a
    /// crash — on the same instances.
    @Test func revokeFullToDeniedFailsAlbumAndSelectedPhotos() async throws {
        let albumGateway = FakePhotoLibraryGateway()
        albumGateway.setAuthorization(.full)
        albumGateway.setAssets([SourceAsset(id: "a1", kind: .image)], for: "album-1")
        let albumProvider = PhotoLibraryProvider(gateway: albumGateway, collectionID: "album-1")

        let poolGateway = FakePhotoLibraryGateway()
        poolGateway.setAuthorization(.full)
        poolGateway.setGrantedAssets([SourceAsset(id: "g1", kind: .image)])
        let poolProvider = PhotoLibraryProvider(gateway: poolGateway, collectionID: PhotoLibrarySource.selectedPhotosID)

        try await albumProvider.ensureReady()
        try await poolProvider.ensureReady()

        // The user revokes Photos access entirely.
        albumGateway.setAuthorization(.denied)
        poolGateway.setAuthorization(.denied)

        #expect(await captureFailure { try await albumProvider.ensureReady() }?.isAuthentication == true)
        #expect(await captureFailure { try await albumProvider.assets(in: "album-1") }?.isAuthentication == true)
        #expect(await captureFailure { try await poolProvider.ensureReady() }?.isAuthentication == true)
        #expect(await captureFailure { try await poolProvider.assets(in: PhotoLibrarySource.selectedPhotosID) }?.isAuthentication == true)
    }

    // MARK: - Transition: limited → full upgrade

    /// Upgrade limited → full: a previously-refused album source becomes serviceable on the
    /// SAME provider instance — no new provider required, because authorization is re-read.
    @Test func upgradeLimitedToFullEnablesAlbumSourceSameInstance() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        let album = [SourceAsset(id: "a1", kind: .image)]
        gateway.setAssets(album, for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album-1")

        // Limited: an album source is refused.
        #expect(await captureFailure { try await provider.ensureReady() }?.isAuthentication == true)
        #expect(await captureFailure { try await provider.assets(in: "album-1") }?.isAuthentication == true)

        // The user grants full access.
        gateway.setAuthorization(.full)

        try await provider.ensureReady()  // now ready
        #expect(try await provider.assets(in: "album-1") == album)
    }

    // MARK: - Transition: collections() re-reads (full → limited must throw, not empty)

    /// `collections()` requires full and never caches it: a downgrade to limited turns a
    /// previously-served album list into the calm `.authentication` gate. Critically, limited
    /// must NEVER return an empty list as if the user simply had no albums — it must throw, so
    /// the gateway is not even asked after the downgrade.
    @Test func collectionsReReadsAuthorizationFullToLimited() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let albums = [SourceCollection(id: "album-1", title: "Iceland", assetCount: 42, coverAssetID: "c1")]
        gateway.setCollections(albums)
        let provider = PhotoLibraryProvider(gateway: gateway)

        #expect(try await provider.collections() == albums)
        #expect(gateway.fetchCollectionsCallCount == 1)

        gateway.setAuthorization(.limited)

        let failure = await captureFailure { try await provider.collections() }
        #expect(failure?.isAuthentication == true)
        // Not enumerated under limited: still exactly the one full-access fetch, no empty list.
        #expect(gateway.fetchCollectionsCallCount == 1)
    }

    // MARK: - SelectedPhotosSource (T028) — the single limited-mode pickable source

    /// The pool maps to one pickable collection: sentinel id, "Selected Photos" title,
    /// assetCount = whatever the gateway reports (all kinds — the engine filters later, not
    /// this surface), cover = the first granted asset.
    @Test func selectedPhotosCollectionMapsCountAndCoverFromGrantedPool() throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        gateway.setGrantedAssets([
            SourceAsset(id: "g1", kind: .image),
            SourceAsset(id: "g2", kind: .video),   // counted too: kinds are the engine's concern
            SourceAsset(id: "g3", kind: .image),
        ])

        let collection = try SelectedPhotosSource.collection(using: gateway)

        #expect(collection.id == PhotoLibrarySource.selectedPhotosID)
        #expect(collection.title == "Selected Photos")
        #expect(collection.assetCount == 3)
        #expect(collection.coverAssetID == "g1")
        #expect(gateway.fetchGrantedAssetsCallCount == 1)
    }

    /// Available under full as well (equals the whole grant) — same pickable shape.
    @Test func selectedPhotosCollectionIsAvailableUnderFull() throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setGrantedAssets([SourceAsset(id: "g1", kind: .image)])

        let collection = try SelectedPhotosSource.collection(using: gateway)

        #expect(collection.id == PhotoLibrarySource.selectedPhotosID)
        #expect(collection.assetCount == 1)
        #expect(collection.coverAssetID == "g1")
    }

    /// An empty grant is still an offerable source (the picker shows the row so the user can
    /// manage selection): assetCount 0, no cover.
    @Test func selectedPhotosCollectionEmptyPoolIsStillOfferable() throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        gateway.setGrantedAssets([])

        let collection = try SelectedPhotosSource.collection(using: gateway)

        #expect(collection.id == PhotoLibrarySource.selectedPhotosID)
        #expect(collection.title == "Selected Photos")
        #expect(collection.assetCount == 0)
        #expect(collection.coverAssetID == nil)
    }

    /// Denied → calm auth gate, pool never fetched (gate closes before the gateway).
    @Test func selectedPhotosCollectionUnderDeniedThrowsAuthentication() {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.denied)
        gateway.setGrantedAssets([SourceAsset(id: "g1", kind: .image)])

        let failure = captureSyncFailure { try SelectedPhotosSource.collection(using: gateway) }

        #expect(failure?.isAuthentication == true)
        #expect(gateway.fetchGrantedAssetsCallCount == 0)
    }

    /// notDetermined → calm auth gate, pool never fetched.
    @Test func selectedPhotosCollectionUnderNotDeterminedThrowsAuthentication() {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        gateway.setGrantedAssets([SourceAsset(id: "g1", kind: .image)])

        let failure = captureSyncFailure { try SelectedPhotosSource.collection(using: gateway) }

        #expect(failure?.isAuthentication == true)
        #expect(gateway.fetchGrantedAssetsCallCount == 0)
    }

    /// An opaque gateway error while fetching the pool surfaces as `.transient` (retryable),
    /// matching `PhotoLibraryProvider`'s error-mapping convention.
    @Test func selectedPhotosCollectionSurfacesOpaqueErrorAsTransient() {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        gateway.setGrantedAssetsError(MarkerError(tag: "icloud-fetch"))

        let failure = captureSyncFailure { try SelectedPhotosSource.collection(using: gateway) }

        #expect((failure?.transientUnderlying as? MarkerError) == MarkerError(tag: "icloud-fetch"))
    }
}

// MARK: - Test helpers

/// Captures a thrown `SourceFailure` from an async operation, recording an issue when the
/// operation unexpectedly succeeds or throws a non-`SourceFailure` error.
private func captureFailure<T>(
    _ operation: () async throws -> T
) async -> SourceFailure? {
    do {
        _ = try await operation()
        Issue.record("Expected a SourceFailure but the call succeeded")
        return nil
    } catch let failure as SourceFailure {
        return failure
    } catch {
        Issue.record("Expected a SourceFailure but got \(error)")
        return nil
    }
}

/// Synchronous sibling of `captureFailure` for the non-async `SelectedPhotosSource` surface.
private func captureSyncFailure<T>(
    _ operation: () throws -> T
) -> SourceFailure? {
    do {
        _ = try operation()
        Issue.record("Expected a SourceFailure but the call succeeded")
        return nil
    } catch let failure as SourceFailure {
        return failure
    } catch {
        Issue.record("Expected a SourceFailure but got \(error)")
        return nil
    }
}

private extension SourceFailure {
    var isAuthentication: Bool { if case .authentication = self { return true } else { return false } }
    var transientUnderlying: (any Error)? {
        if case .transient(let underlying) = self { return underlying } else { return nil }
    }
}

/// A distinctive non-`SourceFailure` error so transient mapping is assertable.
private struct MarkerError: Error, Equatable {
    let tag: String
}
