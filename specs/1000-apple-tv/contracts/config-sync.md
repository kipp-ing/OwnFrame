# Contract: Config Sync (ConfigSyncKit) — FR-1000-05/06/11/12, SC-1000-08

## ConfigSyncStore (non-secret, iCloud KVS)

```
protocol ConfigSyncStore: Sendable {            // @MainActor where the impl needs it
    func load() -> SyncedConfig?                 // nil when nothing synced / iCloud absent
    func save(_ config: SyncedConfig)            // last-writer-wins per key; best-effort
    var externalChanges: AsyncStream<SyncedConfig> { get }  // KVS server-change notifications
}
```
- Real: `UbiquitousKVSConfigSyncStore` over `NSUbiquitousKeyValueStore` (one key per `SyncedConfig`
  field; `.synchronize()` best-effort; observes `didChangeExternallyNotification`).
- Fake: `InMemoryConfigSyncStore` (dictionary; emits on `externalChanges`).
- **Invariant (SC-1000-08):** `save` MUST reject/never write any secret field — unit-asserted by
  serializing a config and scanning the KVS backing dict for known secret markers.

## SecretSyncStore (secret, CloudKit encrypted fields)

```
protocol SecretSyncStore: Sendable {
    func publish(_ secret: SyncedSecret) async throws          // iPad → encryptedValues
    func fetch() async throws -> SyncedSecret?                  // tvOS: nil if unavailable
}
enum SecretSyncError: Error { case iCloudUnavailable, notFound, transport(Error) }
```
- Real: `CloudKitSecretSyncStore` — private DB, record `FrameSecrets`, every value via
  `record.encryptedValues[...]`; no custom crypto. `fetch` maps account/unavailable errors to
  `iCloudUnavailable` and the consumer degrades silently to manual entry.
- Fake: `InMemorySecretSyncStore` (holds one `SyncedSecret?`; can be primed to throw
  `iCloudUnavailable`).

## ConfigPublisher (iPad companion) / ConfigConsumer (tvOS)

- `ConfigPublisher.publishNonSecret(from: stores…)` gathers the six UserDefaults stores → one
  `SyncedConfig` → `ConfigSyncStore.save`. `publishSecrets(from: keychainSeams…)` → `SyncedSecret`
  → `SecretSyncStore.publish`. Idempotent; called on config change.
- `ConfigConsumer.prefill() -> SyncedConfig?` = `ConfigSyncStore.load` (drives onboarding
  prefill). `ConfigConsumer.hydrateSecrets(into: keychainSeams…)` = `SecretSyncStore.fetch`, then
  write each secret into the local keychain; return `.hydrated` / `.manualRequired` (never throws
  to the UI). Manual path always available (US2-3/4).

## Acceptance (host, fakes) — US2 scenarios

1. synced non-secret present ⇒ `prefill()` returns it (onboarding prefilled).
2. secret present in fake CK ⇒ `hydrateSecrets` writes to fake keychain, returns `.hydrated`,
   nothing typed.
3. fake CK primed `iCloudUnavailable` ⇒ `.manualRequired`, no throw, KVS config still usable.
4. empty fakes ⇒ manual path completes; KVS never contains a secret (SC-1000-08).
