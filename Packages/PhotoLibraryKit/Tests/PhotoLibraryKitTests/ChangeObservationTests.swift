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

    // MARK: - Prompt-free change observation (FR-900-04)

    // The observer must never be wired while access is `.notDetermined`: registering a
    // `PHPhotoLibraryChangeObserver` is what fires the system TCC prompt, and the spec forbids
    // any permission request outside the picker moment. So at registration the provider stores
    // the handler but does NOT forward it to the gateway — the gateway is left untouched.
    @Test func notDeterminedDoesNotForwardChangeHandlerAtRegistration() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")

        provider.setChangeHandler { }

        #expect(gateway.setChangeHandlerCallCount == 0)
        #expect(gateway.capturedChangeHandler == nil)
    }

    // Denied is equally prompt-sensitive (and pointless to observe): no forward at registration.
    @Test func deniedDoesNotForwardChangeHandlerAtRegistration() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.denied)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")

        provider.setChangeHandler { }

        #expect(gateway.setChangeHandlerCallCount == 0)
        #expect(gateway.capturedChangeHandler == nil)
    }

    // Full access is already granted, so registering the observer cannot prompt: forward it
    // immediately at registration time.
    @Test func fullAccessForwardsChangeHandlerImmediately() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")

        provider.setChangeHandler { }

        #expect(gateway.setChangeHandlerCallCount == 1)
        #expect(gateway.capturedChangeHandler != nil)
    }

    // Limited access is also a granted level — registration is prompt-free — and the
    // granted-assets pool is the source this provider serves, so forward immediately.
    @Test func limitedSelectedPhotosForwardsChangeHandlerImmediately() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.limited)
        let provider = PhotoLibraryProvider(
            gateway: gateway, collectionID: PhotoLibrarySource.selectedPhotosID
        )

        provider.setChangeHandler { }

        #expect(gateway.setChangeHandlerCallCount == 1)
        #expect(gateway.capturedChangeHandler != nil)
    }

    // The deferred handler comes alive exactly once. It is set while `.notDetermined` (no
    // forward), the user then grants full access, and the next `ensureReady()` — which runs at
    // engine start, every refresh, and manual retry — forwards it. A second `ensureReady()`
    // must not re-register (a double PhotoKit registration).
    @Test func deferredHandlerForwardsOnceAfterAccessIsGranted() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")

        provider.setChangeHandler { }
        #expect(gateway.setChangeHandlerCallCount == 0)   // deferred, no prompt

        gateway.setAuthorization(.full)
        try await provider.ensureReady()
        #expect(gateway.setChangeHandlerCallCount == 1)
        #expect(gateway.capturedChangeHandler != nil)

        // Readiness is re-checked constantly; the observer must be wired exactly once.
        try await provider.ensureReady()
        #expect(gateway.setChangeHandlerCallCount == 1)
    }

    // Access never gets granted: the handler stays deferred and `ensureReady()` still surfaces
    // the calm auth gate, having never touched the gateway.
    @Test func deferredHandlerStaysUnforwardedWhileAccessRemainsNotDetermined() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.notDetermined)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")

        provider.setChangeHandler { }

        let failure = await captureFailure { try await provider.ensureReady() }
        #expect(failure?.isAuthentication == true)
        #expect(gateway.setChangeHandlerCallCount == 0)
    }

    // Once a handler has actually been forwarded, clearing it with `nil` must forward the nil so
    // the gateway tears the real observer down (no leaked registration).
    @Test func clearingAfterForwardUnregistersAtGateway() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: "album")

        provider.setChangeHandler { }
        #expect(gateway.capturedChangeHandler != nil)

        provider.setChangeHandler(nil)
        #expect(gateway.capturedChangeHandler == nil)
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
    var isAuthentication: Bool { if case .authentication = self { return true } else { return false } }
}

/// Thread-safe fire flag for the change-handler callback assertions.
private final class HandlerFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() { lock.withLock { fired = true } }
    var didFire: Bool { lock.withLock { fired } }
}
