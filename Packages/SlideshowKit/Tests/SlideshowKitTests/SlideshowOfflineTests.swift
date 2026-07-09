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

// MARK: - US2: The frame survives an offline relaunch (T009)

@Suite("Offline US2 — relaunch survival")
@MainActor
struct OfflineRelaunchTests {
    private let ids = ["image-1", "image-2", "image-3"]

    /// First app run: play the album far enough that the snapshot is saved and
    /// every photo is on disk, then tear the engine down (power cut).
    private func playFirstRun(
        api: StubImmichAPI, disk: DiskImageCache, snapshots: FileSourceSnapshotStore
    ) async {
        api.setAssets(ids.map { Asset(id: $0, type: "IMAGE") }, for: "album")
        for (index, id) in ids.enumerated() {
            api.setPreviewData(Data([UInt8(index + 1)]), for: id)
        }
        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ManualTicker(), clock: TestClock(),
            diskCache: disk, snapshots: snapshots,
            cache: ImageCache(limit: 2),
            config: SlideshowConfig(prefetchDepth: 1, cacheLimit: 2),
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        await model.advance()
        for id in ids {
            _ = await waitForDiskEntry(disk, "\(id)#preview")
        }
        model.pause()   // park every timer before the "power cut"
    }

    private func makeRelaunchedModel(
        api: StubImmichAPI, disk: DiskImageCache, snapshots: FileSourceSnapshotStore,
        clock: TestClock, ticker: ManualTicker = ManualTicker()
    ) -> SlideshowViewModel {
        SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            diskCache: disk, snapshots: snapshots,
            cache: ImageCache(limit: 2),
            config: SlideshowConfig(prefetchDepth: 1, cacheLimit: 2),
            settingsStore: sequentialThemeStore()
        )
    }

    // US2-1 + SC-320-02 + FR-320-06/07 (scenario 4): relaunch with the source
    // dead plays the remembered list from disk — no error screen, no user
    // input; the fetch was attempted, and the sourceReload retry is armed.
    @Test func offlineRelaunchPlaysFromTheRememberedList() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let api = StubImmichAPI()
        let disk = DiskImageCache(root: root.appendingPathComponent("images"), budget: 10_000_000)
        let snapshots = FileSourceSnapshotStore(root: root.appendingPathComponent("snapshots"))
        await playFirstRun(api: api, disk: disk, snapshots: snapshots)
        #expect(snapshots.load(forKey: "album")?.map(\.id) == ids)   // FR-320-06

        // Relaunch: router still rebooting — the list fetch fails.
        api.setAssetsError(ImmichError.unreachable, for: "album")
        let clock = TestClock()
        let calls0 = api.assetsCallCount
        let model = makeRelaunchedModel(api: api, disk: disk, snapshots: snapshots, clock: clock)
        await model.start()

        #expect(api.assetsCallCount == calls0 + 1)   // live fetch was attempted
        #expect(model.phase == .playing)             // …but the show still starts
        #expect(model.currentAssetID == "image-1")
        #expect(model.currentImageData == Data([1]))
        #expect(model.failureReason == .transient)   // degraded, not broken
        await clock.waitUntilSleeperCount(1)         // the retry is armed
        #expect(clock.sleeperCount >= 1)
    }

    // US2-2 (scenario 5): when the retry reaches the server, the live list
    // replaces the remembered one via 310's reconciliation — an asset added
    // server-side enters the rotation and the snapshot is replaced.
    @Test func recoveryAfterSnapshotStartMergesTheLiveList() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let api = StubImmichAPI()
        let disk = DiskImageCache(root: root.appendingPathComponent("images"), budget: 10_000_000)
        let snapshots = FileSourceSnapshotStore(root: root.appendingPathComponent("snapshots"))
        await playFirstRun(api: api, disk: disk, snapshots: snapshots)

        api.setAssetsError(ImmichError.unreachable, for: "album")
        let clock = TestClock()
        let ticker = ManualTicker()
        let model = makeRelaunchedModel(
            api: api, disk: disk, snapshots: snapshots, clock: clock, ticker: ticker
        )
        await model.start()
        #expect(model.phase == .playing)

        // The network returns — with a new photo in the album.
        let grown = ids + ["image-4"]
        api.setAssets(grown.map { Asset(id: $0, type: "IMAGE") }, for: "album")
        api.setPreviewData(Data([4]), for: "image-4")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(1200))
        await waitUntil(model.failureReason == nil)

        #expect(model.failureReason == nil)
        #expect(model.currentAssetID == "image-1")               // undisturbed
        #expect(snapshots.load(forKey: "album")?.map(\.id) == grown)   // replaced

        // The addition joins the rotation without a restart.
        for expected in ["image-2", "image-3", "image-4"] {
            await ticker.waitUntilWaiting()
            ticker.tick()
            await waitUntil(model.currentAssetID == expected)
            #expect(model.currentAssetID == expected)
        }
    }

    // US1-4/US2-2 regression (found in sim bug hunt 2026-07-09): an offline
    // advance that succeeds FROM DISK must not count as "the recovery" — in
    // 310 a successful step proved the network worked, but a disk hit proves
    // nothing. If it cancels the sourceReload retry (and no refresh is armed
    // because no fetch ever succeeded in this process), the engine stops
    // trying to reach the server forever: the network's return goes unnoticed.
    @Test func offlineAdvancesDoNotKillTheSourceRetry() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let api = StubImmichAPI()
        let disk = DiskImageCache(root: root.appendingPathComponent("images"), budget: 10_000_000)
        let snapshots = FileSourceSnapshotStore(root: root.appendingPathComponent("snapshots"))
        await playFirstRun(api: api, disk: disk, snapshots: snapshots)

        api.setAssetsError(ImmichError.unreachable, for: "album")
        let clock = TestClock()
        let ticker = ManualTicker()
        let model = makeRelaunchedModel(
            api: api, disk: disk, snapshots: snapshots, clock: clock, ticker: ticker
        )
        await model.start()
        #expect(model.phase == .playing)

        // The frame advances twice from disk while the server is still dead —
        // exactly what a wall frame does for however long the outage lasts.
        for _ in 0..<2 {
            let before = model.currentAssetID
            await ticker.waitUntilWaiting()
            ticker.tick()
            await waitUntil(model.currentAssetID != before)
            #expect(model.currentAssetID != before)
        }
        // Stale-but-working stays marked as degraded (FR-320-07: failureReason
        // stays set until live data is back).
        #expect(model.failureReason == .transient)

        // The router reboots — with a new photo in the album. The retry chain
        // must still be alive to notice, whatever backoff attempt it is on:
        // release every parked timer generously.
        let grown = ids + ["image-4"]
        api.setAssets(grown.map { Asset(id: $0, type: "IMAGE") }, for: "album")
        api.setPreviewData(Data([4]), for: "image-4")
        let callsBefore = api.assetsCallCount
        for _ in 0..<10 {
            clock.advance(by: .seconds(360))
            await waitUntil(api.assetsCallCount > callsBefore)
            if api.assetsCallCount > callsBefore {
                break
            }
        }
        await waitUntil(model.failureReason == nil)

        #expect(api.assetsCallCount > callsBefore, "the engine must still be fetching")
        #expect(model.failureReason == nil)
        #expect(snapshots.load(forKey: "album")?.map(\.id) == grown)   // live list adopted
    }

    // US2-4 + SC-320-06 (scenario 6): remembered list present but the stored
    // photos were purged — calm error state with the retry armed, no crash.
    @Test func purgedPhotosDegradeToTheCalmErrorState() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let api = StubImmichAPI()
        let imagesRoot = root.appendingPathComponent("images")
        let disk = DiskImageCache(root: imagesRoot, budget: 10_000_000)
        let snapshots = FileSourceSnapshotStore(root: root.appendingPathComponent("snapshots"))
        await playFirstRun(api: api, disk: disk, snapshots: snapshots)

        // iOS reclaimed the cache directory; the network is also down.
        try FileManager.default.removeItem(at: imagesRoot)
        api.setAssetsError(ImmichError.unreachable, for: "album")
        for id in ids {
            api.setPreviewError(ImmichError.unreachable, for: id)
        }

        let clock = TestClock()
        let freshDisk = DiskImageCache(root: imagesRoot, budget: 10_000_000)
        let model = makeRelaunchedModel(api: api, disk: freshDisk, snapshots: snapshots, clock: clock)
        await model.start()

        #expect(model.phase == .failed)
        #expect(model.failureReason == .transient)
        #expect(model.currentImageData == nil)
        await clock.waitUntilSleeperCount(1)   // auto-retry runs behind the calm state
        #expect(clock.sleeperCount >= 1)
    }

    // US2-3 (scenario 7): no snapshot for the active source — the launch
    // behaves exactly like 310's dead-server scenario, recovery included.
    @Test func launchWithoutASnapshotKeeps310BehaviorVerbatim() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let api = StubImmichAPI()
        let disk = DiskImageCache(root: root.appendingPathComponent("images"), budget: 10_000_000)
        let snapshots = FileSourceSnapshotStore(root: root.appendingPathComponent("snapshots"))
        api.setAssetsError(ImmichError.unreachable, for: "album")

        let clock = TestClock()
        let model = makeRelaunchedModel(api: api, disk: disk, snapshots: snapshots, clock: clock)
        await model.start()

        #expect(model.phase == .failed)
        #expect(model.failureReason == .transient)

        // The server returns before the first retry fires — playback starts by
        // itself (310 US1-2).
        api.setAssets([Asset(id: "image-9", type: "IMAGE")], for: "album")
        api.setPreviewData(Data([9]), for: "image-9")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(1200))
        await waitUntil(model.phase == .playing)

        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-9")
        #expect(model.failureReason == nil)
        #expect(snapshots.load(forKey: "album")?.map(\.id) == ["image-9"])
    }
}

// MARK: - US3: Clear cache semantics at the engine (T011)

@Suite("Offline US3 — Clear never touches the on-screen photo")
@MainActor
struct ClearCacheSemanticsTests {
    // US3-4/5 + FR-320-05 (scenario 8): clearing both stores mid-show leaves
    // the current photo and phase untouched; the next advance (online)
    // re-fetches from the network and re-fills the cache — no restart needed.
    @Test func clearingBothStoresMidShowKeepsPlayingAndRefills() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let api = StubImmichAPI()
        let disk = DiskImageCache(root: root.appendingPathComponent("images"), budget: 10_000_000)
        let snapshots = FileSourceSnapshotStore(root: root.appendingPathComponent("snapshots"))
        let cache = ImageCache(limit: 2)
        api.setAssets([
            Asset(id: "image-1", type: "IMAGE"),
            Asset(id: "image-2", type: "IMAGE")
        ], for: "album")
        api.setPreviewData(Data([1]), for: "image-1")
        api.setPreviewData(Data([2]), for: "image-2")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ManualTicker(), clock: TestClock(),
            diskCache: disk, snapshots: snapshots,
            cache: cache,
            config: SlideshowConfig(prefetchDepth: 1, cacheLimit: 2),
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        await waitForDiskEntry(disk, "image-2#preview")

        // The user taps Clear in Settings (both stores) — mid-show.
        await disk.clear()
        snapshots.clear()

        // The on-screen photo is not interrupted (FR-320-05).
        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-1")
        #expect(model.currentImageData == Data([1]))
        #expect(await disk.currentUsage() == 0)
        #expect(snapshots.load(forKey: "album") == nil)

        // Next advance while online: RAM still holds the prefetched neighbor,
        // so empty it too — the photo must come from the network again.
        cache.store(Data([8]), for: "unrelated-1")
        cache.store(Data([9]), for: "unrelated-2")
        let networkCalls = api.previewCallCount(for: "image-2")

        await model.advance()

        #expect(model.currentAssetID == "image-2")
        #expect(model.currentImageData == Data([2]))
        #expect(api.previewCallCount(for: "image-2") == networkCalls + 1)
        // …and the fetch re-filled the disk cache as it played (US3-5).
        #expect(await waitForDiskEntry(disk, "image-2#preview") == Data([2]))
    }
}
