/// A product identifier as configured in App Store Connect.
///
/// These raw values are the contract with ASC: drift breaks purchases at runtime with no
/// compile-time signal (contracts/purchasekit-api.md §Product identifiers).
///
/// They deliberately do **not** mirror the bundle id (`ing.kipp.Immich-Slideshow`): ASC accepts
/// only alphanumerics, underscores and periods in a product id, so the bundle id's hyphen is
/// rejected outright. `ProductCatalogTests` pins both the literals and the character set.
public enum ProductID: String, CaseIterable, Sendable, Hashable {
    case supporter = "ing.kipp.ownframe.unlock.supporter"
    case tipSmall = "ing.kipp.ownframe.tip.small"
    case tipMedium = "ing.kipp.ownframe.tip.medium"
    case tipLarge = "ing.kipp.ownframe.tip.large"
}

/// The single source of truth for which products exist and what each one grants.
public enum ProductCatalog {

    /// The non-consumable unlocks. Exactly one — the Supporter Unlock — which grants every gated
    /// capability (FR-1100-02, FR-1100-04). There are no tiers and no bundle.
    public static let unlocks: [ProductID] = [.supporter]

    /// The consumable tips, cheapest first. Tips never grant anything (FR-1100-08).
    public static let tips: [ProductID] = [.tipSmall, .tipMedium, .tipLarge]

    /// The entitlements owning `id` grants.
    ///
    /// Unknown identifiers cannot reach this function — `ProductID(rawValue:)` returns `nil` for
    /// them, and the resolver drops them (forward compatibility with future SKUs).
    public static func grants(_ id: ProductID) -> EntitlementSet {
        switch id {
        case .supporter:
            [.supporter]
        case .tipSmall, .tipMedium, .tipLarge:
            EntitlementSet.none
        }
    }
}
