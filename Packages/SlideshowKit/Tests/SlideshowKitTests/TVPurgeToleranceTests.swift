//
//  TVPurgeToleranceTests.swift
//  SlideshowKitTests
//
//  1000 (Apple TV) US3 — "survives tvOS storage reality": a cold start after a
//  full purge of purgeable storage reaches the first photo with no user input and
//  the disk cache re-fills. This exercises the EXISTING topic-320 purge-tolerance
//  paths (the real DiskImageCache + FileSourceSnapshotStore, in per-test temp
//  directories) as the *normal* tvOS case, not the offline edge case. The server is
//  reachable throughout — contrast
//  SlideshowOfflineTests.purgedPhotosDegradeToTheCalmErrorState, which is the purge
//  + dead-network edge case that degrades to the calm error state. No real timers,
//  no network.
//
//  Traceability: FR-1000-04 / SC-1000-03.
//

import Foundation
import PhotoSourceKit
import PhotoSourceTestSupport
import Testing
import ThemeKit
import ThemeKitTestSupport
@testable import SlideshowKit

/// Bounded yield loop (mirrors SlideshowOfflineTests): lets detached work hop actors
/// without real time. File-private here because the offline suite's copy is too.
@MainActor
private func waitUntil(_ condition: @autoclosure () -> Bool) async {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
}

/// Polls the disk tier until the key appears — the write-through is fire-and-forget
/// off the display path (FR-320-11), so tests must wait for the bytes, not assume
/// them. Returns the stored bytes, or nil on timeout.
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

// MARK: - US3: Survives tvOS storage reality (T013)

@Suite("1000 US3 — survives tvOS storage reality (purge as the normal case)")
@MainActor
struct TVPurgeToleranceTests {
    private let ids = ["image-1", "image-2", "image-3"]

    /// First app run on the Apple TV: play far enough that the snapshot is saved and
    /// every shown/prefetched photo lands on disk, then park every timer (power cut /
    /// app not running). Reuses the 320 offline harness verbatim (StubPhotoSource +
    /// ManualTicker + TestClock + the REAL DiskImageCache/FileSourceSnapshotStore).
    private func playFirstRun(
        source: StubPhotoSource, disk: DiskImageCache, snapshots: FileSourceSnapshotStore
    ) async {
        source.setAssets(ids.map { SourceAsset(id: $0, kind: .image) }, for: "album")
        for (index, id) in ids.enumerated() {
            source.setImageData(Data([UInt8(index + 1)]), for: id, fidelity: .preview)
        }
        let model = SlideshowViewModel(
            source: source, collectionID: "album", ticker: ManualTicker(), clock: TestClock(),
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

    // FR-1000-04 + SC-1000-03 (US3 scenario 1): tvOS wiped ALL purgeable storage —
    // the image cache AND the source snapshots — while the app was not running. On
    // the next cold start with the server reachable, the engine re-hydrates from the
    // network by itself: it reaches the first photo with ZERO user interaction and
    // ZERO error surface, and the disk cache re-fills as it plays. This is 320's
    // purge tolerance (FR-320-09) exercised as the *normal* tvOS case (US3), not the
    // offline edge case.
    @Test func coldStartAfterFullPurgeReachesFirstPhotoAndRefills() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let imagesRoot = root.appendingPathComponent("images")
        let snapshotsRoot = root.appendingPathComponent("snapshots")
        let source = StubPhotoSource()
        let disk = DiskImageCache(root: imagesRoot, budget: 10_000_000)
        let snapshots = FileSourceSnapshotStore(root: snapshotsRoot)

        // Run once so real image bytes and a real snapshot exist on "disk".
        await playFirstRun(source: source, disk: disk, snapshots: snapshots)
        #expect(snapshots.load(forKey: "album")?.map(\.id) == ids)   // FR-320-06
        #expect(try !FileManager.default.contentsOfDirectory(atPath: imagesRoot.path).isEmpty)

        // The full purge of purgeable storage while the app is NOT running: the whole
        // cache root — images *and* snapshots — is reclaimed.
        try FileManager.default.removeItem(at: root)
        #expect(!FileManager.default.fileExists(atPath: imagesRoot.path))
        #expect(snapshots.load(forKey: "album") == nil)   // nothing survived the purge

        // Cold start — server reachable (the normal tvOS reboot). Fresh engine deps
        // over the purged roots; no user input beyond the launch itself.
        let freshDisk = DiskImageCache(root: imagesRoot, budget: 10_000_000)
        let freshSnapshots = FileSourceSnapshotStore(root: snapshotsRoot)
        let model = SlideshowViewModel(
            source: source, collectionID: "album", ticker: ManualTicker(), clock: TestClock(),
            diskCache: freshDisk, snapshots: freshSnapshots,
            cache: ImageCache(limit: 2),
            config: SlideshowConfig(prefetchDepth: 1, cacheLimit: 2),
            settingsStore: sequentialThemeStore()
        )
        await model.start()

        // Reaches the first photo, silently, with no error surface (SC-1000-03).
        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-1")
        #expect(model.currentImageData == Data([1]))
        #expect(model.failureReason == nil)

        // The cache re-fills as it plays: the shown photo is back on disk and a file
        // reappears under the recreated cache root (FR-1000-04, 320's write-through).
        #expect(await waitForDiskEntry(freshDisk, "image-1#preview") == Data([1]))
        #expect(try !FileManager.default.contentsOfDirectory(atPath: imagesRoot.path).isEmpty)
    }
}
