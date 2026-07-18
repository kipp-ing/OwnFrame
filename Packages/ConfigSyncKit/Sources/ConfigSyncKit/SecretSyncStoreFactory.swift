import Foundation

/// Single device-gated factory for the secret channel (FR-1000-12), shared by the iPad
/// publisher and the tvOS consumer.
///
/// `CKContainer.default()` raises an uncaught ObjC exception ("containerIdentifier can not
/// be nil") when the binary lacks the iCloud/CloudKit container entitlement — and
/// `ubiquityIdentityToken` only reflects the signed-in *account*, not the entitlement. The
/// entitlement cannot be introspected at runtime on iOS/tvOS, so it is declared here as a
/// compile-time capability flag that is flipped in the same change that adds the
/// entitlements to the app targets (device gate; asserted off by a unit test until then).
public enum SecretSyncStoreFactory {
    /// Whether the app targets carry the iCloud/CloudKit entitlements. OFF until they land.
    public static let cloudKitEntitlementsPresent = false

    /// The real CloudKit store only when the binary is entitled AND an iCloud account is
    /// signed in; otherwise an empty in-memory store, so publish degrades to a no-op and
    /// hydration to the manual path (US2-3/4) — never a crash.
    public static func make(
        entitlementsPresent: Bool = cloudKitEntitlementsPresent,
        accountTokenPresent: Bool = FileManager.default.ubiquityIdentityToken != nil
    ) -> any SecretSyncStore {
        if entitlementsPresent, accountTokenPresent {
            return CloudKitSecretSyncStore()
        }
        return InMemorySecretSyncStore()
    }
}
