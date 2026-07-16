// ImageDeliveryTests.swift — pins the Photos image-delivery semantics (spec 900, T022): the
// degraded-delivery decision (FR-900-07), iCloud-fetch → transient mapping (FR-900-06), and the
// Live-Photo / non-still pass-through contract (FR-900-08). Zero PhotoKit — the decision table is
// a pure type and the provider runs against the scriptable gateway.

import Foundation
import Testing
import PhotoSourceKit
import PhotoLibraryTestSupport
@testable import PhotoLibraryKit

@Suite struct ImageDeliveryTests {

    // MARK: - Degraded-delivery decision (FR-900-07)
    //
    // The rule extracted from PHKitGateway's two request callbacks: a degraded progressive
    // preview is dropped (wait for the final callback), a final payload is delivered, and a
    // final callback carrying no payload is a transient failure. `.highQualityFormat` means
    // the final callback is the only non-degraded one, so this is the whole decision surface.

    @Test func degradedFrameIsNeverDeliveredRegardlessOfPayload() {
        // FR-900-07: a degraded frame is dropped whether or not it already carries bytes —
        // only the final-quality callback may reach the frame.
        #expect(ImageDeliveryRules.decision(isDegraded: true, hasPayload: false) == .ignore)
        #expect(ImageDeliveryRules.decision(isDegraded: true, hasPayload: true) == .ignore)
    }

    @Test func finalQualityPayloadIsDelivered() {
        #expect(ImageDeliveryRules.decision(isDegraded: false, hasPayload: true) == .deliver)
    }

    @Test func finalCallbackWithoutPayloadIsATransientFailure() {
        #expect(ImageDeliveryRules.decision(isDegraded: false, hasPayload: false) == .fail)
    }

    @Test func decisionTableIsExhaustiveAndDegradedDominates() {
        // Full 2×2 table in one place: degraded dominates the payload flag; the non-degraded
        // row splits on whether a payload arrived.
        let table: [(isDegraded: Bool, hasPayload: Bool, expected: ImageDeliveryRules.Decision)] = [
            (true,  true,  .ignore),
            (true,  false, .ignore),
            (false, true,  .deliver),
            (false, false, .fail),
        ]
        for row in table {
            #expect(
                ImageDeliveryRules.decision(isDegraded: row.isDegraded, hasPayload: row.hasPayload) == row.expected,
                "decision(isDegraded: \(row.isDegraded), hasPayload: \(row.hasPayload)) should be \(row.expected)"
            )
        }
    }

    // MARK: - iCloud fetch error → transient (FR-900-06)
    //
    // An iCloud-resident original fetched on demand can fail opaquely (throttling, network
    // drop mid-download). Anything the gateway throws that is not a typed SourceFailure or the
    // not-found signal becomes `.transient`, so the engine retries it with backoff.

    @Test func iCloudImageFetchErrorSurfacesAsTransient() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setImageError(OpaqueICloudError(tag: "icloud-download"), for: "a1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.imageData(for: "a1", fidelity: .original) }

        #expect((failure?.transientUnderlying as? OpaqueICloudError) == OpaqueICloudError(tag: "icloud-download"))
    }

    @Test func iCloudAssetFetchErrorSurfacesAsTransient() async {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        gateway.setAssetsError(OpaqueICloudError(tag: "icloud-list"), for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let failure = await captureFailure { try await provider.assets(in: "album-1") }

        #expect((failure?.transientUnderlying as? OpaqueICloudError) == OpaqueICloudError(tag: "icloud-list"))
    }

    // MARK: - Live-Photo / non-still pass-through (FR-900-08)
    //
    // Live Photos are `mediaType == .image` in PhotoKit and render via the normal image
    // request, so the gateway maps them to `.image`. The provider must NOT filter on kind —
    // it forwards every descriptor verbatim and the ENGINE keeps only `.image` (FR-300-13).

    @Test func imageKindFlowsThroughProviderUnchanged() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        // A Live Photo surfaces as .image — its still is what the frame shows (FR-900-08).
        let assets = [SourceAsset(id: "live-1", kind: .image), SourceAsset(id: "still-1", kind: .image)]
        gateway.setAssets(assets, for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let result = try await provider.assets(in: "album-1")

        #expect(result == assets)
    }

    @Test func videoAndOtherKindsFlowThroughProviderUnchanged() async throws {
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        // The provider does no kind-filtering: videos and other non-still media reach the
        // engine intact, which is where they are skipped (FR-900-08 is an engine contract).
        let assets = [
            SourceAsset(id: "img-1", kind: .image),
            SourceAsset(id: "vid-1", kind: .video),
            SourceAsset(id: "misc-1", kind: .other),
        ]
        gateway.setAssets(assets, for: "album-1")
        let provider = PhotoLibraryProvider(gateway: gateway)

        let result = try await provider.assets(in: "album-1")

        #expect(result == assets)   // all three kinds preserved, in order
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
    var transientUnderlying: (any Error)? {
        if case .transient(let underlying) = self { return underlying } else { return nil }
    }
}

/// A distinctive opaque error standing in for an on-demand iCloud fetch failure — neither a
/// typed `SourceFailure` nor the gateway's not-found signal, so the `.transient` fallback owns it.
private struct OpaqueICloudError: Error, Equatable {
    let tag: String
}
