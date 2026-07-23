/// Turns owned transactions into the tiers they grant. Pure, total, and host-testable.
public enum EntitlementResolver {

    /// Resolves the union of everything `transactions` grants (data-model.md §EntitlementResolver).
    ///
    /// The rules, all of them non-fatal by design:
    /// 1. A non-revoked owned product contributes `ProductCatalog.grants`.
    /// 2. A revoked transaction contributes nothing — evaluated *per transaction*, so a refund
    ///    only drops the entitlement when no other live transaction still grants it (FR-1100-12).
    /// 3. Tips contribute nothing (FR-1100-08).
    /// 4. Unknown product ids contribute nothing (forward compatibility with future SKUs).
    /// 5. No transactions resolve to the empty set.
    public static func resolve(_ transactions: [OwnedTransaction]) -> EntitlementSet {
        transactions.reduce(into: EntitlementSet.none) { resolved, transaction in
            guard !transaction.isRevoked,
                  let product = ProductID(rawValue: transaction.productID)
            else { return }
            resolved.formUnion(ProductCatalog.grants(product))
        }
    }
}
