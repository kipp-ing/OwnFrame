import Foundation
import Testing
@testable import ConfigSyncKit

@Suite
struct ConfigSyncStoreTests {
    private func fullyPopulatedConfig() -> SyncedConfig {
        SyncedConfig(
            schema: 1,
            baseURL: URL(string: "https://immich.example.com"),
            sourceLibrary: Data("non-secret source json".utf8),
            theme: Data("non-secret theme json".utf8),
            cacheBudgetBytes: 512_000_000,
            haPublish: Data("non-secret ha json".utf8),
            brokerHost: "broker.local",
            brokerPort: 8883
        )
    }

    @Test
    func roundTripThroughFakePreservesEveryField() {
        let store = InMemoryConfigSyncStore()
        let config = fullyPopulatedConfig()

        store.save(config)

        #expect(store.load() == config)
    }

    @Test
    func emptyFakeLoadsNil() {
        #expect(InMemoryConfigSyncStore().load() == nil)
    }

    @Test
    func externalChangeEmitsOnStream() async {
        let store = InMemoryConfigSyncStore()
        var iterator = store.externalChanges.makeAsyncIterator()
        let changed = SyncedConfig(brokerHost: "changed.local", brokerPort: 1883)

        store.simulateExternalChange(changed)

        let received = await iterator.next()
        #expect(received == changed)
    }

    // SC-1000-08: the serialized KVS representation must never carry secret material.
    @Test
    func kvsRepresentationCarriesNoSecretMaterial() {
        let store = InMemoryConfigSyncStore()
        let config = fullyPopulatedConfig()
        store.save(config)

        let backing = store.backingStore()

        // The KVS key set is exactly the known non-secret fields.
        let expectedKeys: Set<String> = [
            "cfg.schema", "cfg.baseURL", "cfg.sourceLibrary", "cfg.theme",
            "cfg.cacheBudgetBytes", "cfg.haPublish", "cfg.brokerHost", "cfg.brokerPort",
        ]
        #expect(Set(backing.keys) == expectedKeys)

        // No KVS key names a secret channel.
        let forbidden = ["apikey", "api_key", "password", "credential", "secret", "token"]
        for key in backing.keys {
            let lower = key.lowercased()
            for marker in forbidden {
                #expect(!lower.contains(marker))
            }
        }

        // Structural guard: SyncedConfig has no secret-bearing member.
        let labels = Mirror(reflecting: config).children.compactMap(\.label).map { $0.lowercased() }
        for marker in forbidden {
            #expect(!labels.contains(where: { $0.contains(marker) }))
        }
    }
}
