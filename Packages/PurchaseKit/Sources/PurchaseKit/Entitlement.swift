/// The single paid entitlement (spec 1100, data-model.md §Entitlement).
///
/// Entitlements are *derived* from owned transactions, never stored per feature: a gate asks
/// `entitlements.contains(.supporter)` at the point of effect. There is exactly one functional
/// unlock — the Supporter Unlock (FR-1100-02, FR-1100-04) — so this enum holds one case. The type
/// stays a `Set` so the resolver, cache, and UI-test seams keep their existing shape.
public enum Entitlement: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    /// The Supporter Unlock: Ken Burns motion, the clock overlay, and Home Assistant remote
    /// control plus Shortcuts/App Intents — every gated capability, in one purchase.
    case supporter

    /// Lets the unlock drive `.sheet(item:)` when a locked row asks for its unlock screen.
    public var id: String { rawValue }
}

/// The set of entitlements a user currently holds.
public typealias EntitlementSet = Set<Entitlement>

extension Set where Element == Entitlement {

    /// Owns nothing — the free core, which is whole on its own.
    ///
    /// - Note: Written as `EntitlementSet.none` at every use site. Unqualified `.none` in an
    ///   optional context would resolve to `Optional.none` instead.
    public static var none: EntitlementSet { [] }

    /// Everything the Supporter Unlock grants.
    public static var all: EntitlementSet { EntitlementSet(Entitlement.allCases) }
}
