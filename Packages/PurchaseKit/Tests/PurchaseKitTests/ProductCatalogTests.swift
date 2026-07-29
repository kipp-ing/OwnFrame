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

@Test func entitlementHasExactlyTheSingleSupporterUnlock() {
    #expect(Entitlement.allCases.count == 1)
    #expect(Set(Entitlement.allCases) == [.supporter])
}

@Test func entitlementRoundTripsThroughCodable() throws {
    let encoded = try JSONEncoder().encode([Entitlement.supporter])
    let decoded = try JSONDecoder().decode([Entitlement].self, from: encoded)

    #expect(decoded == [.supporter])
}

@Test func entitlementSetNoneIsEmpty() {
    let none = EntitlementSet.none

    #expect(none.isEmpty)
    #expect(none.contains(.supporter) == false)
}

@Test func entitlementSetAllContainsTheSupporterUnlock() {
    let all = EntitlementSet.all

    #expect(all.count == 1)
    #expect(all.contains(.supporter))
    #expect(all == Set(Entitlement.allCases))
}

/// With a single functional unlock, `.all` and `[.supporter]` are the same set — the whole point
/// of the collapse. Membership still reads correctly on both ends.
@Test func entitlementSetContainsReflectsMembership() {
    let owned: EntitlementSet = [.supporter]

    #expect(owned.contains(.supporter))
    #expect(EntitlementSet.none.contains(.supporter) == false)
    #expect(EntitlementSet.all == [.supporter])
}

// MARK: - Product identifiers (must match App Store Connect exactly)

@Test func productIdentifierRawValuesMatchAppStoreConnect() {
    #expect(ProductID.supporter.rawValue == "ing.kipp.ownframe.unlock.supporter")
    #expect(ProductID.tipSmall.rawValue == "ing.kipp.ownframe.tip.small")
    #expect(ProductID.tipMedium.rawValue == "ing.kipp.ownframe.tip.medium")
    #expect(ProductID.tipLarge.rawValue == "ing.kipp.ownframe.tip.large")
}

/// App Store Connect rejects a product id containing anything but alphanumerics, underscores and
/// periods — a hyphen 409s at creation time. The ids used to be derived from the bundle id
/// (`ing.kipp.Immich-Slideshow`), whose hyphen is legal there and illegal here; this pins the
/// distinction so the two can never be conflated again.
@Test func productIdentifiersUseOnlyCharactersAppStoreConnectAccepts() {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
    for id in ProductID.allCases {
        #expect(
            id.rawValue.unicodeScalars.allSatisfy(allowed.contains),
            "\(id.rawValue) contains a character App Store Connect rejects"
        )
    }
}

@Test func productIdentifierIsConstructibleFromItsRawValue() {
    #expect(ProductID(rawValue: "ing.kipp.ownframe.unlock.supporter") == .supporter)
    #expect(ProductID(rawValue: "ing.kipp.ownframe.tip.small") == .tipSmall)
    #expect(ProductID(rawValue: "ing.kipp.ownframe.tip.medium") == .tipMedium)
    #expect(ProductID(rawValue: "ing.kipp.ownframe.tip.large") == .tipLarge)
}

/// Forward compatibility: a future SKU is simply not in the catalog — never fatal. The retired
/// `.pro`/`.automation`/`.everything` ids are now just such unknowns, and so are the
/// never-created `ing.kipp.Immich-Slideshow.*` ids this catalog carried before the rename.
@Test func unknownProductIdentifiersAreNotInTheCatalog() {
    #expect(ProductID(rawValue: "ing.kipp.ownframe.unlock.future") == nil)
    #expect(ProductID(rawValue: "ing.kipp.ownframe.unlock.SUPPORTER") == nil)
    #expect(ProductID(rawValue: "ing.kipp.ownframe.unlock.pro") == nil)
    #expect(ProductID(rawValue: "ing.kipp.Immich-Slideshow.unlock.supporter") == nil)
    #expect(ProductID(rawValue: "com.example.other.unlock.supporter") == nil)
    #expect(ProductID(rawValue: "") == nil)
}

// MARK: - Catalog buckets

@Test func catalogListsTheSingleUnlock() {
    #expect(ProductCatalog.unlocks == [.supporter])
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

/// The one unlock grants the whole entitlement set — there are no tiers and no bundle, so owning
/// the Supporter Unlock is owning everything gated (data-model.md §Entitlement).
// @covers FR-1100-04
@Test func supporterGrantsTheFullEntitlementSet() {
    #expect(ProductCatalog.grants(.supporter) == [.supporter])
    #expect(ProductCatalog.grants(.supporter) == EntitlementSet.all)
}

/// FR-1100-08: tips are pure goodwill and never unlock anything.
// @covers FR-1100-08
@Test func tipsGrantNothing() {
    #expect(ProductCatalog.grants(.tipSmall).isEmpty)
    #expect(ProductCatalog.grants(.tipMedium).isEmpty)
    #expect(ProductCatalog.grants(.tipLarge).isEmpty)
}

// @covers FR-1100-08
@Test func everyUnlockGrantsAtLeastOneTierAndNoTipDoes() {
    for unlock in ProductCatalog.unlocks {
        #expect(ProductCatalog.grants(unlock).isEmpty == false)
    }
    for tip in ProductCatalog.tips {
        #expect(ProductCatalog.grants(tip) == EntitlementSet.none)
    }
}
