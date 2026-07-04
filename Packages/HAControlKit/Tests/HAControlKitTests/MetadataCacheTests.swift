import Foundation
import HAControlKit
import Testing

@Test func storeEvictsLeastRecentlyUsedEntryWhenLimitIsExceeded() {
    let cache = MetadataCache(limit: 2)

    cache.store(CachedMetadata(takenAt: nil, city: nil, state: nil, country: nil), for: "a")
    cache.store(CachedMetadata(takenAt: nil, city: nil, state: nil, country: nil), for: "b")
    cache.store(CachedMetadata(takenAt: nil, city: nil, state: nil, country: nil), for: "c")

    #expect(cache.count == 2)
    #expect(cache.metadata(for: "a") == nil)
    #expect(cache.metadata(for: "b") != nil)
    #expect(cache.metadata(for: "c") != nil)
}

@Test func metadataLookupRefreshesLRUPosition() {
    let cache = MetadataCache(limit: 2)
    cache.store(CachedMetadata(takenAt: nil, city: nil, state: nil, country: nil), for: "a")
    cache.store(CachedMetadata(takenAt: nil, city: nil, state: nil, country: nil), for: "b")

    _ = cache.metadata(for: "a")
    cache.store(CachedMetadata(takenAt: nil, city: nil, state: nil, country: nil), for: "c")

    #expect(cache.metadata(for: "a") != nil)
    #expect(cache.metadata(for: "b") == nil)
    #expect(cache.metadata(for: "c") != nil)
}

@Test func storeOverwritesExistingKeyWithoutGrowingCount() {
    let cache = MetadataCache(limit: 2)

    let metadata1 = CachedMetadata(takenAt: nil, city: "Berlin", state: nil, country: "DE")
    let metadata2 = CachedMetadata(takenAt: nil, city: nil, state: nil, country: nil)

    cache.store(metadata1, for: "a")
    cache.store(metadata2, for: "b")
    cache.store(metadata1, for: "a")

    #expect(cache.count == 2)
    #expect(cache.metadata(for: "a")?.city == "Berlin")

    cache.store(CachedMetadata(takenAt: nil, city: nil, state: nil, country: nil), for: "c")

    #expect(cache.count == 2)
    #expect(cache.metadata(for: "b") == nil)
    #expect(cache.metadata(for: "a") != nil)
    #expect(cache.metadata(for: "c") != nil)
}

@Test func metadataReturnsNilForUnknownKey() {
    let cache = MetadataCache(limit: 2)

    #expect(cache.metadata(for: "unknown") == nil)
}
