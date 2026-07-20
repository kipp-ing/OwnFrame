import Foundation
import Testing
@testable import PurchaseKit

// T023 — RED tests for the unlock-screen model (data-model.md §PurchaseViewModel,
// contracts/purchasekit-api.md §StoreClient).
//
// Covered here:
//   * offer computation (FR-1100-04) — owns none → both tiers + the bundle; owns exactly one
//     unlock → only the missing single unlock, never the bundle; owns everything → an owned
//     state with nothing on sale.
//   * `unavailable` (FR-1100-16) — a throwing `products(for:)` produces a state that carries no
//     products at all, so there is no surface a placeholder price could live on.
//   * purchase edge states (FR-1100-15) — `.pending` is terminal for the session, `.cancelled`
//     returns to `.ready`, a throwing purchase surfaces `.failed`; none of them touch
//     entitlements.
//   * the happy path drives entitlements through `EntitlementStore.refresh()` rather than
//     around it, and `restore()` delegates to the store (FR-1100-11).
//
// Determinism: every answer is scripted on `StoreClientFake` *before* the call that consumes it,
// and each fixture owns a private `UserDefaults` suite. No sleeps, no real StoreKit, no network.
//
// Tests are `@MainActor` because the model is an `@Observable` view model over the
// `@MainActor` `EntitlementStore`.

// MARK: - Fixture

/// Owns the defaults suite, the fake client, the store and the model under test for one test.
///
/// The `owned` products seed **both** the snapshot cache (what the store loads synchronously at
/// launch) and the fake's standing ownership answer, so the two can never disagree — the model
/// then observes the same entitlements whether or not it refreshes on its way into `load()`.
@MainActor
private final class UnlockFixture {
    let defaults: DefaultsFixture
    let client: StoreClientFake
    let store: EntitlementStore
    let model: PurchaseViewModel

    /// - Parameters:
    ///   - tier: the tier whose unlock screen is being shown.
    ///   - owned: products the user already owns, before this screen is opened.
    init(tier: Entitlement, owned: [ProductID] = []) {
        let defaults = DefaultsFixture()
        let cache = EntitlementSnapshotCache(defaults: defaults.defaults)
        let entitlements = owned.reduce(into: EntitlementSet.none) {
            $0.formUnion(ProductCatalog.grants($1))
        }
        cache.save(EntitlementSnapshot(entitlements: entitlements, savedAt: Date()))

        let client = StoreClientFake()
        client.setDefaultOwnedTransactions(.success(owned.map(OwnedTransaction.owning)))

        let store = EntitlementStore(client: client, cache: cache)

        self.defaults = defaults
        self.client = client
        self.store = store
        self.model = PurchaseViewModel(tier: tier, client: client, store: store)
    }

    /// Scripts the store to answer with exactly these products — once from the queue, and from
    /// the standing default afterwards, so a repeated query cannot change the outcome.
    func stocks(_ ids: [ProductID]) {
        let products = ids.map(DisplayProduct.stub)
        client.enqueueProducts(products)
        client.setDefaultProducts(.success(products))
    }

    /// Makes every ownership query from here on report these products as owned — how a completed
    /// purchase becomes visible to `EntitlementStore.refresh()`.
    func storeNowReportsOwned(_ ids: ProductID...) {
        client.setDefaultOwnedTransactions(.success(ids.map(OwnedTransaction.owning)))
    }
}

private extension OwnedTransaction {
    static func owning(_ id: ProductID) -> OwnedTransaction {
        OwnedTransaction(productID: id.rawValue, isRevoked: false)
    }
}

private extension DisplayProduct {
    /// Deliberately non-numeric strings: real pricing lives in App Store Connect and must never
    /// appear in this repo. Tests assert a price *exists*, never what it says.
    static func stub(_ id: ProductID) -> DisplayProduct {
        DisplayProduct(
            id: id,
            displayName: "unlock-\(id.rawValue)",
            displayPrice: "price-\(id.rawValue)"
        )
    }
}

// MARK: - Phase accessors
//
// Pattern-matching accessors rather than `==` on the phase: the assertions below should pin the
// *case and its payload*, not force an `Equatable` conformance on the enum, and `.failed`'s
// message is a user-facing string no test should hard-code.

private extension PurchasePhase {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    /// The offered products — `nil` in every phase other than `.ready`.
    var readyProducts: [DisplayProduct]? {
        if case .ready(let products) = self { return products }
        return nil
    }

    var pendingProductID: ProductID? {
        if case .pending(let id) = self { return id }
        return nil
    }

    var completedEntitlements: EntitlementSet? {
        if case .completed(let entitlements) = self { return entitlements }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

// MARK: - Launch

/// Construction is inert: the screen renders `loading` and no store traffic has happened yet.
@MainActor
@Test func theUnlockScreenStartsLoadingWithoutTouchingTheStore() {
    let fixture = UnlockFixture(tier: .pro)

    #expect(fixture.model.phase.isLoading)
    #expect(fixture.client.totalCallCount == 0)
}

// MARK: - Offer computation (FR-1100-04)

@MainActor
@Test func owningNothingOffersBothTiersAndTheBundle() async throws {
    let fixture = UnlockFixture(tier: .pro)
    fixture.stocks([.pro, .automation, .everything])

    await fixture.model.load()

    #expect(fixture.client.requestedProductIDs == [[.pro, .automation, .everything]])
    let products = try #require(fixture.model.phase.readyProducts)
    #expect(products.map(\.id) == [.pro, .automation, .everything])
    // A price must exist for every offer; its value is App Store Connect's business.
    #expect(products.allSatisfy { !$0.displayPrice.isEmpty })
}

/// FR-1100-04: a user who owns one tier is offered only the missing tier. Re-selling a bundle
/// that contains something already paid for is the specific trap this rule forbids.
@MainActor
@Test func owningProOffersOnlyAutomationAndNeverTheBundle() async throws {
    let fixture = UnlockFixture(tier: .automation, owned: [.pro])
    fixture.stocks([.automation])

    await fixture.model.load()

    #expect(fixture.client.requestedProductIDs == [[.automation]])
    let products = try #require(fixture.model.phase.readyProducts)
    #expect(products.map(\.id) == [.automation])
    #expect(!products.contains { $0.id == .everything })
    #expect(!fixture.client.requestedProductIDs.flatMap { $0 }.contains(.everything))
}

@MainActor
@Test func owningAutomationOffersOnlyProAndNeverTheBundle() async throws {
    let fixture = UnlockFixture(tier: .pro, owned: [.automation])
    fixture.stocks([.pro])

    await fixture.model.load()

    #expect(fixture.client.requestedProductIDs == [[.pro]])
    let products = try #require(fixture.model.phase.readyProducts)
    #expect(products.map(\.id) == [.pro])
    #expect(!products.contains { $0.id == .everything })
    #expect(!fixture.client.requestedProductIDs.flatMap { $0 }.contains(.everything))
}

/// Owning the bundle leaves nothing to sell: the screen states what is owned and queries no
/// products at all.
@MainActor
@Test func owningEverythingShowsTheOwnedStateWithNoProducts() async throws {
    let fixture = UnlockFixture(tier: .pro, owned: [.everything])

    await fixture.model.load()

    let owned = try #require(fixture.model.phase.completedEntitlements)
    #expect(owned == EntitlementSet.all)
    #expect(fixture.model.phase.readyProducts == nil)
    #expect(fixture.client.productsCallCount == 0)
}

/// Both single unlocks together are the same thing as the bundle — nothing left to offer.
@MainActor
@Test func owningBothSingleUnlocksShowsTheOwnedStateWithNoProducts() async throws {
    let fixture = UnlockFixture(tier: .pro, owned: [.pro, .automation])

    await fixture.model.load()

    let owned = try #require(fixture.model.phase.completedEntitlements)
    #expect(owned == EntitlementSet.all)
    #expect(fixture.model.phase.readyProducts == nil)
    #expect(fixture.client.productsCallCount == 0)
}

// MARK: - Store unreachable (FR-1100-16)

/// The unavailable state carries no products whatsoever — not an empty label, not a cached
/// string, nothing. A placeholder price presented as live would be the bug this test exists for.
@MainActor
@Test func anUnreachableStoreYieldsUnavailableWithNoProductsAtAll() async {
    let fixture = UnlockFixture(tier: .pro)
    fixture.client.failNextProducts()

    await fixture.model.load()

    #expect(fixture.model.phase.isUnavailable)
    #expect(fixture.model.phase.readyProducts == nil)
    #expect(fixture.model.phase.completedEntitlements == nil)
    // Unreachable is not evidence of non-ownership: nothing was granted or taken away.
    #expect(fixture.store.current == EntitlementSet.none)
}

// MARK: - Purchase edge states (FR-1100-15)

/// Ask to Buy: `.pending` ends the session's purchase attempt. Approval arrives later over the
/// updates stream (T029) — the model must not spin, must not optimistically complete, and must
/// not grant the tier in the meantime.
@MainActor
@Test func aPendingPurchaseIsTerminalForTheSessionAndGrantsNothing() async throws {
    let fixture = UnlockFixture(tier: .pro)
    fixture.stocks([.pro, .automation, .everything])
    await fixture.model.load()
    fixture.client.enqueuePurchase(.pending)
    // The fake's standing answer is `.success`, so a silent retry would visibly complete here.
    fixture.client.setDefaultPurchase(.success(.success))
    fixture.client.resetCallLog()

    await fixture.model.buy(.pro)

    #expect(fixture.model.phase.pendingProductID == .pro)
    #expect(fixture.model.phase.completedEntitlements == nil)
    #expect(fixture.client.purchaseCallCount == 1)
    #expect(fixture.store.current == EntitlementSet.none)
}

/// Cancelling drops the user back on the offer, unchanged. No follow-up prompt, no re-attempt.
@MainActor
@Test func aCancelledPurchaseReturnsToReadyWithNoEntitlementChange() async throws {
    let fixture = UnlockFixture(tier: .pro)
    fixture.stocks([.pro, .automation, .everything])
    await fixture.model.load()
    fixture.client.enqueuePurchase(.cancelled)
    fixture.client.resetCallLog()

    await fixture.model.buy(.pro)

    let products = try #require(fixture.model.phase.readyProducts)
    #expect(products.map(\.id) == [.pro, .automation, .everything])
    #expect(fixture.client.purchaseCallCount == 1)
    #expect(fixture.store.current == EntitlementSet.none)
}

/// A throwing purchase is reported, not swallowed — and it changes nothing.
@MainActor
@Test func aFailedPurchaseSurfacesAMessageAndLeavesEntitlementsUntouched() async throws {
    let fixture = UnlockFixture(tier: .pro)
    fixture.stocks([.pro, .automation, .everything])
    await fixture.model.load()
    fixture.client.failNextPurchase()
    fixture.client.resetCallLog()

    await fixture.model.buy(.pro)

    let message = try #require(fixture.model.phase.failureMessage)
    #expect(!message.isEmpty)
    #expect(fixture.model.phase.completedEntitlements == nil)
    #expect(fixture.client.purchaseCallCount == 1)
    #expect(fixture.store.current == EntitlementSet.none)
}

// MARK: - Success

/// The purchase must land through `EntitlementStore.refresh()`, which is the only path that
/// resolves *and persists* ownership. `current` is `private(set)`, so a model that shortcut the
/// store could not move it — asserting the store's state is what proves the production path ran.
@MainActor
@Test func aSuccessfulPurchaseDrivesTheEntitlementThroughTheStoreRefreshPath() async throws {
    let fixture = UnlockFixture(tier: .pro)
    fixture.stocks([.pro, .automation, .everything])
    await fixture.model.load()
    fixture.client.enqueuePurchase(.success)
    fixture.storeNowReportsOwned(.pro)
    fixture.client.resetCallLog()

    await fixture.model.buy(.pro)

    #expect(fixture.store.current == [.pro])
    #expect(fixture.client.purchasedProductIDs == [.pro])
    // Ownership is re-resolved from the store after the purchase, not assumed from the outcome.
    #expect(fixture.client.callLog.last == .ownedTransactions)

    let completed = try #require(fixture.model.phase.completedEntitlements)
    #expect(completed == [.pro])

    // FR-1100-10: the resolved set is persisted, so the next launch starts entitled offline.
    let persisted = try #require(EntitlementSnapshotCache(defaults: fixture.defaults.defaults).load())
    #expect(persisted.entitlements == [.pro])
}

/// Buying the bundle grants both tiers in one transaction.
@MainActor
@Test func buyingTheBundleCompletesWithBothTiers() async throws {
    let fixture = UnlockFixture(tier: .pro)
    fixture.stocks([.pro, .automation, .everything])
    await fixture.model.load()
    fixture.client.enqueuePurchase(.success)
    fixture.storeNowReportsOwned(.everything)

    await fixture.model.buy(.everything)

    #expect(fixture.store.current == EntitlementSet.all)
    let completed = try #require(fixture.model.phase.completedEntitlements)
    #expect(completed == EntitlementSet.all)
}

// MARK: - Restore (FR-1100-11)

/// Restore delegates to the store's platform sync + refresh and reflects whatever came back.
@MainActor
@Test func restoreDelegatesToTheStoreAndReflectsTheRecoveredEntitlements() async throws {
    let fixture = UnlockFixture(tier: .pro)
    fixture.stocks([.pro, .automation, .everything])
    await fixture.model.load()
    fixture.storeNowReportsOwned(.everything)
    fixture.client.resetCallLog()

    await fixture.model.restore()

    #expect(fixture.client.callLog == [.restore, .ownedTransactions])
    #expect(fixture.store.current == EntitlementSet.all)
    let completed = try #require(fixture.model.phase.completedEntitlements)
    #expect(completed == EntitlementSet.all)
}
