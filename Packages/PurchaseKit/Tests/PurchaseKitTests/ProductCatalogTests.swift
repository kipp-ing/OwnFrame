import Foundation
import Testing
@testable import PurchaseKit

// T004 — RED tests for `Entitlement` / `EntitlementSet` basics and the `ProductCatalog`
// product-id + tier mapping (data-model.md §Entitlement, §ProductID / ProductCatalog).
//
// The raw values below are the contract with App Store Connect: any drift breaks purchases at
// runtime with no compile-time signal (contracts/purchasekit-api.md §Product identifiers), so
// they are asserted literally rather than derived from the type.

// MARK: - Entitlement / EntitlementSet basics

@Test func entitlementHasExactlyTheTwoPaidTiers() {
    #expect(Entitlement.allCases.count == 2)
    #expect(Set(Entitlement.allCases) == [.pro, .automation])
}

@Test func entitlementRoundTripsThroughCodable() throws {
    let encoded = try JSONEncoder().encode([Entitlement.pro, Entitlement.automation])
    let decoded = try JSONDecoder().decode([Entitlement].self, from: encoded)

    #expect(decoded == [.pro, .automation])
}

@Test func entitlementSetNoneIsEmpty() {
    let none = EntitlementSet.none

    #expect(none.isEmpty)
    #expect(none.contains(.pro) == false)
    #expect(none.contains(.automation) == false)
}

@Test func entitlementSetAllContainsEveryTier() {
    let all = EntitlementSet.all

    #expect(all.count == 2)
    #expect(all.contains(.pro))
    #expect(all.contains(.automation))
    #expect(all == Set(Entitlement.allCases))
}

@Test func entitlementSetContainsDiscriminatesBetweenTiers() {
    let proOnly: EntitlementSet = [.pro]

    #expect(proOnly.contains(.pro))
    #expect(proOnly.contains(.automation) == false)
}

// MARK: - Product identifiers (must match App Store Connect exactly)

@Test func productIdentifierRawValuesMatchAppStoreConnect() {
    #expect(ProductID.pro.rawValue == "ing.kipp.Immich-Slideshow.unlock.pro")
    #expect(ProductID.automation.rawValue == "ing.kipp.Immich-Slideshow.unlock.automation")
    #expect(ProductID.everything.rawValue == "ing.kipp.Immich-Slideshow.unlock.everything")
    #expect(ProductID.tipSmall.rawValue == "ing.kipp.Immich-Slideshow.tip.small")
    #expect(ProductID.tipMedium.rawValue == "ing.kipp.Immich-Slideshow.tip.medium")
    #expect(ProductID.tipLarge.rawValue == "ing.kipp.Immich-Slideshow.tip.large")
}

@Test func productIdentifierIsConstructibleFromItsRawValue() {
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.unlock.pro") == .pro)
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.unlock.automation") == .automation)
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.unlock.everything") == .everything)
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.tip.small") == .tipSmall)
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.tip.medium") == .tipMedium)
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.tip.large") == .tipLarge)
}

/// Forward compatibility: a future SKU is simply not in the catalog — never fatal.
@Test func unknownProductIdentifiersAreNotInTheCatalog() {
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.unlock.future") == nil)
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.unlock.PRO") == nil)
    #expect(ProductID(rawValue: "com.example.other.unlock.pro") == nil)
    #expect(ProductID(rawValue: "") == nil)
}

// MARK: - Catalog buckets

@Test func catalogListsTheThreeUnlocksInOfferOrder() {
    #expect(ProductCatalog.unlocks == [.pro, .automation, .everything])
}

@Test func catalogListsTheThreeTipsInAscendingOrder() {
    #expect(ProductCatalog.tips == [.tipSmall, .tipMedium, .tipLarge])
}

@Test func catalogPartitionsEveryKnownProductIntoExactlyOneBucket() {
    let unlocks = Set(ProductCatalog.unlocks)
    let tips = Set(ProductCatalog.tips)

    #expect(unlocks.isDisjoint(with: tips))
    #expect(unlocks.union(tips) == Set(ProductID.allCases))
}

// MARK: - grants(_:) tier mapping

@Test func proGrantsOnlyTheProTier() {
    #expect(ProductCatalog.grants(.pro) == [.pro])
}

@Test func automationGrantsOnlyTheAutomationTier() {
    #expect(ProductCatalog.grants(.automation) == [.automation])
}

/// The everything-bundle is a *product* that grants both tiers — it is never an entitlement of
/// its own (data-model.md §Entitlement).
@Test func everythingBundleGrantsBothTiers() {
    #expect(ProductCatalog.grants(.everything) == [.pro, .automation])
    #expect(ProductCatalog.grants(.everything) == EntitlementSet.all)
}

/// FR-1100-08: tips are pure goodwill and never unlock anything.
@Test func tipsGrantNothing() {
    #expect(ProductCatalog.grants(.tipSmall).isEmpty)
    #expect(ProductCatalog.grants(.tipMedium).isEmpty)
    #expect(ProductCatalog.grants(.tipLarge).isEmpty)
}

@Test func everyUnlockGrantsAtLeastOneTierAndNoTipDoes() {
    for unlock in ProductCatalog.unlocks {
        #expect(ProductCatalog.grants(unlock).isEmpty == false)
    }
    for tip in ProductCatalog.tips {
        #expect(ProductCatalog.grants(tip) == EntitlementSet.none)
    }
}
