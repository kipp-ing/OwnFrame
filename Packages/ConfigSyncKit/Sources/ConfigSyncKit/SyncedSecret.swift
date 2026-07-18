import Foundation

/// The secret payload synced iPad -> Apple TV over CloudKit encrypted fields only
/// (topic 1000, FR-1000-06/12, constitution III v1.1.0). Never travels the KVS channel.
///
/// Values are carried as primitives / opaque `Data`, keeping ConfigSyncKit decoupled from the
/// keychain packages that own them. No cryptography of our own — CloudKit encrypts at rest.
public struct SyncedSecret: Sendable, Equatable {
    /// The Immich `x-api-key` (keychain `de.kippings.ImmichSlideshow.apiKey` / `immich-api-key`).
    public var immichApiKey: String?
    /// MQTT broker credentials as an opaque JSON blob (keychain `mqttCredentials`).
    public var mqttCredentials: Data?
    /// Shared-link passwords keyed by `Source.id` (keychain `sharedLinkPassword`, per source).
    public var sharedLinkPasswords: [String: String]

    public init(
        immichApiKey: String? = nil,
        mqttCredentials: Data? = nil,
        sharedLinkPasswords: [String: String] = [:]
    ) {
        self.immichApiKey = immichApiKey
        self.mqttCredentials = mqttCredentials
        self.sharedLinkPasswords = sharedLinkPasswords
    }
}
