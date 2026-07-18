import Foundation

/// Seam for writing fetched secrets into the local keychain, kept in ConfigSyncKit so the module
/// stays decoupled from the concrete keychain packages. The tvOS app implements this over its
/// three keychain stores; tests use a fake.
public protocol SecretWriting: Sendable {
    func writeImmichApiKey(_ apiKey: String) async
    func writeMqttCredentials(_ credentials: Data) async
    func writeSharedLinkPassword(_ password: String, forSourceID sourceID: String) async
}

/// tvOS consumer (topic 1000, US2): prefills onboarding from the synced config and hydrates
/// secrets from CloudKit into the local keychain.
public struct ConfigConsumer: Sendable {
    private let configStore: any ConfigSyncStore
    private let secretStore: any SecretSyncStore

    public init(configStore: any ConfigSyncStore, secretStore: any SecretSyncStore) {
        self.configStore = configStore
        self.secretStore = secretStore
    }

    /// Outcome of a hydration attempt.
    public enum HydrationResult: Sendable, Equatable {
        case hydrated
        case manualRequired
    }

    /// The synced non-secret snapshot to prefill onboarding, or `nil` if nothing synced.
    public func prefill() -> SyncedConfig? {
        configStore.load()
    }

    /// Fetch the secret from CloudKit and write each present value into `writer`.
    ///
    /// Silent degrade (US2-3/4): on `nil` / `.iCloudUnavailable` / any throw, returns
    /// `.manualRequired`. Never throws to the caller — the manual entry path is always available.
    public func hydrateSecrets(into writer: any SecretWriting) async -> HydrationResult {
        guard let secret = (try? await secretStore.fetch()).flatMap({ $0 }) else {
            return .manualRequired
        }

        if let apiKey = secret.immichApiKey {
            await writer.writeImmichApiKey(apiKey)
        }
        if let mqttCredentials = secret.mqttCredentials {
            await writer.writeMqttCredentials(mqttCredentials)
        }
        for (sourceID, password) in secret.sharedLinkPasswords {
            await writer.writeSharedLinkPassword(password, forSourceID: sourceID)
        }
        return .hydrated
    }
}
