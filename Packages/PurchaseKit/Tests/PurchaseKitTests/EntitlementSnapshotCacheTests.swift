import Foundation
import Testing
@testable import PurchaseKit

// T008 — RED tests for the persisted entitlement snapshot (data-model.md §EntitlementSnapshot).
//
// Every test runs against its OWN `UserDefaults` suite (`DefaultsFixture`), injected into the
// cache and torn down afterwards — `.standard` is never touched.

/// The one versioned key the cache is allowed to own (data-model.md).
private let storageKey = "purchase.entitlements.v1"

// MARK: - Round trip

// @covers FR-1100-10
@Test func snapshotRoundTripsThroughTheInjectedSuite() throws {
    let fixture = DefaultsFixture()
    let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(EntitlementSnapshot(entitlements: [.pro, .automation], savedAt: savedAt))

    let loaded = try #require(EntitlementSnapshotCache(defaults: fixture.defaults).load())
    #expect(loaded.entitlements == EntitlementSet.all)
    #expect(abs(loaded.savedAt.timeIntervalSince1970 - savedAt.timeIntervalSince1970) < 1.0)
}

@Test func singleTierSnapshotRoundTripsWithoutWideningTheSet() throws {
    let fixture = DefaultsFixture()
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(EntitlementSnapshot(entitlements: [.automation], savedAt: Date()))

    let loaded = try #require(cache.load())
    #expect(loaded.entitlements == [.automation])
    #expect(loaded.entitlements.contains(.pro) == false)
}

/// An empty snapshot is a real, positively resolved "owns nothing" — distinct from "no snapshot".
@Test func emptySnapshotLoadsAsAnEmptySetNotAsNil() throws {
    let fixture = DefaultsFixture()
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(EntitlementSnapshot(entitlements: EntitlementSet.none, savedAt: Date()))

    let loaded = try #require(cache.load())
    #expect(loaded.entitlements.isEmpty)
}

/// FR-1100-12: a successful resolve to a smaller set is the one path that may shrink the cache.
// @covers FR-1100-12
@Test func savingASmallerSetReplacesThePreviousSnapshot() throws {
    let fixture = DefaultsFixture()
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(EntitlementSnapshot(entitlements: EntitlementSet.all, savedAt: Date()))
    cache.save(EntitlementSnapshot(entitlements: [.pro], savedAt: Date()))

    let loaded = try #require(EntitlementSnapshotCache(defaults: fixture.defaults).load())
    #expect(loaded.entitlements == [.pro])
}

// MARK: - Versioned key

@Test func snapshotIsStoredUnderTheVersionedKeyOnly() {
    let fixture = DefaultsFixture()
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(EntitlementSnapshot(entitlements: [.pro], savedAt: Date()))

    #expect(fixture.defaults.object(forKey: storageKey) != nil)
    #expect(fixture.defaults.object(forKey: "purchase.entitlements") == nil)
    #expect(fixture.defaults.object(forKey: "purchase.entitlements.v2") == nil)
}

@Test func cacheWritesNothingElseIntoTheSuite() {
    let fixture = DefaultsFixture()
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(EntitlementSnapshot(entitlements: EntitlementSet.all, savedAt: Date()))

    let written = fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:]
    #expect(Set(written.keys) == [storageKey])
}

/// The versioned key is the only carrier: moving just that value into a fresh suite carries the
/// whole snapshot with it.
@Test func theVersionedKeyCarriesTheWholeSnapshot() throws {
    let source = DefaultsFixture()
    EntitlementSnapshotCache(defaults: source.defaults)
        .save(EntitlementSnapshot(entitlements: [.automation], savedAt: Date()))
    let payload = try #require(source.defaults.object(forKey: storageKey))

    let destination = DefaultsFixture()
    destination.defaults.set(payload, forKey: storageKey)

    let loaded = try #require(EntitlementSnapshotCache(defaults: destination.defaults).load())
    #expect(loaded.entitlements == [.automation])
}

// MARK: - The snapshot never expires (FR-1100-10)

// @covers FR-1100-10
@Test func aDecadeOldSnapshotStillLoadsInFull() throws {
    let fixture = DefaultsFixture()
    let tenYearsAgo = Date().addingTimeInterval(-10 * 365 * 24 * 60 * 60)
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(EntitlementSnapshot(entitlements: EntitlementSet.all, savedAt: tenYearsAgo))

    let loaded = try #require(EntitlementSnapshotCache(defaults: fixture.defaults).load())
    #expect(loaded.entitlements == EntitlementSet.all)
}

// @covers FR-1100-10
@Test func anEpochOldSnapshotStillLoadsInFull() throws {
    let fixture = DefaultsFixture()
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(EntitlementSnapshot(entitlements: [.pro], savedAt: Date(timeIntervalSince1970: 0)))

    let loaded = try #require(cache.load())
    #expect(loaded.entitlements == [.pro])
}

/// `savedAt` is diagnostic only — a snapshot dated in the future is not rejected either.
// @covers FR-1100-10
@Test func aFutureDatedSnapshotStillLoadsInFull() throws {
    let fixture = DefaultsFixture()
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    cache.save(
        EntitlementSnapshot(
            entitlements: [.automation],
            savedAt: Date().addingTimeInterval(365 * 24 * 60 * 60)
        )
    )

    let loaded = try #require(cache.load())
    #expect(loaded.entitlements == [.automation])
}

// MARK: - Absent / corrupt data → nil, never a crash

@Test func loadReturnsNilForAnEmptySuite() {
    let fixture = DefaultsFixture()

    #expect(EntitlementSnapshotCache(defaults: fixture.defaults).load() == nil)
}

@Test func loadReturnsNilForGarbageBytes() {
    let fixture = DefaultsFixture()
    fixture.defaults.set(Data([0x00, 0xFF, 0x10, 0x42]), forKey: storageKey)

    #expect(EntitlementSnapshotCache(defaults: fixture.defaults).load() == nil)
}

@Test func loadReturnsNilForAWrongTypedValue() {
    let fixture = DefaultsFixture()
    fixture.defaults.set("not a snapshot", forKey: storageKey)

    #expect(EntitlementSnapshotCache(defaults: fixture.defaults).load() == nil)
}

@Test func loadReturnsNilForWellFormedJsonOfTheWrongShape() {
    let fixture = DefaultsFixture()
    fixture.defaults.set(Data(#"{"unexpected":true}"#.utf8), forKey: storageKey)

    #expect(EntitlementSnapshotCache(defaults: fixture.defaults).load() == nil)
}

@Test func loadReturnsNilForAnUnknownEntitlementValue() {
    let fixture = DefaultsFixture()
    let json = #"{"entitlements":["timeTravel"],"savedAt":0}"#
    fixture.defaults.set(Data(json.utf8), forKey: storageKey)

    #expect(EntitlementSnapshotCache(defaults: fixture.defaults).load() == nil)
}

/// A corrupt payload must not be silently "repaired" into an entitled state.
@Test func aCorruptSnapshotIsRecoverableByWritingAFreshOne() throws {
    let fixture = DefaultsFixture()
    fixture.defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: storageKey)
    let cache = EntitlementSnapshotCache(defaults: fixture.defaults)

    #expect(cache.load() == nil)
    cache.save(EntitlementSnapshot(entitlements: [.pro], savedAt: Date()))

    let loaded = try #require(cache.load())
    #expect(loaded.entitlements == [.pro])
}
