import Testing
@testable import ConfigSyncKit

// Topic 1000 (FR-1000-12): `CKContainer.default()` aborts with an uncaught ObjC exception
// when the app binary lacks the iCloud/CloudKit container entitlement — the account token
// alone (`ubiquityIdentityToken`) is NOT a safe gate. The factory must therefore require
// BOTH the compiled-in entitlement capability AND a signed-in account before it ever
// instantiates the CloudKit store.

struct SecretSyncStoreFactoryTests {
    @Test func withoutEntitlementsNeverBuildsCloudKitEvenWithAnAccount() {
        let store = SecretSyncStoreFactory.make(entitlementsPresent: false, accountTokenPresent: true)
        #expect(store is InMemorySecretSyncStore)
    }

    @Test func withoutAnAccountNeverBuildsCloudKit() {
        let store = SecretSyncStoreFactory.make(entitlementsPresent: true, accountTokenPresent: false)
        #expect(store is InMemorySecretSyncStore)
    }

    /// The capability flag is compiled OFF until the iCloud/CloudKit entitlements actually
    /// land in the app targets (device gate). Flipping it is the deliberate, reviewed switch
    /// that turns real secret sync on — this test forces that review.
    @Test func cloudKitCapabilityIsCompiledOffUntilTheEntitlementsLand() {
        #expect(SecretSyncStoreFactory.cloudKitEntitlementsPresent == false)
    }
}
