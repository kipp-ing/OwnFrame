import Foundation
import Testing
@testable import ConfigSyncKit

@Suite
struct SecretSyncStoreTests {
    private func fullSecret() -> SyncedSecret {
        SyncedSecret(
            immichApiKey: "immich-api-key-value",
            mqttCredentials: Data("{\"user\":\"frame\",\"pass\":\"x\"}".utf8),
            sharedLinkPasswords: ["source-1": "hunter2", "source-2": "correct-horse"]
        )
    }

    @Test
    func fakePublishThenFetchRoundTrips() async throws {
        let store = InMemorySecretSyncStore()
        let secret = fullSecret()

        try await store.publish(secret)
        let fetched = try await store.fetch()

        #expect(fetched == secret)
    }

    @Test
    func fetchIsNilWhenNothingPublished() async throws {
        let store = InMemorySecretSyncStore()
        #expect(try await store.fetch() == nil)
    }

    @Test
    func primedUnavailableSurfacesOnFetch() async {
        let store = InMemorySecretSyncStore()
        store.primeFailure(.iCloudUnavailable)

        do {
            _ = try await store.fetch()
            Issue.record("expected fetch to throw .iCloudUnavailable")
        } catch let error as SecretSyncError {
            guard case .iCloudUnavailable = error else {
                Issue.record("expected .iCloudUnavailable, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test
    func primedUnavailableSurfacesOnPublish() async {
        let store = InMemorySecretSyncStore()
        store.primeFailure(.iCloudUnavailable)

        do {
            try await store.publish(fullSecret())
            Issue.record("expected publish to throw .iCloudUnavailable")
        } catch let error as SecretSyncError {
            guard case .iCloudUnavailable = error else {
                Issue.record("expected .iCloudUnavailable, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    // The secret payload carries only the three secret fields — nothing more.
    @Test
    func secretCarriesOnlyTheThreeSecretFields() {
        let secret = fullSecret()
        let labels = Set(Mirror(reflecting: secret).children.compactMap(\.label))
        #expect(labels == ["immichApiKey", "mqttCredentials", "sharedLinkPasswords"])
    }
}
