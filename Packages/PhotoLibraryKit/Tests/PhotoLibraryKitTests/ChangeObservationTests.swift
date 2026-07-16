// ChangeObservationTests.swift — the library-change → engine-refresh seam and the mid-play
// vanish contract (spec 900, T024). Zero PhotoKit: everything runs against the scriptable
// gateway. Two of the three pins here are characterization of behavior that already shipped
// (the handler pass-through and the notFound mapping); they are stated explicitly here because
// this is the file that owns the FR-900-09 change-observation and FR-900-16 vanish contracts.

import Foundation
import Testing
import PhotoSourceKit
import PhotoLibraryTestSupport
@testable import PhotoLibraryKit

@Suite struct ChangeObservationTests {

    // MARK: - Handler registration (FR-900-09)

    // The provider is a pure pass-through for the change handler: registering hands the closure
    // to the gateway (which owns the real PhotoKit observer), and clearing with `nil` unregisters
    // it. The app wires engine `refreshNow()` onto this so a library edit re-fetches the source.
    @Test func setChangeHandlerRegistersAndClearsThroughTheGateway() async {
        let gateway = FakePhotoLibraryGateway()
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")

        provider.setChangeHandler { }
        #expect(gateway.setChangeHandlerCallCount == 1)
        #expect(gateway.capturedChangeHandler != nil)

        // Clearing forwards a nil handler — the observer is torn down at the gateway.
        provider.setChangeHandler(nil)
        #expect(gateway.setChangeHandlerCallCount == 2)
        #expect(gateway.capturedChangeHandler == nil)
    }

    // A gateway library-change callback invokes exactly the handler the provider registered —
    // this is the edge the app turns into an engine re-fetch. `fireChange()` stands in for the
    // real PHPhotoLibraryChangeObserver notification.
    @Test func fireChangeInvokesTheRegisteredHandler() async {
        let gateway = FakePhotoLibraryGateway()
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")
        let flag = HandlerFlag()

        provider.setChangeHandler { flag.fire() }
        #expect(flag.didFire == false)   // registration alone does not fire

        gateway.fireChange()
        #expect(flag.didFire == true)
    }

    // MARK: - Mid-play vanish (FR-900-16)

    // The album this provider serves disappears mid-slideshow (deleted / unshared / upgraded to
    // the new iCloud format). Once the gateway's `fetchAssets` starts raising `collectionNotFound`,
    // `assets(in:)` surfaces `SourceFailure.notFound` — the neutral signal the engine's refresh
    // path turns into the calm, terminal vanish state. The first fetch still succeeds, so this
    // pins the *transition* to gone, not a source that was never there.
    @Test func vanishedCollectionSurfacesNotFoundFromAssets() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setAssets([SourceAsset(id: "a1", kind: .image)], for: "album")
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")

        // The show is playing off a healthy fetch.
        let before = try await provider.assets(in: "album")
        #expect(before == [SourceAsset(id: "a1", kind: .image)])

        // The collection vanishes: every subsequent enumeration raises the not-found signal.
        gateway.setAssetsError(PhotoLibraryGatewayError.collectionNotFound, for: "album")

        let failure = await captureFailure { try await provider.assets(in: "album") }
        #expect(failure?.isNotFound == true)
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
    var isNotFound: Bool { if case .notFound = self { return true } else { return false } }
}

/// Thread-safe fire flag for the change-handler callback assertions.
private final class HandlerFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() { lock.withLock { fired = true } }
    var didFire: Bool { lock.withLock { fired } }
}
