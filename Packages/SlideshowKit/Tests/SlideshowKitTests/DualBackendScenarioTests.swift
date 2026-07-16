// DualBackendScenarioTests.swift — the cross-backend engine gate (spec 900, T026, SC-900-03).
//
// Identical engine-level scenario assertions run over BOTH source backends: the neutral
// `StubPhotoSource` and a real `PhotoLibraryProvider` driven over the shared gateway fake. If
// the engine's behavior ever diverges between an Immich-shaped source and the Photos source,
// one of these parameterized cases fails — that is the whole point of the neutral
// `PhotoSourceProviding` seam (R1). Everything here is deterministic: ManualTicker for the
// auto-advance, TestClock where a backoff sleeper is asserted, and `advance()`/`refreshNow()`
// awaited directly so no polling is needed.

import Foundation
import PhotoSourceKit
import PhotoSourceTestSupport
import PhotoLibraryKit
import PhotoLibraryTestSupport
import SlideshowKit
import Testing

// MARK: - Backend matrix

/// The album/collection identifier every scenario rotates over.
private let scenarioCollectionID = "album"

/// The three still images every scenario is preloaded with; each backend serves
/// `Data(id.utf8)` bytes for them.
private let scenarioImageIDs = ["image-1", "image-2", "image-3"]

/// The two backends the gate runs every scenario over. Internal (not private) so it can be a
/// `@Test(arguments:)` parameter type; renamed off the generic `Backend` to avoid a
/// test-module name clash.
enum ScenarioBackend: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case stub
    case photoLibrary
    var testDescription: String { rawValue }
}

/// A backend the scenarios script uniformly: `source` is what the engine consumes; the four
/// closures adapt the shared scripting calls onto whichever fake sits behind it (the neutral
/// stub, or the gateway under a real `PhotoLibraryProvider`).
private struct ScriptableBackend {
    let source: any PhotoSourceProviding
    let setAssets: ([SourceAsset]) -> Void
    let setImageData: (Data, String) -> Void
    let setAssetsError: (any Error) -> Void
    let setImageError: (any Error, String) -> Void
}

private func makeBackend(_ backend: ScenarioBackend) -> ScriptableBackend {
    switch backend {
    case .stub:
        let stub = StubPhotoSource()
        return ScriptableBackend(
            source: stub,
            setAssets: { stub.setAssets($0, for: scenarioCollectionID) },
            setImageData: { stub.setImageData($0, for: $1, fidelity: .preview) },
            setAssetsError: { stub.setAssetsError($0, for: scenarioCollectionID) },
            setImageError: { stub.setImageError($0, for: $1, fidelity: .preview) }
        )
    case .photoLibrary:
        // A real PhotoLibraryProvider under full access, driven over the gateway fake — the
        // exact production type the app builds for a Photos album, minus PhotoKit.
        let gateway = FakePhotoLibraryGateway()
        gateway.setAuthorization(.full)
        let provider = PhotoLibraryProvider(gateway: gateway, collectionID: scenarioCollectionID)
        return ScriptableBackend(
            source: provider,
            setAssets: { gateway.setAssets($0, for: scenarioCollectionID) },
            setImageData: { gateway.setImageData($0, for: $1) },
            setAssetsError: { gateway.setAssetsError($0, for: scenarioCollectionID) },
            setImageError: { gateway.setImageError($0, for: $1) }
        )
    }
}

/// Preload the standard 3-image fixture (optionally with a `.video` mixed in, to prove the
/// engine's still-image filter holds for every backend).
private func seed(_ backend: ScriptableBackend, includingVideo: Bool = false) {
    var assets = scenarioImageIDs.map { SourceAsset(id: $0, kind: .image) }
    if includingVideo {
        assets.insert(SourceAsset(id: "video-1", kind: .video), at: 1)
    }
    backend.setAssets(assets)
    for id in scenarioImageIDs {
        backend.setImageData(Data(id.utf8), id)
    }
}

// MARK: - Scenarios (identical over both backends)

@Suite("Dual-backend engine gate (SC-900-03)")
struct DualBackendScenarioTests {

    // start → plays the first still image, non-images filtered out.
    @MainActor
    @Test(arguments: ScenarioBackend.allCases)
    func startPlaysFirstImageAndFiltersNonImages(_ backend: ScenarioBackend) async {
        let b = makeBackend(backend)
        seed(b, includingVideo: true)
        let model = SlideshowViewModel(
            source: b.source, collectionID: scenarioCollectionID,
            ticker: ManualTicker(), settingsStore: sequentialThemeStore()
        )
        await model.start()

        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-1")
        #expect(model.currentImageData == Data("image-1".utf8))
    }

    // Manual advance walks the album order and wraps at the end.
    @MainActor
    @Test(arguments: ScenarioBackend.allCases)
    func manualAdvanceWalksOrderAndWraps(_ backend: ScenarioBackend) async {
        let b = makeBackend(backend)
        seed(b)
        let model = SlideshowViewModel(
            source: b.source, collectionID: scenarioCollectionID,
            ticker: ManualTicker(), settingsStore: sequentialThemeStore()
        )
        await model.start()
        #expect(model.currentAssetID == "image-1")

        await model.advance()
        #expect(model.currentAssetID == "image-2")
        await model.advance()
        #expect(model.currentAssetID == "image-3")
        await model.advance()
        #expect(model.currentAssetID == "image-1")   // wraps
    }

    // A failing image load is skipped and the rotation continues to the next loadable photo —
    // no blank, no error surface (FR-300-09 / FR-900-06).
    @MainActor
    @Test(arguments: ScenarioBackend.allCases)
    func failingImageLoadIsSkippedAndRotationContinues(_ backend: ScenarioBackend) async {
        let b = makeBackend(backend)
        seed(b)
        b.setImageError(SourceFailure.transient(underlying: TestSourceError.probe), "image-2")
        let model = SlideshowViewModel(
            source: b.source, collectionID: scenarioCollectionID,
            ticker: ManualTicker(), settingsStore: sequentialThemeStore()
        )
        await model.start()
        #expect(model.currentAssetID == "image-1")

        await model.advance()

        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-3")   // image-2 skipped entirely
        #expect(model.currentImageData == Data("image-3".utf8))
        #expect(model.failureReason == nil)
    }

    // A transient source-list failure at start is calm (no crash, an actionable failed state)
    // and arms the backoff retry — for either backend.
    @MainActor
    @Test(arguments: ScenarioBackend.allCases)
    func sourceListFailureAtStartIsCalmAndArmsRetry(_ backend: ScenarioBackend) async {
        let b = makeBackend(backend)
        b.setAssetsError(SourceFailure.transient(underlying: TestSourceError.probe))
        let clock = TestClock()
        let model = SlideshowViewModel(
            source: b.source, collectionID: scenarioCollectionID,
            ticker: ManualTicker(), clock: clock, settingsStore: sequentialThemeStore()
        )
        await model.start()

        #expect(model.phase == .failed)
        #expect(model.failureReason == .transient)

        await clock.waitUntilSleeperCount(1)   // backoff retry parked
        #expect(clock.sleeperCount == 1)
    }

    // refreshNow() after the list gained an asset reconciles the addition into the running
    // rotation without disturbing the shown photo — the T025 entry point, over both backends.
    @MainActor
    @Test(arguments: ScenarioBackend.allCases)
    func refreshNowReconcilesAListAddition(_ backend: ScenarioBackend) async {
        let b = makeBackend(backend)
        seed(b)
        let model = SlideshowViewModel(
            source: b.source, collectionID: scenarioCollectionID,
            ticker: ManualTicker(), settingsStore: sequentialThemeStore()
        )
        await model.start()
        #expect(model.currentAssetID == "image-1")

        // The library gains image-4.
        b.setAssets((scenarioImageIDs + ["image-4"]).map { SourceAsset(id: $0, kind: .image) })
        b.setImageData(Data("image-4".utf8), "image-4")

        await model.refreshNow()

        // Quiet: the shown photo and the phase are untouched…
        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-1")

        // …and image-4 is now part of the running rotation.
        var seen: Set<String> = [model.currentAssetID ?? ""]
        for _ in 0..<3 {
            await model.advance()
            seen.insert(model.currentAssetID ?? "")
        }
        #expect(seen.contains("image-4"))
    }
}
