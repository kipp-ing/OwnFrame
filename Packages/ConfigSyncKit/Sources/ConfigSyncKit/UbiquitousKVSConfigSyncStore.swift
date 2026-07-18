import Foundation

/// Real `ConfigSyncStore` over `NSUbiquitousKeyValueStore` — one KVS key per `SyncedConfig` field.
///
/// Thin adapter, correct by construction: tests exercise `InMemoryConfigSyncStore`. Save is
/// best-effort (`synchronize()`); external server changes are observed via
/// `didChangeExternallyNotification` and projected onto `externalChanges`.
public final class UbiquitousKVSConfigSyncStore: ConfigSyncStore, @unchecked Sendable {
    private let store: NSUbiquitousKeyValueStore
    private let continuation: AsyncStream<SyncedConfig>.Continuation
    private var observer: NSObjectProtocol?

    public let externalChanges: AsyncStream<SyncedConfig>

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        let (stream, continuation) = AsyncStream<SyncedConfig>.makeStream()
        self.externalChanges = stream
        self.continuation = continuation

        self.observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: nil
        ) { [weak self] _ in
            guard let self, let config = self.load() else { return }
            self.continuation.yield(config)
        }
        store.synchronize()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        continuation.finish()
    }

    public func load() -> SyncedConfig? {
        var dict: [String: KVSValue] = [:]
        for key in SyncedConfigKVSCodec.allKeys {
            guard let object = store.object(forKey: key) else { continue }
            if let data = object as? Data {
                dict[key] = .data(data)
            } else if let number = object as? NSNumber {
                dict[key] = .int64(number.int64Value)
            } else if let string = object as? String {
                dict[key] = .string(string)
            }
        }
        return SyncedConfigKVSCodec.decode(dict)
    }

    public func save(_ config: SyncedConfig) {
        let encoded = SyncedConfigKVSCodec.encode(config)
        for key in SyncedConfigKVSCodec.allKeys {
            switch encoded[key] {
            case .string(let value)?:
                store.set(value, forKey: key)
            case .int64(let value)?:
                store.set(value, forKey: key)
            case .data(let value)?:
                store.set(value, forKey: key)
            case nil:
                store.removeObject(forKey: key)
            }
        }
        store.synchronize()
    }
}
