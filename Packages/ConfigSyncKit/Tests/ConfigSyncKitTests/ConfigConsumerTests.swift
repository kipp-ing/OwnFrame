import Foundation
import Testing
@testable import ConfigSyncKit

/// Records every write, standing in for the tvOS keychain seams.
private final class FakeSecretWriter: SecretWriting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var apiKeys: [String] = []
    private(set) var mqttCredentials: [Data] = []
    private(set) var sharedLinkPasswords: [(password: String, sourceID: String)] = []

    var isEmpty: Bool {
        lock.withLock { apiKeys.isEmpty && mqttCredentials.isEmpty && sharedLinkPasswords.isEmpty }
    }

    func writeImmichApiKey(_ apiKey: String) async {
        lock.withLock { apiKeys.append(apiKey) }
    }

    func writeMqttCredentials(_ credentials: Data) async {
        lock.withLock { mqttCredentials.append(credentials) }
    }

    func writeSharedLinkPassword(_ password: String, forSourceID sourceID: String) async {
        lock.withLock { sharedLinkPasswords.append((password, sourceID)) }
    }
}

@Suite
struct ConfigConsumerTests {
    // US2-1: synced non-secret present ⇒ prefill returns it.
    @Test
    func prefillReturnsSyncedNonSecretConfig() {
        let configStore = InMemoryConfigSyncStore()
        let config = SyncedConfig(baseURL: URL(string: "https://immich.example.com"))
        configStore.save(config)
        let consumer = ConfigConsumer(configStore: configStore, secretStore: InMemorySecretSyncStore())

        #expect(consumer.prefill() == config)
    }

    // US2-2: secret present in fake CK ⇒ hydrate writes to fake keychain, returns .hydrated.
    @Test
    func hydrateWritesEverySecretAndReturnsHydrated() async {
        let secret = SyncedSecret(
            immichApiKey: "immich-key",
            mqttCredentials: Data("mqtt".utf8),
            sharedLinkPasswords: ["source-1": "pw-1"]
        )
        let consumer = ConfigConsumer(
            configStore: InMemoryConfigSyncStore(),
            secretStore: InMemorySecretSyncStore(stored: secret)
        )
        let writer = FakeSecretWriter()

        let result = await consumer.hydrateSecrets(into: writer)

        #expect(result == .hydrated)
        #expect(writer.apiKeys == ["immich-key"])
        #expect(writer.mqttCredentials == [Data("mqtt".utf8)])
        #expect(writer.sharedLinkPasswords.count == 1)
        #expect(writer.sharedLinkPasswords.first?.password == "pw-1")
        #expect(writer.sharedLinkPasswords.first?.sourceID == "source-1")
    }

    // US2-3: fake CK primed .iCloudUnavailable ⇒ .manualRequired, no throw, KVS config still usable.
    @Test
    func iCloudUnavailableDegradesToManualButKeepsPrefill() async {
        let configStore = InMemoryConfigSyncStore()
        let config = SyncedConfig(brokerHost: "broker.local")
        configStore.save(config)
        let secretStore = InMemorySecretSyncStore()
        secretStore.primeFailure(.iCloudUnavailable)
        let consumer = ConfigConsumer(configStore: configStore, secretStore: secretStore)
        let writer = FakeSecretWriter()

        let result = await consumer.hydrateSecrets(into: writer)

        #expect(result == .manualRequired)
        #expect(writer.isEmpty)
        #expect(consumer.prefill() == config)
    }

    // US2-4: empty fakes ⇒ prefill nil, hydrate .manualRequired; config fake never held a secret.
    @Test
    func emptyFakesRequireManualAndConfigNeverHeldSecret() async {
        let configStore = InMemoryConfigSyncStore()
        let consumer = ConfigConsumer(configStore: configStore, secretStore: InMemorySecretSyncStore())
        let writer = FakeSecretWriter()

        #expect(consumer.prefill() == nil)

        let result = await consumer.hydrateSecrets(into: writer)

        #expect(result == .manualRequired)
        #expect(writer.isEmpty)
        #expect(configStore.backingStore().isEmpty)
    }
}
