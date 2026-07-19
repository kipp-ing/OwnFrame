import Foundation
import Observation

/// The app-wide entitlement model: what the user owns, right now, observable by every gate.
///
/// State machine (data-model.md §EntitlementStore):
/// - **Launch** — `current` is seeded from the snapshot cache *synchronously*, with no await and
///   no store contact, so an unattended frame renders entitled on its very first pass while
///   offline (FR-1100-10).
/// - **Refresh success** — `current` becomes the resolved set and is persisted. This is the only
///   path that can shrink it, which is how a revocation takes effect (FR-1100-12).
/// - **Refresh failure / offline** — `current` is left alone (last known good). Nothing is
///   persisted; a failed query means "unknown", never "owns nothing".
@MainActor
@Observable
public final class EntitlementStore {

    /// The tiers the user currently holds. Safe to branch on in the first render pass.
    public private(set) var current: EntitlementSet

    @ObservationIgnored private let client: any StoreClient
    @ObservationIgnored private let cache: EntitlementSnapshotCache

    /// Seeds `current` from the cache synchronously.
    ///
    /// Deliberately starts no task and touches `client` in no way — a caller may inspect
    /// `current` immediately after construction with no intervening suspension. Listening for
    /// store updates is opt-in via ``listenForUpdates()``.
    public init(client: any StoreClient, cache: EntitlementSnapshotCache) {
        self.client = client
        self.cache = cache
        self.current = cache.load()?.entitlements ?? EntitlementSet.none
    }

    /// Re-resolves ownership from the store, then applies and persists the result.
    ///
    /// A failed query leaves `current` untouched: offline is not evidence of non-ownership.
    public func refresh() async {
        guard let transactions = try? await client.ownedTransactions() else { return }
        apply(EntitlementResolver.resolve(transactions))
    }

    /// Runs the platform restore, then refreshes (FR-1100-11).
    ///
    /// A sync failure propagates and no refresh is attempted — a restore that never reached the
    /// store must not be read as a resolve.
    public func restore() async throws {
        try await client.restore()
        await refresh()
    }

    /// Starts consuming ``StoreClient/updates`` so purchases made elsewhere, Ask-to-Buy
    /// approvals, and pushed revocations re-resolve entitlements (FR-1100-15).
    ///
    /// - Important: Not implemented yet — behaviour lands in T029, after its red tests exist
    ///   (constitution I, test-first). It is a separate, explicitly-called method rather than
    ///   init work so that construction stays synchronous and store-free.
    public func listenForUpdates() {
        // T029.
    }

    /// Applies a freshly resolved set and persists it as the new last-known-good snapshot.
    private func apply(_ resolved: EntitlementSet) {
        current = resolved
        cache.save(EntitlementSnapshot(entitlements: resolved, savedAt: Date()))
    }
}
