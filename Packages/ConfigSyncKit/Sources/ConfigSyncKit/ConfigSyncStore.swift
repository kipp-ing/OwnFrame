import Foundation

/// Non-secret configuration sync (topic 1000, FR-1000-05/11, SC-1000-08).
///
/// The active `SyncedConfig` snapshot is stored one key per field in iCloud key-value storage.
/// Secrets never travel this channel — that is `SecretSyncStore`'s job (constitution III v1.1.0).
public protocol ConfigSyncStore: Sendable {
    /// The last synced snapshot, or `nil` when nothing has synced / iCloud is absent.
    func load() -> SyncedConfig?
    /// Persist the snapshot (last-writer-wins per key; best-effort).
    func save(_ config: SyncedConfig)
    /// KVS server-change notifications, projected into decoded snapshots.
    var externalChanges: AsyncStream<SyncedConfig> { get }
}

/// The primitive value kinds a `SyncedConfig` field maps to in key-value storage.
///
/// Deliberately narrow (string / int64 / data) so the KVS backing representation is inspectable
/// and provably secret-free (SC-1000-08).
public enum KVSValue: Sendable, Equatable {
    case string(String)
    case int64(Int64)
    case data(Data)
}

/// Maps `SyncedConfig` <-> a flat `[key: KVSValue]` dictionary, one entry per non-secret field.
///
/// Shared by the in-memory fake and the real `NSUbiquitousKeyValueStore` adapter so both agree on
/// the exact key layout that the SC-1000-08 invariant is asserted against.
enum SyncedConfigKVSCodec {
    static let schemaKey = "cfg.schema"
    static let baseURLKey = "cfg.baseURL"
    static let sourceLibraryKey = "cfg.sourceLibrary"
    static let themeKey = "cfg.theme"
    static let cacheBudgetBytesKey = "cfg.cacheBudgetBytes"
    static let haPublishKey = "cfg.haPublish"
    static let brokerHostKey = "cfg.brokerHost"
    static let brokerPortKey = "cfg.brokerPort"

    /// Every field key, for save-time removal of now-absent optionals.
    static let allKeys: [String] = [
        schemaKey, baseURLKey, sourceLibraryKey, themeKey,
        cacheBudgetBytesKey, haPublishKey, brokerHostKey, brokerPortKey,
    ]

    static func encode(_ config: SyncedConfig) -> [String: KVSValue] {
        var dict: [String: KVSValue] = [:]
        dict[schemaKey] = .int64(Int64(config.schema))
        if let baseURL = config.baseURL { dict[baseURLKey] = .string(baseURL.absoluteString) }
        if let sourceLibrary = config.sourceLibrary { dict[sourceLibraryKey] = .data(sourceLibrary) }
        if let theme = config.theme { dict[themeKey] = .data(theme) }
        if let cacheBudgetBytes = config.cacheBudgetBytes { dict[cacheBudgetBytesKey] = .int64(cacheBudgetBytes) }
        if let haPublish = config.haPublish { dict[haPublishKey] = .data(haPublish) }
        if let brokerHost = config.brokerHost { dict[brokerHostKey] = .string(brokerHost) }
        if let brokerPort = config.brokerPort { dict[brokerPortKey] = .int64(Int64(brokerPort)) }
        return dict
    }

    /// Returns `nil` when nothing is present (i.e. nothing synced yet).
    static func decode(_ dict: [String: KVSValue]) -> SyncedConfig? {
        guard !dict.isEmpty else { return nil }

        var config = SyncedConfig()
        if case let .int64(schema) = dict[schemaKey] { config.schema = Int(schema) }
        if case let .string(baseURL) = dict[baseURLKey] { config.baseURL = URL(string: baseURL) }
        if case let .data(sourceLibrary) = dict[sourceLibraryKey] { config.sourceLibrary = sourceLibrary }
        if case let .data(theme) = dict[themeKey] { config.theme = theme }
        if case let .int64(cacheBudgetBytes) = dict[cacheBudgetBytesKey] { config.cacheBudgetBytes = cacheBudgetBytes }
        if case let .data(haPublish) = dict[haPublishKey] { config.haPublish = haPublish }
        if case let .string(brokerHost) = dict[brokerHostKey] { config.brokerHost = brokerHost }
        if case let .int64(brokerPort) = dict[brokerPortKey] { config.brokerPort = Int(brokerPort) }
        return config
    }
}

/// Dictionary-backed `ConfigSyncStore` fake for host tests (no iCloud).
public final class InMemoryConfigSyncStore: ConfigSyncStore, @unchecked Sendable {
    private let lock = NSLock()
    private var backing: [String: KVSValue] = [:]
    private let continuation: AsyncStream<SyncedConfig>.Continuation

    public let externalChanges: AsyncStream<SyncedConfig>

    public init() {
        let (stream, continuation) = AsyncStream<SyncedConfig>.makeStream()
        self.externalChanges = stream
        self.continuation = continuation
    }

    public func load() -> SyncedConfig? {
        lock.lock()
        defer { lock.unlock() }
        return SyncedConfigKVSCodec.decode(backing)
    }

    public func save(_ config: SyncedConfig) {
        lock.lock()
        backing = SyncedConfigKVSCodec.encode(config)
        lock.unlock()
        continuation.yield(config)
    }

    /// Test hook: simulate a snapshot arriving from another device via KVS.
    public func simulateExternalChange(_ config: SyncedConfig) {
        lock.lock()
        backing = SyncedConfigKVSCodec.encode(config)
        lock.unlock()
        continuation.yield(config)
    }

    /// Test hook: inspect the raw KVS backing representation (for the SC-1000-08 invariant).
    public func backingStore() -> [String: KVSValue] {
        lock.lock()
        defer { lock.unlock() }
        return backing
    }
}
