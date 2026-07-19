/// PurchaseKit — purchase gate and entitlement model for the one-time unlocks (spec 1100).
///
/// All StoreKit contact is confined to the `StoreClient` adapter; everything else is pure,
/// host-testable logic. Entitlements are derived from verified transactions and cached on
/// device so an unattended frame keeps its paid features offline indefinitely (FR-1100-10).
enum PurchaseKitInfo {
    static let specNumber = 1100
}
