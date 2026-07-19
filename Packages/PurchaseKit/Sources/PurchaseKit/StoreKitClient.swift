import Foundation

/// Failures raised by the StoreKit 2 adapter.
public enum StoreKitClientError: Error, Equatable {
    /// The adapter has no behaviour yet — see ``StoreKitClient``.
    case notImplemented
}

/// The real StoreKit 2 adapter — **skeleton only** (T013).
///
/// This type exists so the rest of PurchaseKit and the app targets can compile and link against
/// a concrete `StoreClient`. It contains no StoreKit logic on purpose: its behaviour (product
/// lookup, purchase, `AppStore.sync()`, `Transaction.currentEntitlements` / `.updates`, JWS
/// verification, and finishing transactions only after the snapshot has persisted) lands in T030,
/// once its `SKTestSession` cases are red — writing it here would be untested production code
/// (constitution I, NON-NEGOTIABLE).
///
/// Until then every call throws ``StoreKitClientError/notImplemented`` and `updates` is an
/// immediately-finished stream. Nothing ships on this path: app wiring targets the protocol.
public struct StoreKitClient: StoreClient {

    public init() {}

    public var updates: AsyncStream<Void> {
        AsyncStream { continuation in continuation.finish() }
    }

    public func products(for ids: [ProductID]) async throws -> [DisplayProduct] {
        throw StoreKitClientError.notImplemented
    }

    public func purchase(_ id: ProductID) async throws -> PurchaseOutcome {
        throw StoreKitClientError.notImplemented
    }

    public func restore() async throws {
        throw StoreKitClientError.notImplemented
    }

    public func ownedTransactions() async throws -> [OwnedTransaction] {
        throw StoreKitClientError.notImplemented
    }
}
