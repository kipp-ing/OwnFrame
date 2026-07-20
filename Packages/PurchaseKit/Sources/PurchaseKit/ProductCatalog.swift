/// A product identifier as configured in App Store Connect.
///
/// These raw values are the contract with ASC: drift breaks purchases at runtime with no
/// compile-time signal (contracts/purchasekit-api.md §Product identifiers).
public enum ProductID: String, CaseIterable, Sendable, Hashable {
    case pro = "ing.kipp.Immich-Slideshow.unlock.pro"
    case automation = "ing.kipp.Immich-Slideshow.unlock.automation"
    case everything = "ing.kipp.Immich-Slideshow.unlock.everything"
    case tipSmall = "ing.kipp.Immich-Slideshow.tip.small"
    case tipMedium = "ing.kipp.Immich-Slideshow.tip.medium"
    case tipLarge = "ing.kipp.Immich-Slideshow.tip.large"
}

/// The single source of truth for which products exist and what each one grants.
public enum ProductCatalog {

    /// The non-consumable unlocks, in the order the unlock screen offers them.
    public static let unlocks: [ProductID] = [.pro, .automation, .everything]

    /// The consumable tips, cheapest first. Tips never grant anything (FR-1100-08).
    public static let tips: [ProductID] = [.tipSmall, .tipMedium, .tipLarge]

    /// The tiers owning `id` grants.
    ///
    /// Unknown identifiers cannot reach this function — `ProductID(rawValue:)` returns `nil` for
    /// them, and the resolver drops them (forward compatibility with future SKUs).
    public static func grants(_ id: ProductID) -> EntitlementSet {
        switch id {
        case .pro:
            [.pro]
        case .automation:
            [.automation]
        case .everything:
            EntitlementSet.all
        case .tipSmall, .tipMedium, .tipLarge:
            EntitlementSet.none
        }
    }
}
