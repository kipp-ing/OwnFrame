import Foundation
import StoreKit

/// Failures the StoreKit 2 adapter names itself.
///
/// Store-*reachability* failures are not in here: `Product.products` throws StoreKit's own error
/// when the store can't be reached, and the adapter lets that propagate unchanged so the caller
/// can drive `PurchasePhase.unavailable` (never a placeholder price, FR-1100-16).
public enum StoreKitClientError: Error, Equatable {
    /// A purchase completed but its transaction failed JWS verification — never trusted, never
    /// surfaced as a grant (contracts/purchasekit-api.md §Binding semantics).
    case unverifiedTransaction
    /// The requested product id is not offered by the store, so there is nothing to buy.
    case productUnavailable
}

/// The real StoreKit 2 adapter — the app's single StoreKit touchpoint (T030).
///
/// Everything above the ``StoreClient`` seam is pure, host-testable logic; this thin type is the
/// only place that talks to StoreKit, and it is exercised end to end with `SKTestSession` in
/// `StoreKitClientTests`.
///
/// Two invariants carry the security-adjacent weight:
///
/// - **Only JWS-verified transactions are trusted.** Every `VerificationResult` is unwrapped
///   through ``verified(_:)`` / ``verifiedOrNil(_:)``; an `.unverified` payload is dropped
///   (ownership queries, updates) or rejected (a live purchase), never partially trusted.
/// - **Ownership is answered from `Transaction.currentEntitlements`, StoreKit's own durable
///   ledger — not from a purchase outcome and not from our cache.** That is what makes an
///   interrupted purchase (charged, but the app died before `finish()`) still resolve as owned on
///   the next launch (FR-1100-15): `currentEntitlements` reports non-consumables whether or not
///   they were ever finished. Because ownership never depends on `finish()`, the adapter can
///   finish a transaction as soon as it is delivered without risking a lost unlock — the frozen
///   ``EntitlementStore`` persists its snapshot on the `refresh()` it runs right after a
///   `.success`, and a crash in between is recovered by the next launch's `refresh()`.
public struct StoreKitClient: StoreClient {

    public init() {}

    // MARK: - Products

    public func products(for ids: [ProductID]) async throws -> [DisplayProduct] {
        let products = try await Product.products(for: ids.map(\.rawValue))
        return products.compactMap { product in
            // A store row whose id isn't a known `ProductID` is a future/foreign SKU — ignore it
            // rather than fail the whole fetch (forward compatibility, mirrors the resolver).
            guard let id = ProductID(rawValue: product.id) else { return nil }
            return DisplayProduct(
                id: id,
                displayName: product.displayName,
                displayPrice: product.displayPrice
            )
        }
    }

    // MARK: - Purchase

    public func purchase(_ id: ProductID) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [id.rawValue]).first else {
            throw StoreKitClientError.productUnavailable
        }

        switch try await product.purchase() {
        case .success(let verification):
            // Trust only a verified payload; an unverified "success" grants nothing.
            let transaction = try Self.verified(verification)
            // Delivered — finish so StoreKit stops redelivering it (and a consumable tip leaves
            // the queue). Safe to do now: `currentEntitlements` still reports finished
            // non-consumables, so this can never cost the buyer an unlock (see type doc).
            await transaction.finish()
            return .success
        case .pending:
            // Ask to Buy / deferral. Nothing to finish yet; the approval arrives over `updates`.
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            // A future outcome we can't interpret is treated as "no purchase happened".
            return .cancelled
        }
    }

    // MARK: - Restore

    public func restore() async throws {
        // Platform restore only; the caller re-queries ownership afterwards (FR-1100-11).
        try await AppStore.sync()
    }

    // MARK: - Ownership

    public func ownedTransactions() async throws -> [OwnedTransaction] {
        var owned: [OwnedTransaction] = []
        // `currentEntitlements` is the durable, offline-capable source of truth: the products the
        // user is entitled to right now (non-consumables, active/valid), with refunded ones
        // already dropped. Consumable tips never appear here, so they can't leak into ownership
        // (FR-1100-08). Unverified rows are dropped before mapping.
        for await result in Transaction.currentEntitlements {
            guard let transaction = Self.verifiedOrNil(result) else { continue }
            owned.append(
                OwnedTransaction(
                    productID: transaction.productID,
                    isRevoked: transaction.revocationDate != nil
                )
            )
        }
        return owned
    }

    // MARK: - Updates

    public var updates: AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                // `Transaction.updates` delivers everything that happens outside a direct
                // `purchase()` call: an Ask-to-Buy approval, a purchase on another device, and a
                // previously interrupted purchase completing. Each verified delivery is finished
                // and reported as a *reason to re-resolve* — the payload itself is never trusted
                // as the new state; `EntitlementStore` re-queries `ownedTransactions()`.
                for await result in Transaction.updates {
                    guard let transaction = Self.verifiedOrNil(result) else { continue }
                    await transaction.finish()
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - JWS verification

    /// The verified payload, or a thrown ``StoreKitClientError/unverifiedTransaction`` — used on
    /// the live-purchase path, where an unverified result must not be read as a grant.
    private static func verified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction): return transaction
        case .unverified: throw StoreKitClientError.unverifiedTransaction
        }
    }

    /// The verified payload, or `nil` — used while iterating entitlements/updates, where an
    /// unverified row is simply skipped rather than aborting the whole sweep.
    private static func verifiedOrNil(_ result: VerificationResult<Transaction>) -> Transaction? {
        guard case .verified(let transaction) = result else { return nil }
        return transaction
    }
}
