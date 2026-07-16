import Foundation
import PhotoSourceKit
import PhotoSourceTestSupport
import SlideshowKit
import Testing

@MainActor
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

// The former advanceFailsWhenEveryImageInRingNowFails test asserted the pre-310
// dead-end (`phase == .failed` on total image exhaustion). FR-310-03 supersedes
// it: the current image stays up and a backoff retry recovers the show — see
// imageExhaustionKeepsCurrentImageAndAutoRecovers in SlideshowResilienceTests.
