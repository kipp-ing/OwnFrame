import Foundation

/// The entitlement set as last resolved, persisted so an unattended frame keeps its paid
/// features offline indefinitely (FR-1100-10).
public struct EntitlementSnapshot: Codable, Equatable, Sendable {
    public let entitlements: EntitlementSet

    /// Diagnostic only — the snapshot **never expires**. Age is never a reason to drop a tier.
    public let savedAt: Date

    public init(entitlements: EntitlementSet, savedAt: Date) {
        self.entitlements = entitlements
        self.savedAt = savedAt
    }
}

/// Reads and writes the entitlement snapshot in an injected `UserDefaults` suite.
///
/// Entitlements are not secrets, so `UserDefaults` is the deliberate choice here (research.md
/// R4) — the keychain stays reserved for credentials. The suite is always injected: this type
/// never touches `UserDefaults.standard`, and it owns exactly one key.
///
/// Deliberately not `Sendable`: `UserDefaults` is not `Sendable` under Swift 6, and the cache is
/// only ever used from the `@MainActor`-isolated `EntitlementStore`.
public struct EntitlementSnapshotCache {

    /// The one versioned key this cache owns. Bumping the suffix is how a future format migrates.
    static let storageKey = "purchase.entitlements.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The persisted snapshot, or `nil` when absent, corrupt, or of an unknown shape.
    ///
    /// Never throws and never "repairs" a bad payload into an entitled state — a corrupt cache
    /// simply means "unknown", and the next successful resolve rewrites it.
    public func load() -> EntitlementSnapshot? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(EntitlementSnapshot.self, from: data)
    }

    /// Persists `snapshot`, replacing any previous one. Called only after a *successful* resolve.
    public func save(_ snapshot: EntitlementSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
