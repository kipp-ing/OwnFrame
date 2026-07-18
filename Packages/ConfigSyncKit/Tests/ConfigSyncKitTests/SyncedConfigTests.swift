import Foundation
import Testing
@testable import ConfigSyncKit

@Suite
struct SyncedConfigTests {
    @Test
    func roundTripPreservesAllFields() throws {
        let original = SyncedConfig(
            schema: 1,
            baseURL: URL(string: "https://immich.example.com"),
            sourceLibrary: Data("source".utf8),
            theme: Data("theme".utf8),
            cacheBudgetBytes: 512_000_000,
            haPublish: Data("ha".utf8),
            brokerHost: "broker.local",
            brokerPort: 8883
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncedConfig.self, from: encoded)

        #expect(decoded == original)
    }

    @Test
    func schemaDefaultsToCurrentAndPayloadsDefaultNil() {
        let config = SyncedConfig()
        #expect(config.schema == ConfigSyncSchema.current)
        #expect(config.baseURL == nil)
        #expect(config.sourceLibrary == nil)
        #expect(config.theme == nil)
        #expect(config.cacheBudgetBytes == nil)
        #expect(config.haPublish == nil)
        #expect(config.brokerHost == nil)
        #expect(config.brokerPort == nil)
    }

    @Test
    func equatableHolds() {
        #expect(SyncedConfig() == SyncedConfig())
        #expect(SyncedConfig(brokerHost: "a") != SyncedConfig(brokerHost: "b"))
    }

    @Test
    func decodingOmittedNewerFieldsSucceedsWithNils() throws {
        // A minimal snapshot from a leaner/older writer: only the schema is present.
        let json = Data(#"{"schema":1}"#.utf8)
        let decoded = try JSONDecoder().decode(SyncedConfig.self, from: json)

        #expect(decoded.schema == 1)
        #expect(decoded.baseURL == nil)
        #expect(decoded.sourceLibrary == nil)
        #expect(decoded.theme == nil)
        #expect(decoded.cacheBudgetBytes == nil)
        #expect(decoded.haPublish == nil)
        #expect(decoded.brokerHost == nil)
        #expect(decoded.brokerPort == nil)
    }
}
