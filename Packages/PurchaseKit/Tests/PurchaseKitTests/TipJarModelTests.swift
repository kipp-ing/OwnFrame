import Foundation
import Testing
@testable import PurchaseKit

// T038 (PurchaseKit half) — RED tests for the tip-jar model (spec 1100 US6, FR-1100-08).
//
// The one invariant that matters: a tip is a **consumable that grants nothing**. Buying any tip
// must leave the user's `EntitlementSet` byte-for-byte unchanged — no tier appears, none
// disappears — and must never re-resolve entitlements (a tip cannot change ownership, so a
// refresh would be pointless and could race). Tips are gratitude, not a transaction for features.
//
// The model is handed a `StoreClient` and *no* `EntitlementStore`: a tip model that cannot see
// entitlements cannot change them. The tests still inject a real store — seeded with `[.pro]` —
// and prove the store's `current` never moves and its ownership seam is never queried.
//
// Determinism: every store answer is scripted on `StoreClientFake` before the call that consumes
// it; each fixture owns a private `UserDefaults` suite. No sleeps, no real StoreKit, no network.

// MARK: - Fixture

/// Owns the defaults suite, the fake client, an entitlement store, and the tip model under test.
///
/// The store is real and seeded so the entitlement-unchanged assertions are meaningful. The model
/// is built against the store's *own* client (`EntitlementStore.storeClient` — the same seam the
/// tip UI reaches through), so any ownership query the tip flow made would show up on the shared
/// call log. It shares no other state with the store.
@MainActor
private final class TipFixture {
    let defaults: DefaultsFixture
    let client: StoreClientFake
    let store: EntitlementStore
    let model: TipJarModel

    /// - Parameter owned: entitlement-granting products the user already holds. Seeds BOTH the
    ///   snapshot cache (what the store loads synchronously at launch) and the fake's standing
    ///   ownership answer, so even a stray refresh would resolve to the same set — the tests then
    ///   prove the set never moved because nothing touched it, not because it happened to match.
    init(owned: [ProductID] = []) {
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
        self.model = TipJarModel(client: store.storeClient)
    }

    /// Scripts the store to answer with exactly the three tip products — once from the queue and
    /// from the standing default afterwards, so a repeated query cannot change the outcome.
    func stocksTips() {
        let products = ProductCatalog.tips.map(DisplayProduct.stub)
        client.enqueueProducts(products)
        client.setDefaultProducts(.success(products))
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
            displayName: "tip-\(id.rawValue)",
            displayPrice: "price-\(id.rawValue)"
        )
    }
}

// MARK: - Phase accessors
//
// Pattern-matching accessors rather than `==`: the assertions pin the *case and its payload*
// without forcing an `Equatable` conformance on the phase enum.

private extension TipPhase {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var isThanked: Bool {
        if case .thanked = self { return true }
        return false
    }

    /// The offered tips — `nil` in every phase other than `.ready`.
    var offerProducts: [DisplayProduct]? {
        if case .ready(let products) = self { return products }
        return nil
    }
}

// MARK: - Idle construction

/// Construction is inert: the model renders `loading` and no store traffic has happened yet.
@MainActor
@Test func theTipJarStartsIdleWithoutTouchingTheStore() {
    let fixture = TipFixture()

    #expect(fixture.model.phase.isLoading)
    #expect(fixture.client.totalCallCount == 0)
}

// MARK: - The offer

/// The tip jar offers exactly `ProductCatalog.tips`, in order, each with a displayable price.
@MainActor
@Test func theTipJarOffersExactlyTheThreeTipsInOrderEachWithAPrice() async throws {
    let fixture = TipFixture()
    fixture.stocksTips()

    await fixture.model.load()

    #expect(fixture.client.requestedProductIDs == [ProductCatalog.tips])
    let products = try #require(fixture.model.phase.offerProducts)
    #expect(products.map(\.id) == ProductCatalog.tips)
    // A price string must exist for every tip; its value is App Store Connect's business.
    #expect(products.allSatisfy { !$0.displayPrice.isEmpty })
}

/// The store is unreachable at load time → an informative unavailable state that carries no
/// products and therefore no price a placeholder could hide in (FR-1100-16 spirit).
@MainActor
@Test func anUnreachableStoreYieldsUnavailableWithNoPrices() async {
    let fixture = TipFixture()
    fixture.client.failNextProducts()

    await fixture.model.load()

    #expect(fixture.model.phase.isUnavailable)
    #expect(fixture.model.phase.offerProducts == nil)
}

// MARK: - The load-bearing invariant (FR-1100-08)

/// A successful tip thanks the user and leaves the entitlement set **byte-for-byte** unchanged:
/// the store was seeded with exactly `[.pro]` and must still hold exactly `[.pro]` afterwards —
/// a tip must neither add a tier nor remove one. It must also never re-resolve entitlements: a
/// tip cannot change ownership, so `ownedTransactions()` must never be queried.
@MainActor
@Test func aSuccessfulTipThanksTheUserAndLeavesEntitlementsByteForByteUnchanged() async throws {
    let fixture = TipFixture(owned: [.pro])
    fixture.stocksTips()
    await fixture.model.load()
    #expect(fixture.store.current == [.pro])

    fixture.client.enqueuePurchase(.success)
    fixture.client.resetCallLog()

    await fixture.model.tip(.tipMedium)

    #expect(fixture.model.phase.isThanked)
    // Neither added (.automation never appears) nor removed (.pro survives): still exactly [.pro].
    #expect(fixture.store.current == [.pro])
    // A tip cannot change entitlements, so re-resolving would be pointless and could race.
    #expect(fixture.client.ownedTransactionsCallCount == 0)
    #expect(fixture.client.purchasedProductIDs == [.tipMedium])
}

/// The whole tip flow is a single `purchase` call and nothing else — no ownership query, no
/// restore, no second products fetch. This is the `callLog` proof that a tip never touches the
/// entitlement resolution path.
@MainActor
@Test func aTipNeverReResolvesEntitlements() async {
    let fixture = TipFixture(owned: [.pro])
    fixture.stocksTips()
    await fixture.model.load()
    fixture.client.enqueuePurchase(.success)
    fixture.client.resetCallLog()

    await fixture.model.tip(.tipLarge)

    #expect(fixture.client.callLog == [.purchase(.tipLarge)])
}

// MARK: - Cancel / failure (no thanks, no entitlement change)

/// Cancelling drops the user back on the idle offer, with no thank-you and no entitlement change.
@MainActor
@Test func aCancelledTipReturnsToTheOfferWithNoThanksAndNoEntitlementChange() async throws {
    let fixture = TipFixture(owned: [.pro])
    fixture.stocksTips()
    await fixture.model.load()
    fixture.client.enqueuePurchase(.cancelled)
    fixture.client.resetCallLog()

    await fixture.model.tip(.tipSmall)

    let products = try #require(fixture.model.phase.offerProducts)
    #expect(products.map(\.id) == ProductCatalog.tips)
    #expect(!fixture.model.phase.isThanked)
    #expect(fixture.store.current == [.pro])
    #expect(fixture.client.ownedTransactionsCallCount == 0)
}

/// A throwing tip is not swallowed into a false thank-you: it returns to the idle offer, and
/// changes nothing.
@MainActor
@Test func aFailedTipReturnsToTheOfferWithNoThanksAndNoEntitlementChange() async throws {
    let fixture = TipFixture(owned: [.pro])
    fixture.stocksTips()
    await fixture.model.load()
    fixture.client.failNextPurchase()
    fixture.client.resetCallLog()

    await fixture.model.tip(.tipSmall)

    let products = try #require(fixture.model.phase.offerProducts)
    #expect(products.map(\.id) == ProductCatalog.tips)
    #expect(!fixture.model.phase.isThanked)
    #expect(fixture.store.current == [.pro])
    #expect(fixture.client.ownedTransactionsCallCount == 0)
}

/// Ask-to-Buy on a consumable: a `.pending` tip has not been paid yet, so there is nothing to
/// thank for. It returns to the idle offer — never a premature thank-you.
@MainActor
@Test func aPendingTipReturnsToTheOfferWithoutThanking() async throws {
    let fixture = TipFixture(owned: [.pro])
    fixture.stocksTips()
    await fixture.model.load()
    fixture.client.enqueuePurchase(.pending)
    fixture.client.resetCallLog()

    await fixture.model.tip(.tipMedium)

    let products = try #require(fixture.model.phase.offerProducts)
    #expect(products.map(\.id) == ProductCatalog.tips)
    #expect(!fixture.model.phase.isThanked)
    #expect(fixture.store.current == [.pro])
}

// MARK: - The tip jar cannot grant an unlock

/// Defense in depth: the tip flow rejects any non-tip id outright, so an unlock can never be
/// slipped through the tip jar to bypass the paid gate (FR-1100-08). Nothing is purchased.
@MainActor
@Test func tippingANonTipIsARejectedNoOp() async {
    let fixture = TipFixture()
    fixture.stocksTips()
    await fixture.model.load()
    fixture.client.resetCallLog()

    await fixture.model.tip(.pro)

    #expect(!fixture.model.phase.isThanked)
    #expect(fixture.client.purchaseCallCount == 0)
    #expect(fixture.store.current == EntitlementSet.none)
}

// MARK: - Consumables never appear in ownership

/// After a successful tip, the store's own ownership query still surfaces no tip — a consumable
/// does not become owned. Seeded with `[.pro]`, the resolved ownership stays exactly `[.pro]`.
///
/// Note the seam limit: `StoreClientFake` is queue-based and does not model purchase → ownership
/// at all, so a tip could never appear here regardless of the flow. The real "consumables do not
/// appear in ownership" guarantee is StoreKit's, mirrored in the shipping `StubStoreClient`,
/// which explicitly inserts *only* unlocks (never tips) into its owned set on purchase.
@MainActor
@Test func theStoreNeverSurfacesATipEvenAfterASuccessfulTip() async throws {
    let fixture = TipFixture(owned: [.pro])
    fixture.stocksTips()
    await fixture.model.load()
    fixture.client.enqueuePurchase(.success)

    await fixture.model.tip(.tipLarge)
    #expect(fixture.model.phase.isThanked)

    let owned = try await fixture.client.ownedTransactions()
    let tipRawValues = Set(ProductCatalog.tips.map(\.rawValue))
    #expect(!owned.contains { tipRawValues.contains($0.productID) })
    #expect(EntitlementResolver.resolve(owned) == [.pro])
}
