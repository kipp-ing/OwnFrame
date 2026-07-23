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
// @covers FR-1100-10
@Test func currentIsSeededFromTheCacheAtInitWithoutTouchingTheClient() {
    let fixture = StoreFixture(seed: [.supporter])

    #expect(fixture.store.current == [.supporter])
    #expect(fixture.client.totalCallCount == 0)
    #expect(fixture.client.callLog.isEmpty)
}

@MainActor
// @covers FR-1100-10
@Test func theEntitlementIsSeededFromTheCacheAtInit() {
    let fixture = StoreFixture(seed: EntitlementSet.all)

    #expect(fixture.store.current == EntitlementSet.all)
    #expect(fixture.store.current.contains(.supporter))
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
// @covers FR-1100-10
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
    fixture.client.enqueueOwned(.supporter)

    await fixture.store.refresh()

    #expect(fixture.store.current == [.supporter])
    #expect(fixture.client.ownedTransactionsCallCount == 1)
}

@MainActor
// @covers FR-1100-04
@Test func successfulRefreshResolvesTheSupporterUnlockIntoTheFullSet() async {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.supporter)

    await fixture.store.refresh()

    #expect(fixture.store.current == EntitlementSet.all)
}

@MainActor
// @covers FR-1100-10
@Test func successfulRefreshPersistsTheResolvedEntitlements() async throws {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.supporter)

    await fixture.store.refresh()

    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == [.supporter])
    #expect(fixture.store.current == persisted.entitlements)
}

/// The persisted snapshot is what the *next* launch seeds from — the round trip that makes an
/// unattended frame survive a reboot offline.
@MainActor
// @covers FR-1100-10
@Test func entitlementsPersistedByRefreshSeedTheNextLaunch() async {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.supporter)
    await fixture.store.refresh()

    let relaunched = fixture.relaunch()

    #expect(relaunched.store.current == EntitlementSet.all)
    #expect(relaunched.client.totalCallCount == 0)
}

/// FR-1100-08: a tip purchase resolves to no entitlement, and a revoked unlock contributes
/// nothing, while a live unlock still grants — the tip and the refunded transaction are both
/// ignored, the surviving one is honoured.
@MainActor
// @covers FR-1100-08, FR-1100-12
@Test func refreshIgnoresTipsAndRevokedTransactions() async {
    let fixture = StoreFixture()
    fixture.client.enqueueOwnedTransactions([
        OwnedTransaction(productID: ProductID.tipLarge.rawValue, isRevoked: false),
        OwnedTransaction(productID: ProductID.supporter.rawValue, isRevoked: true),
        OwnedTransaction(productID: ProductID.supporter.rawValue, isRevoked: false),
    ])

    await fixture.store.refresh()

    #expect(fixture.store.current == [.supporter])
}

// MARK: - restore(): platform sync, then refresh

@MainActor
// @covers FR-1100-11
@Test func restoreCallsTheClientRestoreAndThenRefreshes() async throws {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.supporter)

    try await fixture.store.restore()

    #expect(fixture.client.callLog == [.restore, .ownedTransactions])
    #expect(fixture.store.current == EntitlementSet.all)
}

@MainActor
// @covers FR-1100-10, FR-1100-11
@Test func restorePersistsTheRepopulatedEntitlements() async throws {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.supporter)

    try await fixture.store.restore()

    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == [.supporter])
    #expect(fixture.store.current == [.supporter])
}

/// FR-1100-11: restore is idempotent — running it twice ends in the same state.
@MainActor
// @covers FR-1100-11
@Test func restoreIsIdempotent() async throws {
    let fixture = StoreFixture()
    fixture.client.enqueueOwned(.supporter)
    fixture.client.enqueueOwned(.supporter)

    try await fixture.store.restore()
    try await fixture.store.restore()

    #expect(fixture.store.current == [.supporter])
    #expect(fixture.client.restoreCallCount == 2)
    #expect(fixture.client.ownedTransactionsCallCount == 2)
}

@MainActor
// @covers FR-1100-10
@Test func restoreRethrowsAPlatformSyncFailureWithoutRefreshing() async {
    let fixture = StoreFixture(seed: [.supporter])
    fixture.client.failNextRestore()

    await #expect(throws: StoreClientFake.Failure.self) {
        try await fixture.store.restore()
    }

    #expect(fixture.client.callLog == [.restore])
    #expect(fixture.client.ownedTransactionsCallCount == 0)
    #expect(fixture.store.current == [.supporter])
}

// ===========================================================================================
// T028 — the unattended frame (US3). Everything below this line is about one promise: a photo
// frame that has been running for months on flaky wifi must never relock a paid feature
// because a network call failed. The mirror-image promise is that a *store-confirmed*
// revocation still takes effect, so "never shrink" cannot be satisfied by never shrinking.
// ===========================================================================================

// MARK: - Deterministic waiting
//
// The updates-stream tests need to observe work that `listenForUpdates()` performs in its own
// task. They do it by yielding the main actor until the expected state appears — the only
// thing that advances is the cooperative scheduler, so a correct implementation is observed
// as fast as the machine runs and can never lose a race. The wall-clock deadline is a
// *failure* bound only: it decides how long a broken implementation takes to be reported, and
// never how long a working one takes to pass. Nothing here sleeps.

/// Yields the main actor until `condition` holds; records a failure if it never does.
@MainActor
private func waitFor(
    _ what: String,
    within seconds: TimeInterval = 2,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(what).", sourceLocation: sourceLocation)
}

// MARK: - Refresh failure: last known good, never a claw-back (FR-1100-13)

/// The core US3 promise: a failed ownership query means "unknown", never "owns nothing".
@MainActor
// @covers FR-1100-10
@Test func aFailedRefreshLeavesTheEntitlementsAndTheSnapshotUntouched() async throws {
    let fixture = StoreFixture(seed: EntitlementSet.all)
    let snapshotBefore = try #require(fixture.persistedSnapshot)
    fixture.client.failNextOwnedTransactions()

    await fixture.store.refresh()

    #expect(fixture.store.current == EntitlementSet.all)
    #expect(fixture.client.ownedTransactionsCallCount == 1)
    // Not merely "still entitled" — nothing was written at all, so the next launch seeds the
    // same last-known-good set.
    let snapshotAfter = try #require(fixture.persistedSnapshot)
    #expect(snapshotAfter == snapshotBefore)
}

/// Flaky wifi is not one failure, it is thousands. None of them may erode the set.
@MainActor
// @covers FR-1100-10
@Test func repeatedRefreshFailuresNeverShrinkTheEntitlements() async {
    let fixture = StoreFixture(seed: EntitlementSet.all)
    fixture.client.alwaysFailOwnedTransactions()

    for _ in 0..<25 {
        await fixture.store.refresh()
        #expect(fixture.store.current == EntitlementSet.all)
    }

    #expect(fixture.client.ownedTransactionsCallCount == 25)
    #expect(fixture.store.current.contains(.supporter))
}

/// The full unattended scenario: an ancient snapshot, a store that never answers, repeated
/// refreshes, then a power cut. The frame comes back entitled. There is no expiry path
/// anywhere in this type, and this test exists to keep it that way (FR-1100-10).
@MainActor
// @covers FR-1100-10
@Test func aFrameOfflineForMonthsStaysEntitledAcrossRefreshesAndRelaunch() async {
    let fixture = StoreFixture(
        seed: EntitlementSet.all,
        savedAt: Date(timeIntervalSince1970: 0)
    )
    fixture.client.alwaysFailOwnedTransactions()

    for _ in 0..<10 { await fixture.store.refresh() }
    let relaunched = fixture.relaunch()

    #expect(relaunched.store.current == EntitlementSet.all)
    #expect(relaunched.client.totalCallCount == 0)
}

// MARK: - Refresh success: the one legitimate shrink (FR-1100-12)

/// Without this test, "never shrink on failure" could be satisfied by never shrinking at all —
/// which would silently break revocation. A *store-confirmed* smaller set must take effect and
/// must be persisted, so the relock survives a relaunch instead of flapping back. With a single
/// unlock the only smaller set is empty, reached here by a successful resolve that reports nothing
/// owned (distinct from the revocation path below).
@MainActor
// @covers FR-1100-12
@Test func aSuccessfulResolveToASmallerSetShrinksAndPersists() async throws {
    let fixture = StoreFixture(seed: EntitlementSet.all)
    fixture.client.enqueueOwnedTransactions([])

    await fixture.store.refresh()

    #expect(fixture.store.current == EntitlementSet.none)
    #expect(!fixture.store.current.contains(.supporter))
    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == EntitlementSet.none)
}

/// A refund of the unlock: the set empties, and it empties in the cache too.
@MainActor
// @covers FR-1100-12
@Test func aFullRevocationClearsTheEntitlementsAndTheSnapshot() async throws {
    let fixture = StoreFixture(seed: EntitlementSet.all)
    fixture.client.enqueueOwnedTransactions([
        OwnedTransaction(productID: ProductID.supporter.rawValue, isRevoked: true)
    ])

    await fixture.store.refresh()

    #expect(fixture.store.current == EntitlementSet.none)
    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == EntitlementSet.none)
}

/// The shrink is durable: a relaunch must not resurrect the refunded unlock from a stale cache.
@MainActor
// @covers FR-1100-12
@Test func aRevokedUnlockDoesNotComeBackOnTheNextLaunch() async {
    let fixture = StoreFixture(seed: EntitlementSet.all)
    fixture.client.enqueueOwnedTransactions([
        OwnedTransaction(productID: ProductID.supporter.rawValue, isRevoked: true)
    ])
    await fixture.store.refresh()

    let relaunched = fixture.relaunch()

    #expect(relaunched.store.current == EntitlementSet.none)
    #expect(relaunched.client.totalCallCount == 0)
}

// MARK: - listenForUpdates(): ownership changes that arrive on their own (FR-1100-15)

/// A late Ask-to-Buy approval, a purchase made on another device, a pushed revocation: the
/// store learns about all of them through `updates`, and each event is a reason to re-resolve.
@MainActor
// @covers FR-1100-15
@Test func anUpdateEventReResolvesAndPersistsTheNewEntitlements() async throws {
    let fixture = StoreFixture()
    fixture.store.listenForUpdates()
    fixture.client.enqueueOwned(.supporter)

    fixture.client.emitUpdate()

    await waitFor("the update event to be re-resolved") { fixture.store.current == [.supporter] }
    #expect(fixture.store.current == [.supporter])
    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == [.supporter])
    fixture.client.finishUpdates()
}

/// The Ask-to-Buy shape in full: the purchase is deferred, so the first event resolves to
/// nothing; the parent approves later and a second event carries the entitlement in. The
/// listener must still be listening — one event may not end the loop.
@MainActor
// @covers FR-1100-15
@Test func aLateAskToBuyApprovalArrivesOnASubsequentUpdateEvent() async throws {
    let fixture = StoreFixture()
    fixture.store.listenForUpdates()
    fixture.client.enqueueOwnedTransactions([])
    fixture.client.enqueueOwned(.supporter)

    fixture.client.emitUpdate()
    await waitFor("the deferred purchase to resolve to nothing") {
        fixture.client.ownedTransactionsCallCount == 1
    }
    #expect(fixture.store.current == EntitlementSet.none)

    fixture.client.emitUpdate()

    await waitFor("the approval to be re-resolved") { fixture.store.current == [.supporter] }
    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == [.supporter])
    fixture.client.finishUpdates()
}

/// Same last-known-good rule on the updates path: an event whose re-resolve fails must not
/// relock the frame. This is the failure mode that would hurt most — it fires unprompted, with
/// nobody in the room.
@MainActor
// @covers FR-1100-10
@Test func anUpdateEventWhoseReResolveFailsLeavesTheEntitlementsIntact() async throws {
    let fixture = StoreFixture(seed: EntitlementSet.all)
    let snapshotBefore = try #require(fixture.persistedSnapshot)
    fixture.store.listenForUpdates()
    fixture.client.alwaysFailOwnedTransactions()

    fixture.client.emitUpdate()

    await waitFor("the failing re-resolve to be attempted") {
        fixture.client.ownedTransactionsCallCount == 1
    }
    #expect(fixture.store.current == EntitlementSet.all)
    let snapshotAfter = try #require(fixture.persistedSnapshot)
    #expect(snapshotAfter == snapshotBefore)
    fixture.client.finishUpdates()
}

/// The updates path can shrink too, when the store actually says so (revocation pushed while
/// the app is running) — the same asymmetry as `refresh()`.
@MainActor
// @covers FR-1100-12
@Test func anUpdateEventAppliesAPushedRevocation() async throws {
    let fixture = StoreFixture(seed: EntitlementSet.all)
    fixture.store.listenForUpdates()
    fixture.client.enqueueOwnedTransactions([
        OwnedTransaction(productID: ProductID.supporter.rawValue, isRevoked: true),
    ])

    fixture.client.emitUpdate()

    await waitFor("the pushed revocation to be applied") {
        fixture.store.current == EntitlementSet.none
    }
    let persisted = try #require(fixture.persistedSnapshot)
    #expect(persisted.entitlements == EntitlementSet.none)
    fixture.client.finishUpdates()
}
