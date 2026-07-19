import Foundation
import Testing
@testable import PurchaseKit

// T006 — RED tests for the pure resolver (data-model.md §EntitlementResolver).
// The five numbered rules are covered one test each, plus the combination cases that decide
// whether revocation is evaluated per transaction or per product.
//
// The resolver only ever sees *verified* transactions: unverified JWS is dropped inside the
// adapter and never reaches here (contracts/purchasekit-api.md).

private func owned(_ id: ProductID, revoked: Bool = false) -> OwnedTransaction {
    OwnedTransaction(productID: id.rawValue, isRevoked: revoked)
}

// MARK: - Rule 1 — non-revoked owned product → union of ProductCatalog.grants

@Test func rule1SingleOwnedUnlockGrantsItsTier() {
    #expect(EntitlementResolver.resolve([owned(.pro)]) == [.pro])
    #expect(EntitlementResolver.resolve([owned(.automation)]) == [.automation])
}

@Test func rule1OwnedBundleGrantsBothTiers() {
    #expect(EntitlementResolver.resolve([owned(.everything)]) == EntitlementSet.all)
}

@Test func rule1SeparateUnlocksUnionIntoTheFullSet() {
    let resolved = EntitlementResolver.resolve([owned(.pro), owned(.automation)])

    #expect(resolved == EntitlementSet.all)
}

@Test func rule1OverlappingGrantsDoNotDuplicate() {
    let resolved = EntitlementResolver.resolve([owned(.everything), owned(.pro)])

    #expect(resolved == EntitlementSet.all)
    #expect(resolved.count == 2)
}

@Test func rule1TransactionOrderDoesNotMatter() {
    let forward = EntitlementResolver.resolve([owned(.pro), owned(.everything), owned(.tipLarge)])
    let reversed = EntitlementResolver.resolve([owned(.tipLarge), owned(.everything), owned(.pro)])

    #expect(forward == reversed)
    #expect(forward == EntitlementSet.all)
}

// MARK: - Rule 2 — isRevoked == true contributes nothing (FR-1100-12)

@Test func rule2RevokedUnlockContributesNothing() {
    #expect(EntitlementResolver.resolve([owned(.pro, revoked: true)]).isEmpty)
    #expect(EntitlementResolver.resolve([owned(.automation, revoked: true)]).isEmpty)
}

@Test func rule2RevokedBundleContributesNothing() {
    #expect(EntitlementResolver.resolve([owned(.everything, revoked: true)]) == EntitlementSet.none)
}

/// Revocation is evaluated per transaction, not globally: a refunded bundle must not take an
/// independently owned unlock down with it.
@Test func rule2RevokedBundleLeavesAnIndependentlyOwnedUnlockIntact() {
    let resolved = EntitlementResolver.resolve([
        owned(.everything, revoked: true),
        owned(.automation),
    ])

    #expect(resolved == [.automation])
    #expect(resolved.contains(.pro) == false)
}

/// Combination case: the *same* product owned both revoked and non-revoked (re-purchase after a
/// refund). The non-revoked transaction still grants; the revoked one contributes nothing.
@Test func rule2SameProductOwnedRevokedAndNonRevokedStillGrants() {
    let revokedFirst = EntitlementResolver.resolve([
        owned(.pro, revoked: true),
        owned(.pro),
    ])
    let revokedLast = EntitlementResolver.resolve([
        owned(.pro),
        owned(.pro, revoked: true),
    ])

    #expect(revokedFirst == [.pro])
    #expect(revokedLast == [.pro])
}

@Test func rule2AllTransactionsRevokedResolvesToEmpty() {
    let resolved = EntitlementResolver.resolve([
        owned(.pro, revoked: true),
        owned(.automation, revoked: true),
        owned(.everything, revoked: true),
    ])

    #expect(resolved == EntitlementSet.none)
}

// MARK: - Rule 3 — tips contribute nothing (FR-1100-08)

@Test func rule3TipsAloneResolveToEmpty() {
    let resolved = EntitlementResolver.resolve([
        owned(.tipSmall),
        owned(.tipMedium),
        owned(.tipLarge),
    ])

    #expect(resolved.isEmpty)
}

@Test func rule3TipsDoNotChangeAnExistingEntitlement() {
    let withoutTips = EntitlementResolver.resolve([owned(.pro)])
    let withTips = EntitlementResolver.resolve([owned(.pro), owned(.tipLarge), owned(.tipSmall)])

    #expect(withTips == withoutTips)
    #expect(withTips == [.pro])
}

// MARK: - Rule 4 — unknown product ids contribute nothing

@Test func rule4UnknownProductIdentifiersAreIgnored() {
    let resolved = EntitlementResolver.resolve([
        OwnedTransaction(productID: "ing.kipp.Immich-Slideshow.unlock.future", isRevoked: false),
        OwnedTransaction(productID: "com.example.other.unlock.pro", isRevoked: false),
        OwnedTransaction(productID: "", isRevoked: false),
    ])

    #expect(resolved.isEmpty)
}

@Test func rule4UnknownProductIdentifiersDoNotDisturbKnownOnes() {
    let resolved = EntitlementResolver.resolve([
        OwnedTransaction(productID: "ing.kipp.Immich-Slideshow.unlock.future", isRevoked: false),
        owned(.pro),
    ])

    #expect(resolved == [.pro])
}

// MARK: - Rule 5 — empty input → {}

@Test func rule5EmptyInputResolvesToEmptySet() {
    #expect(EntitlementResolver.resolve([]) == EntitlementSet.none)
    #expect(EntitlementResolver.resolve([]).isEmpty)
}
