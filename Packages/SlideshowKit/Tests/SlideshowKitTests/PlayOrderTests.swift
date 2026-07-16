import Foundation
import PhotoSourceKit
import PhotoSourceTestSupport
import SlideshowKit
import ThemeKit
import ThemeKitTestSupport
import Testing

// US1 — the play sequence honors settings.order. Sequential walks the album in order
// and wraps; shuffle shows every photo once per cycle, then reshuffles (SC-004).

@MainActor
@Test func sequentialOrderVisitsAlbumOrderAndWraps() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let assets = (1...3).map { SourceAsset(id: "image-\($0)", kind: .image) }
    source.setAssets(assets, for: "album")
    for value in 1...3 {
        source.setImageData(Data([UInt8(value)]), for: "image-\(value)", fidelity: .preview)
    }
    let store = InMemoryThemeStore(settings: ThemeSettings(order: .sequential))

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: store)
    await model.start()

    var shown = [model.currentAssetID]
    for _ in 0..<5 {
        await model.advance()
        shown.append(model.currentAssetID)
    }

    #expect(shown == ["image-1", "image-2", "image-3", "image-1", "image-2", "image-3"])
}

@MainActor
@Test func shuffleShowsEveryPhotoOncePerCycleThenReshuffles() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let count = 6
    let assets = (1...count).map { SourceAsset(id: "image-\($0)", kind: .image) }
    source.setAssets(assets, for: "album")
    for value in 1...count {
        source.setImageData(Data([UInt8(value)]), for: "image-\(value)", fidelity: .preview)
    }
    let store = InMemoryThemeStore(settings: ThemeSettings(order: .shuffle))

    let model = SlideshowViewModel(
        source: source,
        collectionID: "album",
        ticker: ticker,
        settingsStore: store,
        rng: SeededRandomNumberGenerator(seed: 0xCAFE)
    )
    await model.start()

    // Cycle 1 = the first image plus (count - 1) advances.
    var cycle1 = [model.currentAssetID]
    for _ in 0..<(count - 1) {
        await model.advance()
        cycle1.append(model.currentAssetID)
    }

    // Cycle 2 = the next `count` advances (a fresh permutation).
    var cycle2: [String?] = []
    for _ in 0..<count {
        await model.advance()
        cycle2.append(model.currentAssetID)
    }

    let allIDs = Set(assets.map { $0.id as String? })
    // Every photo exactly once per cycle (no repeat before all are shown — SC-004).
    #expect(Set(cycle1).count == count)
    #expect(Set(cycle1) == allIDs)
    #expect(Set(cycle2).count == count)
    #expect(Set(cycle2) == allIDs)
    // The new cycle is a fresh shuffle, and does not immediately repeat the last photo.
    #expect(cycle2.first != cycle1.last)
}

@MainActor
@Test func switchingOrderMidShowKeepsCurrentPhotoAsAnchor() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    let assets = (1...4).map { SourceAsset(id: "image-\($0)", kind: .image) }
    source.setAssets(assets, for: "album")
    for value in 1...4 {
        source.setImageData(Data([UInt8(value)]), for: "image-\(value)", fidelity: .preview)
    }
    let store = InMemoryThemeStore(settings: ThemeSettings(order: .sequential))

    let model = SlideshowViewModel(
        source: source,
        collectionID: "album",
        ticker: ticker,
        settingsStore: store,
        rng: SeededRandomNumberGenerator(seed: 7)
    )
    await model.start()
    await model.advance() // now on image-2
    #expect(model.currentAssetID == "image-2")

    // Switch to shuffle mid-show: the current photo stays put; the next advance
    // follows the new order from here (no restart, no lost photo).
    store.settings.order = .shuffle
    let anchored = model.currentAssetID
    #expect(anchored == "image-2")

    await model.advance()
    #expect(model.currentAssetID != nil)
    #expect(model.phase == .playing)
}
