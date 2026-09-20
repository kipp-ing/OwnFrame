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
    /// The single live ``listenForUpdates()`` consumer, or nil before it starts.
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// The wait between ``refreshUntilOwns(_:)`` attempts. Real `Task.sleep` in production;
    /// tests inject a no-op so the retry path stays instant (no real sleeps in this suite).
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void

    deinit { updatesTask?.cancel() }

    /// The store's own StoreKit seam, read-only.
    ///
    /// Exists so a purchase surface reached from the environment (``UnlockScreenView``) can build
    /// its ``PurchaseViewModel`` against *this* store's client rather than the app threading a
    /// second copy through the environment — two seams that could disagree about which store the
    /// screen is talking to. Get-only by design: the client is fixed at construction, and nothing
    /// outside may swap it.
    public var storeClient: any StoreClient { client }

    /// Seeds `current` from the cache synchronously.
    ///
    /// Deliberately starts no task and touches `client` in no way — a caller may inspect
    /// `current` immediately after construction with no intervening suspension. Listening for
    /// store updates is opt-in via ``listenForUpdates()``.
    public init(
        client: any StoreClient,
        cache: EntitlementSnapshotCache,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.cache = cache
        self.current = cache.load()?.entitlements ?? EntitlementSet.none
        self.sleep = sleep
    }

    /// Re-resolves ownership from the store, then applies and persists the result.
    ///
    /// A failed query leaves `current` untouched: offline is not evidence of non-ownership.
    public func refresh() async {
        guard let transactions = try? await client.ownedTransactions() else { return }
        apply(EntitlementResolver.resolve(transactions))
    }

    /// Refreshes, then retries a couple more times if `id`'s grant still isn't reflected in
    /// `current` (issue #79).
    ///
    /// Right after `StoreClient.purchase(_:)` reports success, its local transaction store can
    /// briefly lag before `ownedTransactions()` reflects the new purchase — so a single `refresh()`
    /// straight after a buy can read the pre-purchase entitlements. The outcome is still never
    /// treated as a grant on its own (FR-1100-13's principle): this polls the real resolve instead
    /// of assuming, and gives up after 3 attempts rather than looping forever if the entitlement
    /// genuinely never lands.
    public func refreshUntilOwns(_ id: ProductID) async {
        for attempt in 0..<3 {
            await refresh()
            if ProductCatalog.grants(id).isSubset(of: current) { return }
            if attempt < 2 {
                await sleep(.milliseconds(300))
            }
        }
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
    /// Every event routes through ``refresh()``, which is what makes the outcomes consistent with
    /// every other path: a success applies *and* persists, and a failed re-resolve leaves both
    /// `current` and the snapshot untouched rather than reading a dropped connection as a loss
    /// (FR-1100-13).
    ///
    /// Deliberately not called from `init` — construction stays synchronous and store-free so the
    /// first render can branch on `current` with no await (FR-1100-10). The caller starts this
    /// once the app is up.
    ///
    /// Idempotent: a second call is a no-op. `AsyncStream` supports a single consumer, so
    /// spawning a second loop would split events between two readers and lose half of them.
    public func listenForUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            guard let updates = self?.client.updates else { return }
            // `weak` inside the loop too: the task outlives a deallocated store otherwise, and a
            // test fixture's store would be kept alive by its own listener.
            for await _ in updates {
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    /// Applies a freshly resolved set and persists it as the new last-known-good snapshot.
    private func apply(_ resolved: EntitlementSet) {
        current = resolved
        cache.save(EntitlementSnapshot(entitlements: resolved, savedAt: Date()))
    }
}
