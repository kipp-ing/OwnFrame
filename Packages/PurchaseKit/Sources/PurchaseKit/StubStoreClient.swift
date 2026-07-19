import Foundation

// DEBUG-only by design. This type can hand out entitlements nobody paid for, so it must not
// exist in a shipping binary at all — not merely be unreachable there. SPM builds a package
// with the configuration of the app embedding it, so an archived Release build compiles this
// file away entirely. Both call sites are `#if DEBUG` too; this is the second lock.
#if DEBUG

/// A deterministic in-memory ``StoreClient`` for hermetic UI tests (contracts/uitest-seams.md).
///
/// This is a test seam, not a shipping code path: the app only ever constructs it behind the
/// `--uitest-store=` launch argument, so a production launch never reaches it. It exists in the
/// package rather than the app target so both the iOS and tvOS targets can share one stub.
///
/// Purchases mutate the stub's own ownership set, so a stubbed buy flows back through the normal
/// ``EntitlementStore/refresh()`` path rather than poking `current` directly — the UI test then
/// exercises the same code the real store drives.
public final class StubStoreClient: StoreClient, @unchecked Sendable {

    /// Which failure mode the stub models, per `--uitest-store=<value>`.
    public enum Behavior: String, Sendable {
        /// Products load; purchases succeed immediately.
        case stub
        /// `products(for:)` throws — drives the unlock screen's unavailable state (FR-1100-16).
        case unavailable
        /// Purchases return `.pending` — drives the Ask-to-Buy state (FR-1100-15).
        case pending
    }

    public enum StubError: Error, Equatable {
        case storeUnavailable
    }

    private let lock = NSLock()
    private let behavior: Behavior
    private var owned: Set<ProductID>
    private let continuation: AsyncStream<Void>.Continuation

    public let updates: AsyncStream<Void>

    /// - Parameters:
    ///   - behavior: the modelled store condition.
    ///   - owned: products already owned when the stub is created. Note this seeds the *store*,
    ///     which is a different seam from `--uitest-entitlements=` seeding the snapshot cache.
    public init(behavior: Behavior = .stub, owned: Set<ProductID> = []) {
        self.behavior = behavior
        self.owned = owned
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.updates = stream
        self.continuation = continuation
    }

    deinit { continuation.finish() }

    /// Prices are fixed placeholder strings. UI tests must assert that a price label *exists*,
    /// never its value — real pricing lives in App Store Connect and stays out of this repo.
    public func products(for ids: [ProductID]) async throws -> [DisplayProduct] {
        guard behavior != .unavailable else { throw StubError.storeUnavailable }
        return ids.map {
            DisplayProduct(id: $0, displayName: $0.stubDisplayName, displayPrice: "$1.00")
        }
    }

    public func purchase(_ id: ProductID) async throws -> PurchaseOutcome {
        switch behavior {
        case .unavailable:
            throw StubError.storeUnavailable
        case .pending:
            // Ask to Buy: no ownership yet. The approval would arrive over `updates`.
            return .pending
        case .stub:
            // Tips are consumable: they complete but never become ownership (FR-1100-08).
            if ProductCatalog.unlocks.contains(id) {
                lock.withLock { _ = owned.insert(id) }
                continuation.yield()
            }
            return .success
        }
    }

    public func restore() async throws {
        guard behavior != .unavailable else { throw StubError.storeUnavailable }
        continuation.yield()
    }

    public func ownedTransactions() async throws -> [OwnedTransaction] {
        guard behavior != .unavailable else { throw StubError.storeUnavailable }
        return lock.withLock { owned }
            .map { OwnedTransaction(productID: $0.rawValue, isRevoked: false) }
    }
}

private extension ProductID {
    var stubDisplayName: String {
        switch self {
        case .pro: "Pro"
        case .automation: "Automation"
        case .everything: "Everything"
        case .tipSmall: "Small Tip"
        case .tipMedium: "Medium Tip"
        case .tipLarge: "Large Tip"
        }
    }
}

#endif
