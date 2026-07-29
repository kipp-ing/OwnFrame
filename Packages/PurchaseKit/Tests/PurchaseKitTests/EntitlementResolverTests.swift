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

/// The one unlock grants the whole entitlement set — `[.supporter]` is `EntitlementSet.all`.
// @covers FR-1100-04
@Test func rule1OwnedSupporterUnlockGrantsTheFullEntitlementSet() {
    #expect(EntitlementResolver.resolve([owned(.supporter)]) == [.supporter])
    #expect(EntitlementResolver.resolve([owned(.supporter)]) == EntitlementSet.all)
}

/// The reduce unions grants, so owning the same unlock across two transactions (a re-purchase)
/// resolves to the same single set rather than doubling it.
@Test func rule1OverlappingGrantsDoNotDuplicate() {
    let resolved = EntitlementResolver.resolve([owned(.supporter), owned(.supporter)])

    #expect(resolved == EntitlementSet.all)
    #expect(resolved.count == 1)
}

@Test func rule1TransactionOrderDoesNotMatter() {
    let forward = EntitlementResolver.resolve([owned(.supporter), owned(.tipLarge)])
    let reversed = EntitlementResolver.resolve([owned(.tipLarge), owned(.supporter)])

    #expect(forward == reversed)
    #expect(forward == EntitlementSet.all)
}

// MARK: - Rule 2 — isRevoked == true contributes nothing (FR-1100-12)

// @covers FR-1100-12
@Test func rule2RevokedUnlockContributesNothing() {
    #expect(EntitlementResolver.resolve([owned(.supporter, revoked: true)]).isEmpty)
    #expect(EntitlementResolver.resolve([owned(.supporter, revoked: true)]) == EntitlementSet.none)
}

/// Revocation is evaluated per transaction, not per product: the *same* unlock owned both revoked
/// and non-revoked (a re-purchase after a refund) still grants — the live transaction contributes,
/// the revoked one does not. With a single unlock this is the whole of the per-transaction rule.
// @covers FR-1100-12
@Test func rule2SameProductOwnedRevokedAndNonRevokedStillGrants() {
    let revokedFirst = EntitlementResolver.resolve([
        owned(.supporter, revoked: true),
        owned(.supporter),
    ])
    let revokedLast = EntitlementResolver.resolve([
        owned(.supporter),
        owned(.supporter, revoked: true),
    ])

    #expect(revokedFirst == [.supporter])
    #expect(revokedLast == [.supporter])
}

// @covers FR-1100-12
@Test func rule2AllTransactionsRevokedResolvesToEmpty() {
    let resolved = EntitlementResolver.resolve([
        owned(.supporter, revoked: true),
        owned(.supporter, revoked: true),
    ])

    #expect(resolved == EntitlementSet.none)
}

// MARK: - Rule 3 — tips contribute nothing (FR-1100-08)

// @covers FR-1100-08
@Test func rule3TipsAloneResolveToEmpty() {
    let resolved = EntitlementResolver.resolve([
        owned(.tipSmall),
        owned(.tipMedium),
        owned(.tipLarge),
    ])

    #expect(resolved.isEmpty)
}

// @covers FR-1100-08
@Test func rule3TipsDoNotChangeAnExistingEntitlement() {
    let withoutTips = EntitlementResolver.resolve([owned(.supporter)])
    let withTips = EntitlementResolver.resolve([owned(.supporter), owned(.tipLarge), owned(.tipSmall)])

    #expect(withTips == withoutTips)
    #expect(withTips == [.supporter])
}

// MARK: - Rule 4 — unknown product ids contribute nothing

@Test func rule4UnknownProductIdentifiersAreIgnored() {
    let resolved = EntitlementResolver.resolve([
        OwnedTransaction(productID: "ing.kipp.ownframe.unlock.future", isRevoked: false),
        OwnedTransaction(productID: "com.example.other.unlock.supporter", isRevoked: false),
        OwnedTransaction(productID: "", isRevoked: false),
    ])

    #expect(resolved.isEmpty)
}

@Test func rule4UnknownProductIdentifiersDoNotDisturbKnownOnes() {
    let resolved = EntitlementResolver.resolve([
        OwnedTransaction(productID: "ing.kipp.ownframe.unlock.future", isRevoked: false),
        owned(.supporter),
    ])

    #expect(resolved == [.supporter])
}

// MARK: - Rule 5 — empty input → {}

@Test func rule5EmptyInputResolvesToEmptySet() {
    #expect(EntitlementResolver.resolve([]) == EntitlementSet.none)
    #expect(EntitlementResolver.resolve([]).isEmpty)
}
