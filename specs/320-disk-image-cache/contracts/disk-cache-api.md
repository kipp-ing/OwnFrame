# Contract — SlideshowKit Disk Cache API (320)

Additive only; no existing signature changes. `nil` defaults keep every current call site and
test source-compatible.

## New protocol: `DiskImageStoring`

```swift
public protocol DiskImageStoring: Sendable {
    /// Bytes for the key, or nil on miss. A hit refreshes the entry's recency.
    /// Corrupt/unreadable entries are removed and reported as a miss.
    func data(forKey key: String) async -> Data?

    /// Persist bytes under the key, then prune to the budget. Failures are
    /// swallowed (playback must never notice). An entry larger than the whole
    /// budget is not persisted.
    func store(_ data: Data, forKey key: String) async

    /// Change the budget; prunes immediately when lowered.
    func setBudget(_ bytes: Int64) async

    /// Remove every entry.
    func clear() async

    /// Tracked byte total of all entries (Settings usage label).
    func currentUsage() async -> Int64
}

/// Production implementation: byte-capped LRU over one-file-per-entry in `root`.
public actor DiskImageCache: DiskImageStoring {
    public init(root: URL, budget: Int64, now: @escaping @Sendable () -> Date = Date.init)
}
```

Contract guarantees (asserted by `DiskImageCacheTests`, real files in a temp dir):

- After any `store`/`setBudget`/`clear` completes: `currentUsage() ≤ budget`, and usage equals
  the byte sum of present files (FR-320-03, SC-320-03).
- Filling past the budget evicts strictly in least-recently-stamped order; a read re-stamps
  (injected `now` makes order deterministic).
- Round-trip: `store` then `data(forKey:)` returns identical bytes; distinct quality variants
  are distinct keys (`assetID#preview` / `assetID#original`).
- Corrupt file ⇒ `data` returns nil and the file is gone afterwards (FR-320-09).
- `clear()` ⇒ usage 0, directory empty (FR-320-05).

## New protocol: `SourceSnapshotStoring`

```swift
public protocol SourceSnapshotStoring: Sendable {
    func save(_ assets: [Asset], forKey key: String)   // replaces previous snapshot
    func load(forKey key: String) -> [Asset]?          // nil: missing or undecodable
    func clear()                                       // removes all snapshots
}

public final class FileSourceSnapshotStore: SourceSnapshotStoring {
    public init(root: URL)   // prod root is created backup-excluded
}
```

Guarantees (`SourceSnapshotStoreTests`): round-trip equality, replace-on-save, per-key
isolation, corrupt file ⇒ nil, `clear()` empties the root. Content is `[Asset]` (id + type) —
no other fields exist to leak (FR-320-06/10).

## New type: `CacheBudget` + `CacheBudgetStore`

```swift
public struct CacheBudget: Sendable, Equatable {
    public var bytes: Int64
    public static let steps: [CacheBudget]   // 100 MB, 250 MB, 500 MB, 1 GB, 2 GB
    public static let `default`: CacheBudget // 500 MB
}

public protocol CacheBudgetStore: Sendable {
    func load() -> CacheBudget
    func save(_ budget: CacheBudget)
}

public final class UserDefaultsCacheBudgetStore: CacheBudgetStore {
    public init(defaults: UserDefaults = .standard)
}
```

## `SlideshowViewModel` — additive API surface

```swift
// init gains two optional seams (defaults keep all existing call sites compiling):
public init(..., clock: any SlideshowClock = ContinuousSlideshowClock(),
            retryPolicy: RetryPolicy = RetryPolicy(),
            diskCache: (any DiskImageStoring)? = nil,
            snapshots: (any SourceSnapshotStoring)? = nil,
            cache: ImageCache = ..., config: SlideshowConfig = .default, ...)
```

Behavioral contract (asserted by `SlideshowOfflineTests`):

| Trigger | Guarantee |
|---|---|
| Photo displayed/prefetched (network fetch) | bytes land on disk; budget respected (FR-320-01/03) |
| Photo available on disk | shown with zero network requests; RAM repopulated (FR-320-02, SC-320-05) |
| Offline mid-run, album played through once | full rotation continues from disk (US1, SC-320-01) |
| Launch with dead source + snapshot + stored photos | `.playing` from snapshot, retry armed, no user input (US2-1, SC-320-02) |
| Launch with dead source + snapshot, photos purged | `.failed` + retry, no crash (US2-4, SC-320-06) |
| Launch with dead source, no snapshot | 310 behavior verbatim (US2-3) |
| Retry/refresh succeeds after snapshot start | live list merges via 310 reconciliation; snapshot replaced (US2-2) |
| `diskCache == nil && snapshots == nil` | byte-for-byte 310 behavior — existing suites prove it by staying green |

## Unchanged surfaces (compatibility guarantees)

- `ImageCache` (RAM tier), `SlideshowTicker`, `SlideshowClock`, `RetryPolicy`,
  `RotationReconciler`, `SlideshowPhase`, `ImmichAPI`: untouched.
- App-facing: Settings gains one new `Section`; existing accessibility IDs stable; new IDs
  `settings.storage.usage` / `settings.storage.budget` / `settings.storage.clear`.
