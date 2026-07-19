import Foundation
import Testing
@testable import PurchaseKit

// T011 — RED tests for the observable entitlement model (data-model.md §EntitlementStore,
// contracts/purchasekit-api.md §EntitlementStore).
//
// Covered here:
//   * `current` is seeded from the snapshot cache *synchronously* at init, with the store
//     client never touched (FR-1100-10 — an unattended frame renders entitled on the first
//     pass, offline, with no await).
//   * a successful `refresh()` applies the resolved set and persists it.
//   * `restore()` triggers the platform restore first, then refreshes (FR-1100-11).
//
// The failure/last-known-good and updates-stream behaviours belong to T028 and are not
// asserted here.
//
// Tests are `@MainActor` because the store is an app-wide `@Observable` model; the assertions
// after `init` deliberately run without an intervening `await`, so any work the store might
// spawn cannot have executed yet — that is what makes the "zero calls" assertion meaningful.

/// Owns the suite, the fake client and the store under test for the lifetime of one test.
@MainActor
private final class StoreFixture {
    let defaults: DefaultsFixture
    let client: StoreClientFake
    let store: EntitlementStore

    /// - Parameter seed: entitlements written to the cache *before* the store is constructed.
    init(seed: EntitlementSet? = nil, savedAt: Date = Date()) {
        let defaults = DefaultsFixture()
        let client = StoreClientFake()
        let cache = EntitlementSnapshotCache(defaults: defaults.defaults)
        if let seed {
            cache.save(EntitlementSnapshot(entitlements: seed, savedAt: savedAt))
        }
        self.defaults = defaults
        self.client = client
        self.store = EntitlementStore(client: client, cache: cache)
    }

    /// Reads the snapshot back through a fresh cache instance — proves it really hit defaults.
    var persistedSnapshot: EntitlementSnapshot? {
        EntitlementSnapshotCache(defaults: defaults.defaults).load()
    }

    /// A second store over the same suite, as a relaunch would build it.
    func relaunch() -> (store: EntitlementStore, client: StoreClientFake) {
        let freshClient = StoreClientFake()
        let store = EntitlementStore(
            client: freshClient,
            cache: EntitlementSnapshotCache(defaults: defaults.defaults)
        )
        return (store, freshClient)
    }
}

// MARK: - Launch: synchronous cache seeding, client never awaited

@MainActor
@Test func currentIsSeededFromTheCacheAtInitWithoutTouchingTheClient() {
    let fixture = StoreFixture(seed: [.pro])

    #expect(fixture.store.current == [.pro])
    #expect(fixture.client.totalCallCount == 0)
    #expect(fixture.client.callLog.isEmpty)
}

@MainActor
@Test func bothTiersAreSeededFromTheCacheAtInit() {
    let fixture = StoreFixture(seed: EntitlementSet.all)

    #expect(fixture.store.current == EntitlementSet.all)
    #expect(fixture.store.current.contains(.pro))
    #expect(fixture.store.current.contains(.automation))
    #expect(fixture.client.totalCallCount == 0)
}

@MainActor
@Test func currentIsEmptyWhenNoSnapshotHasEverBeenWritten() {
    let fixture = StoreFixture()

    #expect(fixture.store.current == EntitlementSet.none)
    #expect(fixture.client.totalCallCount == 0)
}

/// FR-1100-10: the snapshot never expires, so age must not affect the launch seed.
@MainActor
@Test func anAncientSnapshotStillSeedsTheFullEntitlementSet() {
    let fixture = StoreFixture(seed: EntitlementSet.all, savedAt: Date(timeIntervalSince1970: 0))

    #expect(fixture.store.current == EntitlementSet.all)
    #expect(fixture.client.totalCallCount == 0)
}

@MainActor
@Test func aCorruptSnapshotSeedsAnEmptySetInsteadOfCrashing() {
    let defaults = DefaultsFixture()
    defaults.defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: "purchase.entitlements.v1")
    let client = StoreClientFake()

    let store = EntitlementStore(
        client: client,
        cache: EntitlementSnapshotCache(defaults: defaults.defaults)
    )

    #expect(store.current == EntitlementSet.none)
    #expect(client.totalCallCount == 0)
}

// MARK: - refresh(): apply + persist

@MainActor
@Test func successfulRefreshAppliesTheResolvedEntitlements() async {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.pro)

    await fixture.store.refresh()

    #expect(fixture.store.current == [.pro])
    #expect(fixture.client.ownedTransactionsCallCount == 1)
}

@MainActor
@Test func successfulRefreshResolvesTheBundleIntoBothTiers() async {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.everything)

    await fixture.store.refresh()

    #expect(fixture.store.current == EntitlementSet.all)
}

@MainActor
@Test func successfulRefreshPersistsTheResolvedEntitlements() async throws {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.automation)

    await fixture.store.refresh()

    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == [.automation])
    #expect(fixture.store.current == persisted.entitlements)
}

/// The persisted snapshot is what the *next* launch seeds from — the round trip that makes an
/// unattended frame survive a reboot offline.
@MainActor
@Test func entitlementsPersistedByRefreshSeedTheNextLaunch() async {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.everything)
    await fixture.store.refresh()

    let relaunched = fixture.relaunch()

    #expect(relaunched.store.current == EntitlementSet.all)
    #expect(relaunched.client.totalCallCount == 0)
}

/// FR-1100-08: a tip purchase resolves to no entitlement at all.
@MainActor
@Test func refreshIgnoresTipsAndRevokedTransactions() async {
    let fixture = StoreFixture()
    fixture.client.enqueueOwnedTransactions([
        OwnedTransaction(productID: ProductID.tipLarge.rawValue, isRevoked: false),
        OwnedTransaction(productID: ProductID.pro.rawValue, isRevoked: true),
        OwnedTransaction(productID: ProductID.automation.rawValue, isRevoked: false),
    ])

    await fixture.store.refresh()

    #expect(fixture.store.current == [.automation])
}

// MARK: - restore(): platform sync, then refresh

@MainActor
@Test func restoreCallsTheClientRestoreAndThenRefreshes() async throws {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.everything)

    try await fixture.store.restore()

    #expect(fixture.client.callLog == [.restore, .ownedTransactions])
    #expect(fixture.store.current == EntitlementSet.all)
}

@MainActor
@Test func restorePersistsTheRepopulatedEntitlements() async throws {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.pro)

    try await fixture.store.restore()

    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == [.pro])
    #expect(fixture.store.current == [.pro])
}

/// FR-1100-11: restore is idempotent — running it twice ends in the same state.
@MainActor
@Test func restoreIsIdempotent() async throws {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.pro)
    fixture.client.enqueueOwned(.pro)

    try await fixture.store.restore()
    try await fixture.store.restore()

    #expect(fixture.store.current == [.pro])
    #expect(fixture.client.restoreCallCount == 2)
    #expect(fixture.client.ownedTransactionsCallCount == 2)
}

@MainActor
@Test func restoreRethrowsAPlatformSyncFailureWithoutRefreshing() async {
    let fixture = StoreFixture(seed: [.pro])
    fixture.client.failNextRestore()

    await #expect(throws: StoreClientFake.Failure.self) {
        try await fixture.store.restore()
    }

    #expect(fixture.client.callLog == [.restore])
    #expect(fixture.client.ownedTransactionsCallCount == 0)
    #expect(fixture.store.current == [.pro])
}
