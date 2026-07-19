/// A paid capability tier (spec 1100, data-model.md §Entitlement).
///
/// Entitlements are *derived* from owned transactions, never stored per feature: a gate asks
/// `entitlements.contains(.pro)` at the point of effect. The everything-bundle is deliberately
/// absent — it is a product that grants both tiers, not a tier of its own, which keeps the
/// entitlement space closed under future SKUs.
public enum Entitlement: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    /// Ambience: Ken Burns motion and the clock overlay.
    case pro
    /// Automation: HA/MQTT remote control and App Intents.
    case automation

    /// Lets a tier drive `.sheet(item:)` when a locked row asks for its unlock screen.
    public var id: String { rawValue }
}

/// The set of tiers a user currently holds.
public typealias EntitlementSet = Set<Entitlement>

extension Set where Element == Entitlement {

    /// Owns nothing — the free core, which is whole on its own.
    ///
    /// - Note: Written as `EntitlementSet.none` at every use site. Unqualified `.none` in an
    ///   optional context would resolve to `Optional.none` instead.
    public static var none: EntitlementSet { [] }

    /// Every tier — what the everything-bundle grants.
    public static var all: EntitlementSet { EntitlementSet(Entitlement.allCases) }
}
