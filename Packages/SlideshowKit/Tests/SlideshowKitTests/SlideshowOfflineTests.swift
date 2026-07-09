//
//  SlideshowOfflineTests.swift
//  SlideshowKitTests
//
//  320 — disk image cache: engine scenarios against StubImmichAPI + TestClock +
//  the REAL DiskImageCache/FileSourceSnapshotStore in per-test temp directories
//  (quickstart "Engine scenarios → tests"). No real timers, no network.
//

import Foundation
import ImmichClient
import Testing
import ThemeKit
import ThemeKitTestSupport
@testable import SlideshowKit

/// Bounded yield loop (same pattern as SlideshowResilienceTests): lets detached
/// work hop actors without real time. Passing `false` just settles the executor.
@MainActor
private func waitUntil(_ condition: @autoclosure () -> Bool) async {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
}

/// Polls the disk tier until the key appears — the write-through is
/// fire-and-forget off the display path (FR-320-11), so tests must wait for the
/// bytes, not assume them. Returns the stored bytes, or nil on timeout.
@discardableResult
private func waitForDiskEntry(_ disk: DiskImageCache, _ key: String) async -> Data? {
    for _ in 0..<500 {
        if let data = await disk.data(forKey: key) {
            return data
        }
        await Task.yield()
    }
    return nil
}

// MARK: - US1: The whole album keeps playing when the network breaks (T007)

@Suite("Offline US1 — whole album keeps playing")
@MainActor
struct OfflinePlaybackTests {
    // FR-320-01 (scenario 1): every photo the show displays or prefetches lands
    // on disk, byte-identical, under its quality-variant key.
    @Test func shownAndPrefetchedPhotosAreWrittenThroughToDisk() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskImageCache(root: root, budget: 10_000_000)
        let api = StubImmichAPI()
        api.setAssets([
            Asset(id: "image-1", type: "IMAGE"),
            Asset(id: "image-2", type: "IMAGE"),
            Asset(id: "image-3", type: "IMAGE")
        ], for: "album")
        api.setPreviewData(Data([1]), for: "image-1")
        api.setPreviewData(Data([2]), for: "image-2")
        api.setPreviewData(Data([3]), for: "image-3")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ManualTicker(), clock: TestClock(),
            diskCache: disk,
            cache: ImageCache(limit: 2),
            config: SlideshowConfig(prefetchDepth: 1, cacheLimit: 2),
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        #expect(model.currentAssetID == "image-1")

        // The shown photo and the prefetched neighbor both persist.
        #expect(await waitForDiskEntry(disk, "image-1#preview") == Data([1]))
        #expect(await waitForDiskEntry(disk, "image-2#preview") == Data([2]))
        // The never-shown, never-prefetched photo does not.
        #expect(await disk.data(forKey: "image-3#preview") == nil)
    }

    // FR-320-02 + SC-320-05 (scenario 2): a photo evicted from RAM but present
    // on disk is shown with zero network requests, and the RAM tier is
    // repopulated by the hit.
    @Test func diskHitMakesNoNetworkRequestAndRepopulatesRAM() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskImageCache(root: root, budget: 10_000_000)
        let api = StubImmichAPI()
        let cache = ImageCache(limit: 2)
        api.setAssets([
            Asset(id: "image-1", type: "IMAGE"),
            Asset(id: "image-2", type: "IMAGE")
        ], for: "album")
        api.setPreviewData(Data([1]), for: "image-1")
        api.setPreviewData(Data([2]), for: "image-2")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ManualTicker(), clock: TestClock(),
            diskCache: disk,
            cache: cache,
            config: SlideshowConfig(prefetchDepth: 1, cacheLimit: 2),
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        await waitForDiskEntry(disk, "image-2#preview")

        // Evict the RAM tier entirely; the disk keeps its copies.
        cache.store(Data([9]), for: "unrelated-1")
        cache.store(Data([10]), for: "unrelated-2")
        let networkCalls = api.previewCallCount

        await model.advance()

        #expect(model.currentAssetID == "image-2")
        #expect(model.currentImageData == Data([2]))
        #expect(model.failureReason == nil)
        // Zero new fetches: the shown photo AND the re-pointed prefetch both
        // came from disk.
        await waitUntil(cache.contains("image-1#preview"))
        #expect(api.previewCallCount == networkCalls)
        // The disk hit repopulated RAM for the shown photo.
        #expect(cache.contains("image-2#preview"))
    }

    // US1 + SC-320-01 (scenario 3): after one full pass, cutting the network
    // still rotates the ENTIRE album from disk — not just the RAM handful —
    // with zero network image requests and no error surface.
    @Test func wholeAlbumKeepsRotatingOfflineAfterOnePass() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskImageCache(root: root, budget: 10_000_000)
        let api = StubImmichAPI()
        let cache = ImageCache(limit: 2)
        let ids = ["image-1", "image-2", "image-3", "image-4"]
        api.setAssets(ids.map { Asset(id: $0, type: "IMAGE") }, for: "album")
        for (index, id) in ids.enumerated() {
            api.setPreviewData(Data([UInt8(index + 1)]), for: id)
        }

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ManualTicker(), clock: TestClock(),
            diskCache: disk,
            cache: cache,
            config: SlideshowConfig(prefetchDepth: 1, cacheLimit: 2),
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        for _ in 0..<3 {
            await model.advance()
        }
        #expect(model.currentAssetID == "image-4")

        // The full pass put every photo on disk (RAM only ever held 2).
        for id in ids {
            #expect(await waitForDiskEntry(disk, "\(id)#preview") != nil, "missing \(id)")
        }

        // Wi-Fi drops: every image fetch fails from here on.
        for id in ids {
            api.setPreviewError(ImmichError.unreachable, for: id)
        }
        let networkCalls = api.previewCallCount

        // A full offline cycle: every photo appears, in order, from disk.
        for expected in ["image-1", "image-2", "image-3", "image-4"] {
            await model.advance()
            #expect(model.currentAssetID == expected)
            #expect(model.currentImageData != nil)
            #expect(model.phase == .playing)
            #expect(model.failureReason == nil)
        }
        await waitUntil(false)   // settle stray prefetch tasks
        #expect(api.previewCallCount == networkCalls)
    }
}
