// ConfigSyncKit — config sync for the Apple TV port (topic 1000).
//
// Non-secret configuration syncs iPad <-> Apple TV over iCloud key-value storage
// (`ConfigSyncStore`); secrets sync only through CloudKit private-database encrypted
// fields (`SecretSyncStore`, constitution III v1.1.0). All logic sits behind protocols
// with in-memory fakes so it is host-unit-testable without iCloud (FR-1000-11).
//
// The concrete types are added by the 1000 task set (SyncedConfig, ConfigSyncStore,
// SecretSyncStore, ConfigPublisher, ConfigConsumer). This file is the module anchor.

/// Schema version stamped into every synced snapshot for forward tolerance.
public enum ConfigSyncSchema {
    public static let current = 1
}
