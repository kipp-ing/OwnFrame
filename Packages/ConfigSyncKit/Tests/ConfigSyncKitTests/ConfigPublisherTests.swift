import Foundation
import Testing
@testable import ConfigSyncKit

@Suite
struct ConfigPublisherTests {
    @Test
    func publishRoutesConfigAndSecretToSeparateStores() async {
        let configStore = InMemoryConfigSyncStore()
        let secretStore = InMemorySecretSyncStore()
        let publisher = ConfigPublisher(configStore: configStore, secretStore: secretStore)

        let config = SyncedConfig(
            baseURL: URL(string: "https://immich.example.com"),
            brokerHost: "broker.local",
            brokerPort: 8883
        )
        let secret = SyncedSecret(
            immichApiKey: "SUPER-SECRET-KEY",
            mqttCredentials: Data("mqtt-secret".utf8),
            sharedLinkPasswords: ["source-1": "hunter2"]
        )

        await publisher.publish(config: config, secret: secret)

        // Non-secret landed in the KVS fake.
        #expect(configStore.load() == config)
        // Secret landed in the CloudKit fake.
        #expect(secretStore.peekStored() == secret)
    }

    @Test
    func secretNeverLeaksIntoTheConfigChannel() async {
        let configStore = InMemoryConfigSyncStore()
        let secretStore = InMemorySecretSyncStore()
        let publisher = ConfigPublisher(configStore: configStore, secretStore: secretStore)

        let apiKey = "SUPER-SECRET-KEY"
        await publisher.publish(
            config: SyncedConfig(brokerHost: "broker.local"),
            secret: SyncedSecret(immichApiKey: apiKey)
        )

        // The secret string appears nowhere in the config fake's KVS representation.
        for value in configStore.backingStore().values {
            if case let .string(string) = value {
                #expect(!string.contains(apiKey))
            }
        }
    }

    @Test
    func cloudKitFailureDoesNotThrowAndConfigStillSaves() async {
        let configStore = InMemoryConfigSyncStore()
        let secretStore = InMemorySecretSyncStore()
        secretStore.primeFailure(.iCloudUnavailable)
        let publisher = ConfigPublisher(configStore: configStore, secretStore: secretStore)

        let config = SyncedConfig(brokerHost: "broker.local")

        // Best-effort: must not throw past the caller (publish is non-throwing).
        await publisher.publish(config: config, secret: SyncedSecret(immichApiKey: "k"))

        // Non-secret save still succeeded; the secret was not stored.
        #expect(configStore.load() == config)
        #expect(secretStore.peekStored() == nil)
    }
}
