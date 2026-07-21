import Foundation
import SlideshowKit
import Testing

// @covers FR-300-07
@Test func storeEvictsLeastRecentlyStoredEntryWhenLimitIsExceeded() {
    let cache = ImageCache(limit: 2)

    cache.store(Data([1]), for: "one")
    cache.store(Data([2]), for: "two")
    cache.store(Data([3]), for: "three")

    #expect(cache.count == 2)
    #expect(!cache.contains("one"))
    #expect(cache.contains("two"))
    #expect(cache.contains("three"))
}

@Test func dataLookupRefreshesLRUPosition() {
    let cache = ImageCache(limit: 2)
    cache.store(Data([1]), for: "one")
    cache.store(Data([2]), for: "two")

    #expect(cache.data(for: "one") == Data([1]))
    cache.store(Data([3]), for: "three")

    #expect(cache.contains("one"))
    #expect(!cache.contains("two"))
    #expect(cache.contains("three"))
}

@Test func containsDoesNotRefreshLRUPosition() {
    let cache = ImageCache(limit: 2)
    cache.store(Data([1]), for: "one")
    cache.store(Data([2]), for: "two")

    #expect(cache.contains("one"))
    cache.store(Data([3]), for: "three")

    #expect(!cache.contains("one"))
    #expect(cache.contains("two"))
    #expect(cache.contains("three"))
}

@Test func storeOverwritesExistingKeyWithoutGrowingCountAndRefreshesLRUPosition() {
    let cache = ImageCache(limit: 2)

    cache.store(Data([1]), for: "one")
    cache.store(Data([2]), for: "two")
    cache.store(Data([10]), for: "one")

    #expect(cache.count == 2)
    #expect(cache.data(for: "one") == Data([10]))

    cache.store(Data([3]), for: "three")

    #expect(cache.count == 2)
    #expect(!cache.contains("two"))
    #expect(cache.contains("one"))
    #expect(cache.contains("three"))
}

@Test func dataReturnsNilForUnknownKey() {
    let cache = ImageCache(limit: 2)

    #expect(cache.data(for: "unknown") == nil)
}
