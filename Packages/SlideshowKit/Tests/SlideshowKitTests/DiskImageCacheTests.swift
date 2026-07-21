import Foundation
import SlideshowKit
import Testing

/// T002 — DiskImageCache contract (FR-320-03/04/09, SC-320-03/04): real files in a
/// per-test temp directory, recency stamped from an injected `now` so LRU order is
/// fully deterministic.
@Suite("DiskImageCache — byte-capped LRU on disk")
struct DiskImageCacheTests {
    private func makeCache(
        budget: Int64,
        root: URL,
        dates: MutableDateSource = MutableDateSource()
    ) -> DiskImageCache {
        DiskImageCache(root: root, budget: budget, now: { dates.now })
    }

    private func fileByteSum(in root: URL) throws -> Int64 {
        let files = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.fileSizeKey]
        )
        return try files.reduce(Int64(0)) { sum, url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return sum + Int64(size)
        }
    }

    @Test func roundTripReturnsIdenticalBytesForDistinctQualityKeys() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = makeCache(budget: 1_000, root: root)

        let preview = Data([1, 2, 3])
        let original = Data([9, 8, 7, 6])
        await cache.store(preview, forKey: "asset-1#preview")
        await cache.store(original, forKey: "asset-1#original")

        #expect(await cache.data(forKey: "asset-1#preview") == preview)
        #expect(await cache.data(forKey: "asset-1#original") == original)
        #expect(await cache.data(forKey: "asset-2#preview") == nil)
    }

    // @covers FR-320-03, SC-320-03
    @Test func usageNeverExceedsBudgetAfterAnyStore() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dates = MutableDateSource()
        let cache = makeCache(budget: 100, root: root, dates: dates)

        for index in 0..<10 {
            await cache.store(Data(repeating: UInt8(index), count: 30), forKey: "asset-\(index)")
            dates.advance(by: 1)
            #expect(await cache.currentUsage() <= 100)
        }
    }

    // @covers FR-320-03, SC-320-03
    @Test func fillingPastBudgetEvictsLeastRecentlyStampedFirst() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dates = MutableDateSource()
        let cache = makeCache(budget: 300, root: root, dates: dates)

        for key in ["a", "b", "c"] {
            await cache.store(Data(repeating: 1, count: 100), forKey: key)
            dates.advance(by: 1)
        }
        await cache.store(Data(repeating: 1, count: 100), forKey: "d")

        #expect(await cache.data(forKey: "a") == nil)
        #expect(await cache.data(forKey: "b") != nil)
        #expect(await cache.data(forKey: "c") != nil)
        #expect(await cache.data(forKey: "d") != nil)
    }

    // @covers FR-320-02, FR-320-03
    @Test func readRestampsRecencySoTheOtherEntryIsEvicted() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dates = MutableDateSource()
        let cache = makeCache(budget: 200, root: root, dates: dates)

        await cache.store(Data(repeating: 1, count: 100), forKey: "a")
        dates.advance(by: 1)
        await cache.store(Data(repeating: 2, count: 100), forKey: "b")
        dates.advance(by: 1)

        _ = await cache.data(forKey: "a")
        dates.advance(by: 1)
        await cache.store(Data(repeating: 3, count: 100), forKey: "c")

        #expect(await cache.data(forKey: "a") != nil)
        #expect(await cache.data(forKey: "b") == nil)
        #expect(await cache.data(forKey: "c") != nil)
    }

    // @covers FR-320-09
    @Test func unreadableEntryIsAMissAndGetsDeleted() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = makeCache(budget: 1_000, root: root)

        await cache.store(Data(repeating: 1, count: 100), forKey: "broken")

        // Corrupt the entry behind the actor's back: replace the file with a
        // directory so the next read fails (FR-320-09).
        let entry = root.appendingPathComponent("broken")
        try FileManager.default.removeItem(at: entry)
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: false)

        #expect(await cache.data(forKey: "broken") == nil)
        #expect(!FileManager.default.fileExists(atPath: entry.path))
        #expect(await cache.currentUsage() == 0)
    }

    // @covers FR-320-03, SC-320-03
    @Test func entryLargerThanTheWholeBudgetIsNotPersisted() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = makeCache(budget: 50, root: root)

        await cache.store(Data(repeating: 1, count: 40), forKey: "small")
        await cache.store(Data(repeating: 2, count: 100), forKey: "huge")

        #expect(await cache.data(forKey: "huge") == nil)
        #expect(await cache.data(forKey: "small") != nil)
        #expect(await cache.currentUsage() <= 50)
    }

    // @covers FR-320-03, FR-320-04, SC-320-04
    @Test func loweringTheBudgetPrunesImmediately() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dates = MutableDateSource()
        let cache = makeCache(budget: 1_000, root: root, dates: dates)

        for key in ["a", "b", "c"] {
            await cache.store(Data(repeating: 1, count: 100), forKey: key)
            dates.advance(by: 1)
        }

        await cache.setBudget(150)

        #expect(await cache.currentUsage() <= 150)
        #expect(await cache.data(forKey: "a") == nil)
        #expect(await cache.data(forKey: "b") == nil)
        #expect(await cache.data(forKey: "c") != nil)
    }

    // @covers SC-320-04
    @Test func clearRemovesEveryEntryAndZeroesUsage() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = makeCache(budget: 1_000, root: root)

        await cache.store(Data(repeating: 1, count: 100), forKey: "a")
        await cache.store(Data(repeating: 2, count: 100), forKey: "b")
        await cache.clear()

        #expect(await cache.currentUsage() == 0)
        #expect(await cache.data(forKey: "a") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func usageAccountingMatchesTheFileByteSum() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dates = MutableDateSource()
        let cache = makeCache(budget: 250, root: root, dates: dates)

        for index in 0..<6 {
            await cache.store(Data(repeating: UInt8(index), count: 60 + index), forKey: "asset-\(index)")
            dates.advance(by: 1)
            let usage = await cache.currentUsage()
            #expect(usage == (try fileByteSum(in: root)))
        }
    }

    @Test func cacheKeysAreSanitizedForTheFilesystem() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = makeCache(budget: 1_000, root: root)

        await cache.store(Data([1]), forKey: "asset-1#preview")

        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(files == ["asset-1_preview"])
    }

    @Test func aFreshInstanceOverAnExistingRootSeesPriorEntries() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dates = MutableDateSource()

        let first = makeCache(budget: 1_000, root: root, dates: dates)
        await first.store(Data(repeating: 1, count: 100), forKey: "a")
        dates.advance(by: 1)
        await first.store(Data(repeating: 2, count: 50), forKey: "b")

        let second = makeCache(budget: 1_000, root: root, dates: dates)
        #expect(await second.currentUsage() == 150)
        #expect(await second.data(forKey: "a") == Data(repeating: 1, count: 100))
    }

    // @covers FR-320-09
    @Test func writeFailureIsSwallowedAndPlaybackNeverNotices() async throws {
        let root = try makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: root.path
            )
            try? FileManager.default.removeItem(at: root)
        }
        let cache = makeCache(budget: 1_000, root: root)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: root.path
        )

        await cache.store(Data(repeating: 1, count: 100), forKey: "a")

        #expect(await cache.currentUsage() == 0)
        #expect(await cache.data(forKey: "a") == nil)
    }

    @Test func initCreatesAMissingRootDirectory() async throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("nested/ImageCache", isDirectory: true)
        let cache = makeCache(budget: 1_000, root: root)

        await cache.store(Data([1, 2]), forKey: "a")

        #expect(await cache.data(forKey: "a") == Data([1, 2]))
    }
}

/// T002 (budget half) — CacheBudget steps/default + UserDefaults round-trip (FR-320-04).
@Suite("CacheBudget — fixed steps and persistence")
struct CacheBudgetTests {
    // @covers FR-320-04
    @Test func stepsAreTheFiveFixedSizesWithHalfAGigabyteDefault() {
        let megabyte: Int64 = 1_000_000
        #expect(CacheBudget.steps.map(\.bytes) == [
            100 * megabyte, 250 * megabyte, 500 * megabyte,
            1_000 * megabyte, 2_000 * megabyte,
        ])
        #expect(CacheBudget.default.bytes == 500 * megabyte)
        #expect(CacheBudget.steps.contains(CacheBudget.default))
    }

    // @covers FR-320-04
    @Test func userDefaultsStoreRoundTripsAndDefaultsWhenUnset() {
        let suiteName = "CacheBudgetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsCacheBudgetStore(defaults: defaults)
        #expect(store.load() == CacheBudget.default)

        let oneGigabyte = CacheBudget.steps[3]
        store.save(oneGigabyte)
        #expect(store.load() == oneGigabyte)

        let reread = UserDefaultsCacheBudgetStore(defaults: defaults)
        #expect(reread.load() == oneGigabyte)
    }
}
