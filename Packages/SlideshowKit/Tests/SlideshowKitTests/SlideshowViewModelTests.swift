import Foundation
import ImmichClient
import SlideshowKit
import Testing

@MainActor
@Test func startShowsFirstImageAssetAndFiltersVideos() async {
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "video", type: "VIDEO"),
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-1")
    #expect(model.currentImageData == Data([1]))
}

@MainActor
@Test func switchAlbumLoadsNewAlbumAndExposesCurrentAlbumID() async {
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([Asset(id: "a1-image", type: "IMAGE")], for: "a1")
    api.setAssets([Asset(id: "a2-image", type: "IMAGE")], for: "a2")
    api.setPreviewData(Data([1]), for: "a1-image")
    api.setPreviewData(Data([2]), for: "a2-image")

    let model = SlideshowViewModel(api: api, albumID: "a1", ticker: ticker, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([Asset(id: "image-1", type: "IMAGE")], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE"),
        Asset(id: "image-3", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")
    api.setPreviewData(Data([3]), for: "image-3")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    let cache = ImageCache(limit: 3)
    let config = SlideshowConfig(prefetchDepth: 1, cacheLimit: 3)
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, cache: cache, config: config, settingsStore: sequentialThemeStore())
    await model.start()

    #expect(model.currentAssetID == "image-1")
    await waitUntil(cache.contains("image-2#preview"))
    #expect(cache.contains("image-2#preview"))
    #expect(api.previewCallCount(for: "image-2") == 1)
}

@MainActor
@Test func advanceUsesPrefetchedImageWithoutAdditionalPreviewCall() async {
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    let cache = ImageCache(limit: 3)
    let config = SlideshowConfig(prefetchDepth: 1, cacheLimit: 3)
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE"),
        Asset(id: "image-3", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")
    api.setPreviewData(Data([3]), for: "image-3")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, cache: cache, config: config, settingsStore: sequentialThemeStore())
    await model.start()
    await waitUntil(cache.contains("image-2"))
    #expect(api.previewCallCount(for: "image-2") == 1)

    await model.advance()

    #expect(model.currentAssetID == "image-2")
    #expect(api.previewCallCount(for: "image-2") == 1)
}

@MainActor
@Test func prefetchWrapsAndRespectsCacheLimitAcrossTicks() async {
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    let cache = ImageCache(limit: 3)
    let config = SlideshowConfig(prefetchDepth: 2, cacheLimit: 3)
    let assets = (1...6).map { Asset(id: "image-\($0)", type: "IMAGE") }
    api.setAssets(assets, for: "album")
    for value in 1...6 {
        api.setPreviewData(Data([UInt8(value)]), for: "image-\(value)")
    }

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, cache: cache, config: config, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE")
    ], for: "album")
    api.setPreviewError(ImmichError.unreachable, for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-2")
    #expect(model.currentImageData == Data([2]))
}

@MainActor
@Test func advanceSkipsPreviewErrorAndShowsNextLoadableImage() async {
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE"),
        Asset(id: "image-3", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewError(ImmichError.unreachable, for: "image-2")
    api.setPreviewData(Data([3]), for: "image-3")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    await model.advance()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-3")
    #expect(model.currentImageData == Data([3]))
}

@MainActor
@Test func emptyAndVideoOnlyAlbumsEnterEmptyPhase() async {
    let emptyAPI = StubImmichAPI()
    emptyAPI.setAssets([], for: "empty")
    let emptyModel = SlideshowViewModel(api: emptyAPI, albumID: "empty", ticker: ManualTicker(), settingsStore: sequentialThemeStore())
    await emptyModel.start()
    #expect(emptyModel.phase == .empty)

    let videoAPI = StubImmichAPI()
    videoAPI.setAssets([
        Asset(id: "video-1", type: "VIDEO"),
        Asset(id: "video-2", type: "VIDEO")
    ], for: "videos")
    let videoModel = SlideshowViewModel(api: videoAPI, albumID: "videos", ticker: ManualTicker(), settingsStore: sequentialThemeStore())
    await videoModel.start()
    #expect(videoModel.phase == .empty)
}

@MainActor
@Test func assetsErrorFailsAndRetryStartsAgainWhenAssetsRecover() async {
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssetsError(ImmichError.unreachable, for: "album")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
    await model.start()
    #expect(model.phase == .failed)

    api.setAssets([Asset(id: "image-1", type: "IMAGE")], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    await model.retry()

    #expect(model.phase == .playing)
    #expect(model.currentAssetID == "image-1")
}

@MainActor
@Test func showPreviousStepsBackwardAndWraps() async {
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE"),
        Asset(id: "image-3", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")
    api.setPreviewData(Data([3]), for: "image-3")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE"),
        Asset(id: "image-3", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")
    api.setPreviewData(Data([3]), for: "image-3")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
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
    let api = StubImmichAPI()
    let ticker = ManualTicker()
    api.setAssets([
        Asset(id: "image-1", type: "IMAGE"),
        Asset(id: "image-2", type: "IMAGE"),
        Asset(id: "image-3", type: "IMAGE")
    ], for: "album")
    api.setPreviewData(Data([1]), for: "image-1")
    api.setPreviewData(Data([2]), for: "image-2")
    api.setPreviewData(Data([3]), for: "image-3")

    let model = SlideshowViewModel(api: api, albumID: "album", ticker: ticker, settingsStore: sequentialThemeStore())
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
