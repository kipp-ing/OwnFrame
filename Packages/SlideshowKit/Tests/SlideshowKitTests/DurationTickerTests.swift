import Foundation
import PhotoSourceKit
import PhotoSourceTestSupport
import SlideshowKit
import ThemeKit
import ThemeKitTestSupport
import Testing

// US1 — the live-duration ticker. The engine reads settings.duration on the main actor
// at the top of each cycle and waits that value, so a duration change re-arms the timer
// on the next cycle without restarting the show (SC-001, review R1).

@MainActor
@Test func tickerWaitsCurrentDurationAndReArmsWhenDurationChangesMidShow() async {
    let source = StubPhotoSource()
    let ticker = ManualTicker()
    source.setAssets([
        SourceAsset(id: "image-1", kind: .image),
        SourceAsset(id: "image-2", kind: .image)
    ], for: "album")
    source.setImageData(Data([1]), for: "image-1", fidelity: .preview)
    source.setImageData(Data([2]), for: "image-2", fidelity: .preview)
    let store = InMemoryThemeStore(settings: ThemeSettings(order: .sequential, duration: .seconds(15)))

    let model = SlideshowViewModel(source: source, collectionID: "album", ticker: ticker, settingsStore: store)
    await model.start()

    // First cycle waits the current duration.
    await ticker.waitUntilWaiting()
    #expect(ticker.lastRequestedDuration == .seconds(15))

    // Change the duration live, then let the current wait complete.
    store.settings.duration = .seconds(30)
    ticker.tick()
    await ticker.waitUntilConsumedTickCount(1)
    await waitUntil(model.currentAssetID == "image-2")
    #expect(model.currentAssetID == "image-2")

    // The next cycle re-arms with the new duration — no restart.
    await ticker.waitUntilWaiting()
    #expect(ticker.lastRequestedDuration == .seconds(30))
}

@MainActor
private func waitUntil(_ condition: @autoclosure () -> Bool) async {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
}
