import Foundation

/// iPad companion (topic 1000, US2): pushes the current configuration to the paired Apple TV.
///
/// Non-secret config goes to iCloud KVS (`ConfigSyncStore`); the secret goes only to the CloudKit
/// encrypted channel (`SecretSyncStore`) — never through `configStore`. Publishing is
/// best-effort and idempotent: a CloudKit failure is swallowed so it can never fail the
/// non-secret save nor throw past the caller.
public struct ConfigPublisher: Sendable {
    private let configStore: any ConfigSyncStore
    private let secretStore: any SecretSyncStore

    public init(configStore: any ConfigSyncStore, secretStore: any SecretSyncStore) {
        self.configStore = configStore
        self.secretStore = secretStore
    }

    /// Save the non-secret snapshot to KVS, then best-effort publish the secret to CloudKit.
    public func publish(config: SyncedConfig, secret: SyncedSecret) async {
        // Non-secret first, so a secret-channel failure never blocks the config save.
        configStore.save(config)
        do {
            try await secretStore.publish(secret)
        } catch {
            // Best-effort: swallow. The non-secret save already succeeded; the tvOS consumer
            // degrades to manual secret entry (US2-3/4).
        }
    }
}
