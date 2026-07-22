import Foundation
import PhotoSourceKit
import PhotoSourceTestSupport
import SlideshowKit
import Testing

@MainActor
// @covers FR-300-13
@Test func startShowsFirstImageAssetAndFiltersVideos() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "video", kind: .video),
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-1")
    #expect(model.currentImageData == Data([1]))
}

@MainActor
@Test func switchAlbumLoadsNewAlbumAndExposesCurrentAlbumID() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([SourceAsset(id: "a1-image", kind: .image)], for: "a1")
    source.setAssets([SourceAsset(id: "a2-image", kind: .image)], for: "a2")
    source.setImageData(Data([1]), for: "a1-image", fidelity: .preview)
    source.setImageData(Data([2]), for: "a2-image", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "a1", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    #expect(model.albumID == "a1")
    #expect(model.currentAssetID == "a1-image")

    await model.switchAlbum("a2")

    #expect(model.albumID == "a2")
    #expect(model.currentAssetID == "a2-image")
    #expect(model.currentImageData == Data([2]))
}

@MainActor
// @covers FR-300-03
@Test func manualTickAdvancesExactlyOneImageAndWraps() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    await ticker.waitUntilWaiting()
    ticker.tick()
    await ticker.waitUntilConsumedTickCount(1)
    await waitUntil(model.currentAssetID == "image-2")
    #expect(model.currentAssetID == "image-2")
    #expect(model.currentImageData == Data([2]))

    await ticker.waitUntilWaiting()
    ticker.tick()
    await ticker.waitUntilConsumedTickCount(2)
    await waitUntil(model.currentAssetID == "image-1")
    #expect(model.currentAssetID == "image-1")
    #expect(model.currentImageData == Data([1]))
}

@MainActor
// @covers FR-300-14
@Test func slideshowDoesNotAdvanceWithoutTickAndPauseStopsTickerUntilResume() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    await settleMainActor()
    #expect(model.currentAssetID == "image-1")

    await ticker.waitUntilWaiting()
    model.pause()
    ticker.tick()
    await settleMainActor()
    #expect(model.currentAssetID == "image-1")

    model.resume()
    await ticker.waitUntilWaiting()
    ticker.tick()
    await ticker.waitUntilConsumedTickCount(1)
    await waitUntil(model.currentAssetID == "image-2")
    #expect(model.currentAssetID == "image-2")
}

@MainActor
@Test func singleImageAlbumRemainsStableOnTick() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([SourceAsset(id: "image-1", kind: .image)], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    await ticker.waitUntilWaiting()
    ticker.tick()
    await ticker.waitUntilConsumedTickCount(1)
    await settleMainActor()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-1")
    #expect(model.currentImageData == Data([1]))
}

@MainActor
private func settleMainActor() async {
    await Task.yield()
    await Task.yield()
    await Task.yield()
}

@MainActor
private func waitUntil(_ condition: @autoclosure () -> Bool) async {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
}

@MainActor
// @covers FR-300-03
@Test func advanceCanBeCalledDirectlyAndWrapsInAlbumOrder() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image),
        SourceAsset(id: "image-3", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)
    source.setImageData(Data([3]), for: "image-3", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    await model.advance()
    #expect(model.currentAssetID == "image-2")

    await model.advance()
    #expect(model.currentAssetID == "image-3")

    await model.advance()
    #expect(model.currentAssetID == "image-1")
}

@MainActor
// @covers FR-300-06
@Test func startPrefetchesNextImageWithoutBlockingDisplay() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let cache = ImageCache(limit: 3)
    let config = SlideshowConfig(prefetchDepth: 1, cacheLimit: 3)
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, cache: cache, config: config, settingsStore: sequentialThemeStore())
    await model.start()

    #expect(model.currentAssetID == "image-1")
    await waitUntil(cache.contains("image-2#preview"))
    #expect(cache.contains("image-2#preview"))
    #expect(source.imageDataCallCount(for: "image-2", fidelity: .preview) == 1)
}

@MainActor
// @covers FR-300-06
@Test func advanceUsesPrefetchedImageWithoutAdditionalPreviewCall() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let cache = ImageCache(limit: 3)
    let config = SlideshowConfig(prefetchDepth: 1, cacheLimit: 3)
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image),
        SourceAsset(id: "image-3", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)
    source.setImageData(Data([3]), for: "image-3", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, cache: cache, config: config, settingsStore: sequentialThemeStore())
    await model.start()
    await waitUntil(cache.contains("image-2"))
    #expect(source.imageDataCallCount(for: "image-2", fidelity: .preview) == 1)

    await model.advance()

    #expect(model.currentAssetID == "image-2")
    #expect(source.imageDataCallCount(for: "image-2", fidelity: .preview) == 1)
}

@MainActor
// @covers FR-300-07, SC-300-04
@Test func prefetchWrapsAndRespectsCacheLimitAcrossTicks() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let cache = ImageCache(limit: 3)
    let config = SlideshowConfig(prefetchDepth: 2, cacheLimit: 3)
    let assets = (1...6).map { SourceAsset(id: "image-\($0)", kind: .image) }
    source.setAssets(assets, for: "album")
    for value in 1...6 {
        source.setImageData(Data([UInt8(value)]), for: "image-\(value)", fidelity: .preview)
    }

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, cache: cache, config: config, settingsStore: sequentialThemeStore())
    await model.start()
    await waitUntil(cache.contains("image-2") && cache.contains("image-3"))

    for expectedTick in 1...10 {
        await ticker.waitUntilWaiting()
        ticker.tick()
        await ticker.waitUntilConsumedTickCount(expectedTick)
        await settleMainActor()
        #expect(cache.count <= config.cacheLimit)
    }
}

@MainActor
// @covers FR-300-09
@Test func startSkipsInitialPreviewErrorsAndShowsFirstLoadableImage() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageError(SourceFailure.transient(underlying: TestSourceError.probe), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-2")
    #expect(model.currentImageData == Data([2]))
}

@MainActor
// @covers FR-300-09, SC-300-05
@Test func advanceSkipsPreviewErrorAndShowsNextLoadableImage() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image),
        SourceAsset(id: "image-3", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageError(SourceFailure.transient(underlying: TestSourceError.probe), for: "image-2", fidelity: .preview)
    source.setImageData(Data([3]), for: "image-3", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    await model.advance()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-3")
    #expect(model.currentImageData == Data([3]))
}

@MainActor
// @covers FR-300-10, FR-300-13
@Test func emptyAndVideoOnlyAlbumsEnterEmptyPhase() async {
    let emptySource = StubPhotoSource()
    emptySource.setAssets([], for: "empty")
    let emptyModel = SlideshowViewModel(source: emptySource, collectionID: "empty", ticker: ManualTicker(), settingsStore: sequentialThemeStore())
    await emptyModel.start()
    #expect(emptyModel.phase == .empty)

    let videoSource = StubPhotoSource()
    videoSource.setAssets([
        SourceAsset(id: "video-1", kind: .video),
        SourceAsset(id: "video-2", kind: .video)
    ], for: "videos")
    let videoModel = SlideshowViewModel(source: videoSource, collectionID: "videos", ticker: ManualTicker(), settingsStore: sequentialThemeStore())
    await videoModel.start()
    #expect(videoModel.phase == .empty)
}

@MainActor
// @covers FR-300-10, SC-300-07
@Test func assetsErrorFailsAndRetryStartsAgainWhenAssetsRecover() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssetsError(SourceFailure.transient(underlying: TestSourceError.probe), for: "album")

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    #expect(model.phase == .failed)

    source.setAssets([SourceAsset(id: "image-1", kind: .image)], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    await model.retry()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-1")
}

@MainActor
@Test func showPreviousStepsBackwardAndWraps() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image),
        SourceAsset(id: "image-3", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)
    source.setImageData(Data([3]), for: "image-3", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    #expect(model.currentAssetID == "image-1")

    // From the first image, previous wraps to the last.
    await model.showPrevious()
    #expect(model.currentAssetID == "image-3")

    await model.showPrevious()
    #expect(model.currentAssetID == "image-2")
}

@MainActor
// @covers FR-300-19
@Test func showNextStepsForwardAndResetsTicker() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image),
        SourceAsset(id: "image-3", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)
    source.setImageData(Data([3]), for: "image-3", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    await model.showNext()
    #expect(model.currentAssetID == "image-2")

    // The auto-advance timer is still armed after a manual step.
    await ticker.waitUntilWaiting()
    ticker.tick()
    await ticker.waitUntilConsumedTickCount(1)
    await waitUntil(model.currentAssetID == "image-3")
    #expect(model.currentAssetID == "image-3")
}

@MainActor
// @covers FR-300-14, FR-300-18
@Test func togglePauseStopsTickerAndSurvivesForegroundResume() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    await ticker.waitUntilWaiting()

    // User pauses via chrome.
    model.togglePause()
    #expect(model.isPaused)
    ticker.tick()
    await settleMainActor()
    #expect(model.currentAssetID == "image-1")

    // A background→foreground cycle must NOT silently resume a user-paused show.
    model.pause()
    model.resume()
    ticker.tick()
    await settleMainActor()
    #expect(model.currentAssetID == "image-1")

    // While paused, manual navigation still works.
    await model.showNext()
    #expect(model.currentAssetID == "image-2")
    #expect(model.isPaused)

    // Resuming re-arms the auto-advance.
    model.togglePause()
    #expect(!model.isPaused)
    await ticker.waitUntilWaiting()
    ticker.tick()
    await ticker.waitUntilConsumedTickCount(1)
    await waitUntil(model.currentAssetID == "image-1")
    #expect(model.currentAssetID == "image-1")
}

@MainActor
// @covers FR-300-23
@Test func jumpGoesToRequestedAssetAndIgnoresUnknown() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image),
        SourceAsset(id: "image-3", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)
    source.setImageData(Data([3]), for: "image-3", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    await model.jump(to: "image-3")
    #expect(model.currentAssetID == "image-3")
    #expect(model.currentImageData == Data([3]))

    await model.jump(to: "does-not-exist")
    #expect(model.currentAssetID == "image-3")
}

// 900 T032 (FR-900-10): the info overlay reads date/place through the engine's neutral
// metadata pass-through — one path for both backends (Immich composes EXIF place; Photos
// delivers date only, placeName nil by R7).
@MainActor
@Test func metadataPassesThroughFromTheSource() async throws {
    let source = StubPhotoSource()
    let captured = Date(timeIntervalSince1970: 1_718_462_400)
    source.setAssets([SourceAsset(id: "image-1", kind: .image)], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setMetadata(
        AssetMetadata(capturedAt: captured, latitude: nil, longitude: nil, placeName: "Berlin, Germany"),
        for: "image-1"
    )

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ManualTicker(), settingsStore: sequentialThemeStore())
    let metadata = try await model.metadata(for: "image-1")

    #expect(metadata.capturedAt == captured)
    #expect(metadata.placeName == "Berlin, Germany")
}

// 900 T031 (FR-900-12): HA image publishing reads bytes through the engine's neutral
// pass-through, so a Photos source publishes under the same opt-in as Immich.
@MainActor
@Test func imageDataPassesThroughFromTheSource() async throws {
    let source = StubPhotoSource()
    source.setAssets([SourceAsset(id: "image-1", kind: .image)], for: "album")
    source.setImageData(Data([7]), for: "image-1", fidelity: .thumbnail)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ManualTicker(), settingsStore: sequentialThemeStore())
    let data = try await model.imageData(for: "image-1", fidelity: .thumbnail)

    #expect(data == Data([7]))
}

// 900 T031 (FR-710-07 parity): the photo-count diagnostic can come from the engine's own
// rotation — correct for backends whose collections the server album list doesn't know.
@MainActor
@Test func photoCountReflectsTheLoadedRotation() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "video", kind: .video),
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    #expect(model.photoCount == 0)
    await model.start()
    #expect(model.photoCount == 2, "videos are filtered — the rotation holds two images")
}

// The former advanceFailsWhenEveryImageInRingNowFails test asserted the pre-310
// dead-end (`phase == .failed` on total image exhaustion). FR-310-03 supersedes
// it: the current image stays up and a backoff retry recovers the show — see
// imageExhaustionKeepsCurrentImageAndAutoRecovers in SlideshowResilienceTests.

// 900 US1 / SC-900-06 seed: a cross-backend source switch uses the rebuild strategy —
// the app drops the old engine and builds a fresh one against the other provider.
// Nothing calls pause() on the way out, so the engine itself must not outlive its last
// external reference: a playing view model that is dropped mid-tick has to deallocate
// (its ticker loop must hold it only weakly and die with it), or every rebuild leaks a
// live timer still advancing — and fetching — against the abandoned source.
@MainActor
@Test func droppedViewModelDeallocatesAndStopsItsTickerLoop() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    var model: SlideshowViewModel? = SlideshowViewModel(
        source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore()
    )
    await model!.start()
    #expect(model!.phase == .playing)
    // The auto-advance loop is armed and parked inside the ticker wait.
    await ticker.waitUntilWaiting()

    weak var dropped = model
    model = nil

    #expect(dropped == nil, "the rebuild path just drops the engine — its ticker loop must not keep it alive")
}

// MARK: - refreshNow (900, FR-900-09)
//
// The app calls refreshNow() when the platform reports a library change or the app
// foregrounds with a Photos source active. It is the same quiet re-fetch the hourly
// refresh runs — no loading state, the live list reconciled into the running rotation
// (310 rules), failures classified like any refresh failure — just triggered on demand.

@MainActor
@Test func refreshNowReconcilesAListAdditionWithoutDisturbingPlayback() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-a", kind: .image),
        SourceAsset(id: "image-c", kind: .image)
    ], for: "album")
    source.setImageData(Data("image-a".utf8), for: "image-a", fidelity: .preview)
    source.setImageData(Data("image-c".utf8), for: "image-c", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    #expect(model.currentAssetID == "image-a")

    // The library gains image-b between a and c; an immediate refresh (change callback /
    // foreground) reconciles it in — without a phase change and without a frame swap.
    source.setAssets([
        SourceAsset(id: "image-a", kind: .image),
        SourceAsset(id: "image-b", kind: .image),
        SourceAsset(id: "image-c", kind: .image)
    ], for: "album")
    source.setImageData(Data("image-b".utf8), for: "image-b", fidelity: .preview)

    await model.refreshNow()

    // FR-310-07: quiet — the shown photo and the phase are untouched.
    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-a")
    #expect(model.currentImageData == Data("image-a".utf8))

    // …but image-b is now part of the running rotation.
    await ticker.waitUntilWaiting()
    ticker.tick()
    await waitUntil(model.currentAssetID == "image-b")
    #expect(model.currentAssetID == "image-b")
}

@MainActor
@Test func refreshNowOnAVanishedSourceLandsCalmNotFoundState() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let clock = TestClock()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, clock: clock, settingsStore: sequentialThemeStore())
    await model.start()
    #expect(model.currentAssetID == "image-1")
    await clock.waitUntilSleeperCount(1)   // only the hourly refresh is parked

    // The source's collection vanishes (album deleted / unshared / upgraded to the new
    // iCloud format); every fetch now raises the not-found signal.
    source.setAssetsError(SourceFailure.notFound, for: "album")

    await model.refreshNow()

    // FR-900-16: vanish is terminal and calm — a first-class unavailable state, NOT an error
    // path that keeps looping a dead collection's remembered photos. Because a terminal reason
    // never retries, FR-310-03 ("keep the current image while retrying") does not apply: there
    // is no silent recovery to hold the stale photo for. So the calm `.failed` state is
    // surfaced at once even though a photo was on screen — the stale image is cleared, the
    // reason names it, and NO backoff retry is armed. The pre-existing hourly refresh survives
    // (terminal cancels only the retry), so the show still recovers on its own if the
    // collection returns.
    #expect(model.failureReason == .notFound)
    #expect(model.currentAssetID == nil)
    #expect(model.currentImageData == nil)
    #expect(model.phase == .failed)
    #expect(clock.sleeperCount == 1)
}

// MARK: - Decode-ahead preparer seam (Ken Burns smoothness: no lazy decode at the swap)

@MainActor
@Test func startPreparesTheCurrentAndPrefetchedImagesForDisplay() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let preparer = SpyImagePreparer()
    let config = SlideshowConfig(prefetchDepth: 2, cacheLimit: 4)
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image),
        SourceAsset(id: "image-3", kind: .image),
        SourceAsset(id: "image-4", kind: .image)
    ], for: "album")
    for value in 1...4 {
        source.setImageData(Data([UInt8(value)]), for: "image-\(value)", fidelity: .preview)
    }

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, config: config, settingsStore: sequentialThemeStore(), preparer: preparer)
    await model.start()

    // The current photo and the whole prefetch window are decoded ahead, each
    // with the exact bytes the display path would hand SwiftUI.
    await waitUntil(preparer.preparedIDs.contains("image-1")
        && preparer.preparedIDs.contains("image-2")
        && preparer.preparedIDs.contains("image-3"))
    #expect(preparer.data(for: "image-1") == Data([1]))
    #expect(preparer.data(for: "image-2") == Data([2]))
    #expect(preparer.data(for: "image-3") == Data([3]))
    #expect(!preparer.preparedIDs.contains("image-4"))
}

@MainActor
@Test func prefetchPreparesRAMCacheHitsToo() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let preparer = SpyImagePreparer()
    let cache = ImageCache(limit: 4)
    let config = SlideshowConfig(prefetchDepth: 1, cacheLimit: 4)
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)
    // Pre-warm the RAM cache: the prefetch loop's cache-hit branch used to
    // `continue` without the data in hand — it must still decode ahead.
    cache.store(Data([2]), for: "image-2#preview")

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, cache: cache, config: config, settingsStore: sequentialThemeStore(), preparer: preparer)
    await model.start()

    await waitUntil(preparer.preparedIDs.contains("image-2"))
    #expect(preparer.data(for: "image-2") == Data([2]))
    // The bytes came from the RAM cache, not another fetch.
    #expect(source.imageDataCallCount(for: "image-2", fidelity: .preview) == 0)
}

@MainActor
@Test func nilPreparerKeepsTodaysBehavior() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)

    // The nil-means-unchanged DI contract (like diskCache/snapshots): omitting
    // the preparer is exactly the pre-seam engine.
    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    #expect(model.currentAssetID == "image-1")
    #expect(model.currentImageData == Data([1]))

    await model.advance()
    #expect(model.currentAssetID == "image-2")
    #expect(model.currentImageData == Data([2]))
}
