/// One verified transaction, reduced to the minimum the resolver needs.
///
/// The adapter drops JWS-unverified transactions before building these, so an
/// `OwnedTransaction` is always trustworthy by construction (contracts/purchasekit-api.md).
/// `productID` stays a `String` rather than a `ProductID` so unknown/future SKUs travel through
/// the seam and are ignored by the resolver instead of being fatal at the boundary.
public struct OwnedTransaction: Hashable, Sendable {
    public let productID: String
    public let isRevoked: Bool

    public init(productID: String, isRevoked: Bool) {
        self.productID = productID
        self.isRevoked = isRevoked
    }
}

/// The result of a purchase attempt. `.pending` is an Ask-to-Buy deferral, not an error.
public enum PurchaseOutcome: Equatable, Sendable {
    case success
    case pending
    case cancelled
}

/// A product ready to display: name and price already localized by the store.
///
/// PurchaseKit never formats prices itself and never substitutes a placeholder — when the store
/// is unreachable there are simply no `DisplayProduct`s to show (FR-1100-16).
public struct DisplayProduct: Equatable, Sendable, Identifiable {
    public let id: ProductID
    public let displayName: String
    public let displayPrice: String

    public init(id: ProductID, displayName: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
    }
}

/// The only StoreKit touchpoint in the app (contracts/purchasekit-api.md §StoreClient).
///
/// Everything above this seam is pure, host-testable logic; everything below it is the thin
/// `StoreKitClient` adapter, which is exercised with `SKTestSession`.
public protocol StoreClient: Sendable {
    /// Localized, ready-to-display products for the given ids.
    /// Throws when the store is unreachable (drives `PurchasePhase.unavailable`).
    func products(for ids: [ProductID]) async throws -> [DisplayProduct]

    /// Initiates purchase. `.pending` = Ask to Buy deferral (not an error).
    func purchase(_ id: ProductID) async throws -> PurchaseOutcome

    /// Triggers the platform restore (`AppStore.sync()`); caller refreshes afterwards.
    func restore() async throws

    /// Current verified ownership. Must answer from local state when offline if the
    /// platform allows; a throw means "unknown", never "nothing owned".
    func ownedTransactions() async throws -> [OwnedTransaction]

    /// Long-lived stream of ownership changes (new purchases, Ask-to-Buy approvals,
    /// revocations). Elements are the *reason* to re-query `ownedTransactions`.
    var updates: AsyncStream<Void> { get }
}
