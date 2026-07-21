import Foundation
import Testing
@testable import PurchaseKit

// T031 — the launch path of an unattended frame that boots with no working store.
//
// The invariant under test (FR-1100-10): between constructing `EntitlementStore` and reading a
// gating decision off it there is **no suspension point at all**, and the store is never
// contacted. A frame in a hallway that reboots after a power cut, with the router still coming
// up, must render its paid ambience on the very first pass — not after a timeout, not on the
// second photo, not "once the network settles".
//
// Two things make these tests mean something rather than merely pass:
//
//   1. The client used here answers *nothing, ever*. If the store were ever changed to await
//      ownership before `current` is readable, a test written this way could not reach its
//      assertions at all — it would hang until the suite killed it. It could not go green.
//   2. The assertions sit in synchronous test functions. There is no `await` available between
//      construction and the assertion, so any work the store might have spawned provably has
//      not run: on the main actor it cannot start until this function suspends, and these
//      functions never do.
//
// Both are structural. Neither depends on timing, and nothing here sleeps.

/// A `StoreClient` whose every method suspends forever and returns nothing.
///
/// Suspension is implemented with an `AsyncStream` the test finishes in `release()`, so a call
/// that does happen (i.e. a regression) unblocks at teardown instead of leaking a continuation.
private final class NeverRespondingStoreClient: StoreClient, @unchecked Sendable {

    let updates: AsyncStream<Void>
    private let updatesContinuation: AsyncStream<Void>.Continuation

    /// Never yields an element; only ever finishes, and only from `release()`.
    private let hang: AsyncStream<Void>
    private let hangContinuation: AsyncStream<Void>.Continuation

    private let lock = NSLock()
    private var _callCount = 0

    init() {
        let (updateStream, updateContinuation) = AsyncStream<Void>.makeStream()
        updates = updateStream
        updatesContinuation = updateContinuation
        let (hangStream, hangContinuation) = AsyncStream<Void>.makeStream()
        hang = hangStream
        self.hangContinuation = hangContinuation
    }

    /// How many times the store reached for this client. The launch path must leave it at zero.
    var callCount: Int {
        lock.withLock { _callCount }
    }

    private func recordCall() {
        lock.withLock { _callCount += 1 }
    }

    /// Lets any hung call finish, so nothing is left suspended after the test.
    func release() {
        hangContinuation.finish()
        updatesContinuation.finish()
    }

    private func neverAnswers() async throws -> Never {
        recordCall()
        for await _ in hang {}
        throw CancellationError()
    }

    func products(for ids: [ProductID]) async throws -> [DisplayProduct] { try await neverAnswers() }
    func purchase(_ id: ProductID) async throws -> PurchaseOutcome { try await neverAnswers() }
    func restore() async throws { try await neverAnswers() }
    func ownedTransactions() async throws -> [OwnedTransaction] { try await neverAnswers() }
}

/// Builds a store over a defaults suite that already holds `seed`, exactly as a relaunch would.
@MainActor
private func launchStore(
    seededWith seed: EntitlementSet,
    savedAt: Date = Date(),
    defaults: DefaultsFixture
) -> (store: EntitlementStore, client: NeverRespondingStoreClient) {
    let cache = EntitlementSnapshotCache(defaults: defaults.defaults)
    cache.save(EntitlementSnapshot(entitlements: seed, savedAt: savedAt))
    let client = NeverRespondingStoreClient()
    // Everything from here to the caller's assertion is synchronous, on purpose.
    return (EntitlementStore(client: client, cache: cache), client)
}

// MARK: - First render pass, offline

/// The whole story in one test: entitled snapshot on disk, a store that will never answer, and
/// the gating decision is already correct with no await in between.
@MainActor
// @covers FR-1100-10
@Test func anEntitledFrameRendersItsPaidAmbienceOnTheFirstPassWithADeadStore() {
    let defaults = DefaultsFixture()
    let launched = launchStore(seededWith: EntitlementSet.all, defaults: defaults)

    // The gate as the slideshow actually latches it at start-up.
    let gate = AmbienceGate(entitled: launched.store.current.contains(.pro))

    #expect(gate.effectiveKenBurns(setting: true))
    #expect(gate.effectiveClock(setting: true))
    #expect(launched.store.current == EntitlementSet.all)
    #expect(launched.client.callCount == 0)

    launched.client.release()
}

/// The automation half of the same pass: the HA coordinator gate reads true offline, so an
/// unattended frame stays remotely controllable after a power cut.
@MainActor
// @covers FR-1100-10
@Test func theAutomationGateIsOpenOnTheFirstPassWithADeadStore() {
    let defaults = DefaultsFixture()
    let launched = launchStore(seededWith: [.automation], defaults: defaults)

    #expect(launched.store.current.contains(.automation))
    #expect(!launched.store.current.contains(.pro))
    #expect(launched.client.callCount == 0)

    launched.client.release()
}

/// Age is not a gate. A snapshot written before the app was ever installed on this device seeds
/// exactly the same — there is no expiry path to regress into (FR-1100-10).
@MainActor
// @covers FR-1100-10
@Test func anAncientSnapshotStillOpensTheGateAtLaunchWithADeadStore() {
    let defaults = DefaultsFixture()
    let launched = launchStore(
        seededWith: EntitlementSet.all,
        savedAt: Date(timeIntervalSince1970: 0),
        defaults: defaults
    )

    let gate = AmbienceGate(entitled: launched.store.current.contains(.pro))

    #expect(gate.effectiveKenBurns(setting: true))
    #expect(launched.store.current == EntitlementSet.all)
    #expect(launched.client.callCount == 0)

    launched.client.release()
}

/// Repeated cold starts against the same dead store keep answering entitled — the launch path
/// has no "first run" side effect that a second boot could lose.
@MainActor
// @covers FR-1100-10
@Test func everyColdStartAgainstADeadStoreSeedsTheSameEntitlements() {
    let defaults = DefaultsFixture()
    let first = launchStore(seededWith: EntitlementSet.all, defaults: defaults)
    #expect(first.store.current == EntitlementSet.all)
    first.client.release()

    for _ in 0..<5 {
        let client = NeverRespondingStoreClient()
        let store = EntitlementStore(
            client: client,
            cache: EntitlementSnapshotCache(defaults: defaults.defaults)
        )

        #expect(store.current == EntitlementSet.all)
        #expect(client.callCount == 0)
        client.release()
    }
}
