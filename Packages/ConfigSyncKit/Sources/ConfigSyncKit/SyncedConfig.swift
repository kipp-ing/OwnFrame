import Foundation

/// Non-secret configuration snapshot synced iPad <-> Apple TV (topic 1000, FR-1000-11).
///
/// Secret-free by construction: the Immich API key and MQTT credentials live only in the
/// keychain / CloudKit encrypted fields (`SecretSyncStore`), never here. Sub-configurations
/// owned by other packages (the photo source, theme, HA publish options) are carried as
/// opaque, already-encoded JSON `Data` blobs rather than typed models — so ConfigSyncKit stays
/// decoupled from every other local package and cannot accidentally embed a secret field.
public struct SyncedConfig: Codable, Sendable, Equatable {
    /// Schema version stamped for forward tolerance (defaults to `ConfigSyncSchema.current`).
    public var schema: Int
    /// The Immich server base URL (non-secret; the API key is keychain-only).
    public var baseURL: URL?
    /// Opaque JSON owned by PhotoSourceKit: which source is active and its config.
    public var sourceLibrary: Data?
    /// Opaque JSON owned by ThemeKit: transition, duration, Ken Burns, clock overlay, ...
    public var theme: Data?
    /// Disk image-cache budget in bytes.
    public var cacheBudgetBytes: Int64?
    /// Opaque JSON owned by HAControlKit: publish options (no credentials).
    public var haPublish: Data?
    /// MQTT broker host (non-secret; username/password are keychain-only).
    public var brokerHost: String?
    /// MQTT broker port.
    public var brokerPort: Int?

    public init(
        schema: Int = ConfigSyncSchema.current,
        baseURL: URL? = nil,
        sourceLibrary: Data? = nil,
        theme: Data? = nil,
        cacheBudgetBytes: Int64? = nil,
        haPublish: Data? = nil,
        brokerHost: String? = nil,
        brokerPort: Int? = nil
    ) {
        self.schema = schema
        self.baseURL = baseURL
        self.sourceLibrary = sourceLibrary
        self.theme = theme
        self.cacheBudgetBytes = cacheBudgetBytes
        self.haPublish = haPublish
        self.brokerHost = brokerHost
        self.brokerPort = brokerPort
    }
}
