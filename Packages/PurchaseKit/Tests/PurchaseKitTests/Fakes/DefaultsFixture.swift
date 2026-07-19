import Foundation

/// A unique, self-cleaning `UserDefaults` suite for one test.
///
/// PurchaseKit persists the entitlement snapshot into an *injected* suite (data-model.md
/// §EntitlementSnapshot); tests must never touch `UserDefaults.standard`.
final class DefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "purchasekit.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
