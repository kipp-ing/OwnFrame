// PhotoLibraryProviderTests.swift — pure-logic PhotoLibraryProvider behavior over a scriptable gateway (spec 900, T014). Zero PhotoKit.

import Foundation
import Testing
import PhotoSourceKit
import PhotoLibraryTestSupport
@testable import PhotoLibraryKit

@Suite struct PhotoLibraryProviderTests {

    // MARK: - Collections pass-through (full access)

    @Test func collectionsPassThroughUnderFullAccess() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let expected = [
            SourceCollection(id: "album-1", title: "Iceland", assetCount: 42, coverAssetID: "c1"),
            SourceCollection(id: "album-2", title: "Shared", assetCount: 7, coverAssetID: nil),
        ]
        gateway.setCollections(expected)
        let provider = PhotoLibraryProvider(gateway: gateway)

        let result = try await provider.collections()

        #expect(result == expected)
        #expect(gateway.fetchCollectionsCallCount == 1)
    }

    @Test func collectionsThrowsAuthenticationUnderLimited() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        gateway.setCollections([SourceCollection(id: "album-1", title: "Iceland", assetCount: 1, coverAssetID: nil)])
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.collections() }

        #expect(failure?.isAuthentication == true)
        // Not enumerable under limited: the gateway must not even be asked.
        #expect(gateway.fetchCollectionsCallCount == 0)
    }

    @Test func collectionsThrowsAuthenticationUnderDenied() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.denied)
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.collections() }

        #expect(failure?.isAuthentication == true)
        #expect(gateway.fetchCollectionsCallCount == 0)
    }

    @Test func collectionsThrowsAuthenticationUnderNotDetermined() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.collections() }

        #expect(failure?.isAuthentication == true)
        #expect(gateway.fetchCollectionsCallCount == 0)
    }

    @Test func collectionsGatewayErrorSurfacesAsTransient() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setCollectionsError(MarkerError(tag: "icloud-throttle"))
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.collections() }

        #expect((failure?.transientUnderlying as? MarkerError) == MarkerError(tag: "icloud-throttle"))
    }

    // MARK: - assets(in:) pass-through

    @Test func assetsPassThroughForRegularCollectionUnderFull() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let expected = [SourceAsset(id: "a1", kind: .image), SourceAsset(id: "a2", kind: .video)]
        gateway.setAssets(expected, for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let result = try await provider.assets(in: "album-1")

        #expect(result == expected)
        #expect(gateway.fetchAssetsCallCount(for: "album-1") == 1)
        #expect(gateway.fetchGrantedAssetsCallCount == 0)
    }

    @Test func assetsForMissingCollectionSurfacesNotFound() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setAssetsError(PhotoLibraryGatewayError.collectionNotFound, for: "gone")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: "gone") }

        #expect(failure?.isNotFound == true)
    }

    @Test func assetsGatewayErrorSurfacesAsTransient() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setAssetsError(MarkerError(tag: "icloud-fetch"), for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: "album-1") }

        #expect((failure?.transientUnderlying as? MarkerError) == MarkerError(tag: "icloud-fetch"))
    }

    @Test func assetsPassesAnExistingSourceFailureThroughUnchanged() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setAssetsError(SourceFailure.permanent(underlying: MarkerError(tag: "decode")), for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: "album-1") }

        // Not re-wrapped as .transient — an already-typed SourceFailure survives verbatim.
        #expect((failure?.permanentUnderlying as? MarkerError) == MarkerError(tag: "decode"))
    }

    // MARK: - ensureReady() authorization gate

    @Test func ensureReadyOkUnderFullAccess() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album-1")

        try await provider.ensureReady()  // must not throw

        #expect(gateway.authorizationStatusCallCount == 1)
    }

    @Test func ensureReadyThrowsAuthenticationUnderNotDetermined() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album-1")

        let failure = await captureFailure { try await provider.ensureReady() }

        #expect(failure?.isAuthentication == true)
    }

    @Test func ensureReadyThrowsAuthenticationUnderDenied() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.denied)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album-1")

        let failure = await captureFailure { try await provider.ensureReady() }

        #expect(failure?.isAuthentication == true)
    }

    // @covers FR-900-04
    @Test func ensureReadyUnderLimitedThrowsAuthenticationForRegularCollection() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album-1")

        let failure = await captureFailure { try await provider.ensureReady() }

        #expect(failure?.isAuthentication == true)
    }

    // @covers FR-900-04
    @Test func ensureReadyUnderLimitedIsOkForSelectedPhotosSource() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: PhotoLibrarySource.selectedPhotosID)

        try await provider.ensureReady()  // the granted-assets pool stays serviceable
    }

    @Test func ensureReadyReReadsAuthorizationOnEveryCall() async {
        // R5: authorization is re-evaluated on every ensureReady(), not cached for the session.
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album-1")

        let firstFailure = await captureFailure { try await provider.ensureReady() }
        #expect(firstFailure?.isAuthentication == true)

        // The user grants access between the two readiness checks.
        gateway.setAuthorization(.full)
        var secondCallThrew = false
        do { try await provider.ensureReady() } catch { secondCallThrew = true }

        #expect(secondCallThrew == false)
        #expect(gateway.authorizationStatusCallCount == 2)
    }

    // MARK: - Selected-Photos granted pool

    @Test func assetsForSelectedPhotosUnderFullReturnsGrantedPool() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let pool = [SourceAsset(id: "g1", kind: .image), SourceAsset(id: "g2", kind: .image)]
        gateway.setGrantedAssets(pool)
        let provider = PhotoLibraryProvider(gateway: gateway)

        let result = try await provider.assets(in: PhotoLibrarySource.selectedPhotosID)

        #expect(result == pool)
        #expect(gateway.fetchGrantedAssetsCallCount == 1)
        #expect(gateway.fetchAssetsCallCount(for: PhotoLibrarySource.selectedPhotosID) == 0)
    }

    // @covers FR-900-04
    @Test func assetsForSelectedPhotosUnderLimitedReturnsGrantedPool() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        let pool = [SourceAsset(id: "g1", kind: .image)]
        gateway.setGrantedAssets(pool)
        let provider = PhotoLibraryProvider(gateway: gateway)

        let result = try await provider.assets(in: PhotoLibrarySource.selectedPhotosID)

        #expect(result == pool)
        #expect(gateway.fetchGrantedAssetsCallCount == 1)
    }

    // @covers FR-900-04
    @Test func assetsForRegularCollectionUnderLimitedThrowsAuthentication() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        gateway.setAssets([SourceAsset(id: "a1", kind: .image)], for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: "album-1") }

        #expect(failure?.isAuthentication == true)
        // Album is not enumerable under limited: the gateway must not be asked.
        #expect(gateway.fetchAssetsCallCount(for: "album-1") == 0)
    }

    @Test func assetsForSelectedPhotosUnderDeniedThrowsAuthentication() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.denied)
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: PhotoLibrarySource.selectedPhotosID) }

        #expect(failure?.isAuthentication == true)
        #expect(gateway.fetchGrantedAssetsCallCount == 0)
    }

    // MARK: - imageData / metadata pass-through

    @Test func imageDataPassesThroughToGateway() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setImageData(Data([0x01, 0x02, 0x03]), for: "a1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let data = try await provider.imageData(for: "a1", fidelity: .preview)

        #expect(data == Data([0x01, 0x02, 0x03]))
        #expect(gateway.requestImageDataCallCount == 1)
    }

    @Test func imageDataGatewayErrorSurfacesAsTransient() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setImageError(MarkerError(tag: "icloud-image"), for: "a1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.imageData(for: "a1", fidelity: .original) }

        #expect((failure?.transientUnderlying as? MarkerError) == MarkerError(tag: "icloud-image"))
    }

    @Test func metadataPassesThroughToGateway() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let captured = Date(timeIntervalSince1970: 1_600_000_000)
        gateway.setMetadata(
            AssetMetadata(capturedAt: captured, latitude: 64.1, longitude: -21.9, placeName: nil),
            for: "a1"
        )
        let provider = PhotoLibraryProvider(gateway: gateway)

        let metadata = try await provider.metadata(for: "a1")

        #expect(metadata.capturedAt == captured)
        #expect(metadata.latitude == 64.1)
        #expect(metadata.placeName == nil)   // R7: no geocoding from PhotoLibraryKit
        #expect(gateway.fetchMetadataCallCount == 1)
    }

    // MARK: - Change handler pass-through

    @Test func setChangeHandlerForwardsToGateway() async {
        let gateway = FakePhotoLibraryGateway()
        let provider = PhotoLibraryProvider(gateway: gateway)
        let flag = HandlerFlag()

        provider.setChangeHandler { flag.fire() }

        #expect(gateway.setChangeHandlerCallCount == 1)
        #expect(gateway.capturedChangeHandler != nil)

        gateway.fireChange()
        #expect(flag.didFire == true)
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

private extension SourceFailure {
    var isAuthentication: Bool { if case .authentication = self { return true } else { return false } }
    var isNotFound: Bool { if case .notFound = self { return true } else { return false } }
    var transientUnderlying: (any Error)? {
        if case .transient(let underlying) = self { return underlying } else { return nil }
    }
    var permanentUnderlying: (any Error)? {
        if case .permanent(let underlying) = self { return underlying } else { return nil }
    }
}

/// A distinctive non-`SourceFailure` error so transient/permanent mapping is assertable.
private struct MarkerError: Error, Equatable {
    let tag: String
}

/// Thread-safe fire flag for the change-handler pass-through test.
private final class HandlerFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() { lock.withLock { fired = true } }
    var didFire: Bool { lock.withLock { fired } }
}
