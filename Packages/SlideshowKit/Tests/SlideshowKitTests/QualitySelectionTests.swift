import Foundation
import PhotoSourceKit
import PhotoSourceTestSupport
import SlideshowKit
import Testing
import ThemeKit
import ThemeKitTestSupport

@MainActor
// @covers FR-300-04
@Test func originalQualityLoadsOriginalBytesWithoutPreviewFetch() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([SourceAsset(id: "a", kind: .image)], for: "album")
    source.setImageData(Data([1]), for: "a", fidelity: .preview)
    source.setImageData(Data([2]), for: "a", fidelity: .original)

    let model = SlideshowViewModel(
        source: source,
        collectionID: "album",
        ticker: ticker,
        settingsStore: themeStore(quality: .original)
    )
    await model.start()

    #expect(model.currentAssetID == "a")
    #expect(model.currentImageData == Data([2]))
    #expect(source.imageDataCallCount(for: "a", fidelity: .original) == 1)
    #expect(source.imageDataCallCount(for: "a", fidelity: .preview) == 0)
}

@MainActor
// @covers FR-300-04
@Test func previewQualityLoadsPreviewBytesWithoutOriginalFetch() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([SourceAsset(id: "a", kind: .image)], for: "album")
    source.setImageData(Data([1]), for: "a", fidelity: .preview)
    source.setImageData(Data([2]), for: "a", fidelity: .original)

    let model = SlideshowViewModel(
        source: source,
        collectionID: "album",
        ticker: ticker,
        settingsStore: themeStore(quality: .preview)
    )
    await model.start()

    #expect(model.currentAssetID == "a")
    #expect(model.currentImageData == Data([1]))
    #expect(source.imageDataCallCount(for: "a", fidelity: .preview) == 1)
    #expect(source.imageDataCallCount(for: "a", fidelity: .original) == 0)
}

@MainActor
@Test func previewCacheEntryDoesNotSatisfyOriginalQualityRequest() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let cache = ImageCache(limit: 3)
    source.setAssets([SourceAsset(id: "a", kind: .image)], for: "album")
    source.setImageData(Data([1]), for: "a", fidelity: .preview)
    source.setImageData(Data([2]), for: "a", fidelity: .original)

    let previewModel = SlideshowViewModel(
        source: source,
        collectionID: "album",
        ticker: ticker,
        cache: cache,
        settingsStore: themeStore(quality: .preview)
    )
    await previewModel.start()

    let originalModel = SlideshowViewModel(
        source: source,
        collectionID: "album",
        ticker: ticker,
        cache: cache,
        settingsStore: themeStore(quality: .original)
    )
    await originalModel.start()

    #expect(originalModel.currentAssetID == "a")
    #expect(originalModel.currentImageData == Data([2]))
    #expect(source.imageDataCallCount(for: "a", fidelity: .preview) == 1)
    #expect(source.imageDataCallCount(for: "a", fidelity: .original) == 1)
}

@MainActor
// @covers FR-300-04
@Test func qualityChangeAppliesToNextLoadedImageWithoutRestart() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "a", kind: .image),
        SourceAsset(id: "b", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "a", fidelity: .preview)
    source.setImageData(Data([2]), for: "b", fidelity: .preview)
    source.setImageData(Data([10]), for: "a", fidelity: .original)
    source.setImageData(Data([20]), for: "b", fidelity: .original)
    let store = themeStore(quality: .preview)

    let model = SlideshowViewModel(
        source: source,
        collectionID: "album",
        ticker: ticker,
        settingsStore: store
    )
    await model.start()
    #expect(model.currentAssetID == "a")
    #expect(model.currentImageData == Data([1]))

    store.settings.quality = .original
    await model.advance()

    #expect(model.currentAssetID == "b")
    #expect(model.currentImageData == Data([20]))
    #expect(source.imageDataCallCount(for: "b", fidelity: .original) == 1)
}

// 900 R2/R6 (wire + cache compat): the RAM/disk cache key stays `"\(id)#\(quality.rawValue)"`
// byte-for-byte across the ImmichAPI→PhotoSourceProviding refactor. ThemeKit `ImageQuality`
// and PhotoSourceKit `ImageFidelity` share the "preview"/"original" raw values, so the key the
// engine writes is identical to the pre-900 one — fielded 320 disk caches keep hitting. This
// pins the literal key strings the engine produces per quality tier; a silent rename here would
// invalidate every on-disk image (SC-320 regression).
@MainActor
@Test func cacheKeysPinTheLiteralFidelityStrings() async {
    let previewCache = ImageCache(limit: 4)
    let previewSource = StubPhotoSource()
    previewSource.setAssets([SourceAsset(id: "asset", kind: .image)], for: "album")
    let previewModel = SlideshowViewModel(
        source: previewSource, collectionID: "album", ticker: ManualTicker(),
        cache: previewCache, settingsStore: themeStore(quality: .preview)
    )
    await previewModel.start()
    #expect(previewCache.contains("asset#preview"))
    #expect(!previewCache.contains("asset#original"))
    #expect(!previewCache.contains("asset#thumbnail"))

    let originalCache = ImageCache(limit: 4)
    let originalSource = StubPhotoSource()
    originalSource.setAssets([SourceAsset(id: "asset", kind: .image)], for: "album")
    let originalModel = SlideshowViewModel(
        source: originalSource, collectionID: "album", ticker: ManualTicker(),
        cache: originalCache, settingsStore: themeStore(quality: .original)
    )
    await originalModel.start()
    #expect(originalCache.contains("asset#original"))
    #expect(!originalCache.contains("asset#preview"))
}

@MainActor
private func themeStore(quality: ImageQuality) -> InMemoryThemeStore {
    InMemoryThemeStore(settings: ThemeSettings(order: .sequential, quality: quality))
}
