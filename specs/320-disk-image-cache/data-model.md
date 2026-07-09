# Data Model — 320 Disk Image Cache

Phase 1 output. All types live in `Packages/SlideshowKit/Sources/SlideshowKit/`. Persistence
is files in the app sandbox plus one UserDefaults integer — nothing leaves the device.

## DiskImageCache (new, `DiskImageCache.swift`)

`actor DiskImageCache: DiskImageStoring`. One file per entry; the filesystem is the index.

| State | Type | Meaning |
|---|---|---|
| `root` | `URL` (injected) | Directory holding the entry files (prod: `Library/Caches/ImageCache/`) |
| `budget` | `Int64` (bytes) | Current cap; mutable via `setBudget` (FR-320-03/04) |
| `now` | `() -> Date` (injected) | Recency stamp source — deterministic in tests |
| `usage` | `Int64` | Incrementally tracked byte total, seeded by one lazy directory scan |

Operations and rules (each is at least one test):

- `data(forKey:)` — read the entry file; hit ⇒ re-stamp recency with `now()`, return bytes.
  Unreadable/corrupt ⇒ delete the file, adjust usage, return nil (miss — FR-320-09).
- `store(_:forKey:)` — write bytes (atomic write), stamp recency, add to usage, then prune.
  Write failure ⇒ swallow silently, usage unchanged (FR-320-09). Entry larger than the whole
  budget ⇒ not persisted (edge case: cap smaller than one photo).
- `prune()` — while `usage > budget`: delete the least-recently-stamped entry first
  (FR-320-03). Runs after every store and inside `setBudget` (FR-320-04).
- `clear()` — delete all entries; usage 0 (FR-320-05).
- `currentUsage()` — the tracked total (Settings label).
- Key mapping: cache key `assetID#quality` → filename with `#` → `_` (asset IDs are UUIDs).
- Invariant: after any `store`/`setBudget`/`clear` completes, `usage ≤ budget` (SC-320-03) and
  `usage` equals the byte sum of files present.

## SourceSnapshot (new, `SourceSnapshotStore.swift`)

`SourceSnapshotStoring` protocol; file-backed implementation, one JSON per source key under an
injected, backup-excluded root (prod: `Application Support/SourceSnapshots/`).

| Operation | Rule |
|---|---|
| `save(_ assets: [Asset], forKey: String)` | Replaces the key's previous snapshot (FR-320-06); content is the `Codable` `Asset` array (id + type only — non-secret by construction, FR-320-10) |
| `load(forKey:) -> [Asset]?` | nil when missing or undecodable (corrupt ⇒ nil, never a crash) |
| `clear()` | Removes all snapshots (part of Clear cache, FR-320-05) |

Key = the engine's `albumID` (shared links resolve to an album ID upstream — the same
identity 310 rebinds on). Written from `markRefreshSucceeded()` — exactly every successful
list fetch.

## CacheBudget (new, `CacheBudget.swift`)

| Member | Value |
|---|---|
| `bytes` | `Int64` |
| `steps` | 100 MB, 250 MB, 500 MB, 1 GB, 2 GB (fixed picker options, FR-320-04) |
| `.default` | 500 MB |

`CacheBudgetStore` protocol + `UserDefaultsCacheBudgetStore` (one integer key, non-secret).
Settings picker writes the store AND calls `diskCache.setBudget(_:)` so pruning is immediate.

## SlideshowViewModel — new/changed behavior (existing type)

| Change | Rule |
|---|---|
| `diskCache: (any DiskImageStoring)?` init param, default nil | nil ⇒ exact 310 behavior (all existing tests unchanged) |
| `snapshots: (any SourceSnapshotStoring)?` init param, default nil | same |
| `loadImageData(for:)` | RAM hit → return. Disk hit → repopulate RAM + return (no network call, FR-320-02, SC-320-05). Network fetch → RAM store + fire-and-forget disk store (FR-320-01/11) |
| `prefetchImages()` | same tier order; fetched bytes write through to disk (FR-320-01) |
| `markRefreshSucceeded()` | additionally `snapshots?.save(imageAssets, forKey: albumID)` (FR-320-06) |
| `start()` catch | if `snapshots?.load(forKey: albumID)` is non-nil and non-empty: adopt it as `imageAssets`, rebuild sequence, show from cursor via the disk tier, arm the sourceReload retry, keep `failureReason` set (FR-320-07); photos all missing ⇒ existing exhaustion path (`.failed` + retry, SC-320-06). No snapshot ⇒ 310 behavior verbatim |

State transitions (offline startup fallback):

```
start() fetch fails
├─ snapshot exists, ≥1 stored photo loads → .playing (stale) + retry armed  (US2-1)
├─ snapshot exists, no photo loads        → .failed + retry armed           (US2-4, SC-320-06)
└─ no snapshot                            → .failed + retry armed           (310 US1-2, unchanged)
retry/refresh succeeds later → markRefreshSucceeded (snapshot replaced) +
                               reconcile branch merges live list             (US2-2)
```

## Settings "Storage" section (app target, no new model)

Reads `currentUsage()` on appear and after Clear; binds the budget picker to
`CacheBudgetStore`; Clear = confirmation dialog → `diskCache.clear()` + `snapshots.clear()` →
refresh usage label. Accessibility identifiers: `settings.storage.usage`,
`settings.storage.budget`, `settings.storage.clear` (for the UITest).
