# Research — 320 Disk Image Cache

Phase 0 output. All decisions are internal architecture choices against existing code (310's
machinery is the base — branch off `310-slideshow-resilience`).

## R1 — Tier composition: who owns RAM → disk → network

**Decision**: `SlideshowViewModel.loadImageData(for:)` owns the ordering explicitly: RAM hit →
return; disk hit → repopulate RAM, refresh recency, return; network fetch → write-through to
RAM synchronously and to disk fire-and-forget. `prefetchImages()` gets the same treatment.
The disk tier is a new optional dependency (`diskCache: (any DiskImageStoring)? = nil`).

**Rationale**: The view model already owns the load path and 310's failure classification
sits exactly there (`lastLoadError`, skip-walk). The tiers have different natures — sync
locked class (RAM), async actor (file I/O), async network — so a composite "one cache
protocol" would flatten semantics that the engine needs to treat differently (a disk read
must not surface a loading state; a network fetch may). `nil` default keeps every existing
300/310 test green untouched.

**Alternatives considered**: a composite `TieredImageCache` wrapping all three — rejected
(hides the failure-classification seam 310 needs); making `ImageCache` itself disk-backed —
rejected (changes a proven type's semantics and its eviction unit from count to bytes).

## R2 — DiskImageCache mechanics

**Decision**: An `actor DiskImageCache: DiskImageStoring`. One file per entry under an
injected root directory; filename = the existing cache key (`assetID#quality`) with `#`
mapped to `_` (asset IDs are UUIDs — no other unsafe characters). Recency = file
`contentModificationDate`, stamped from an injected `now: () -> Date` on every store *and*
read. Usage = incrementally tracked byte total, seeded by one directory scan at first use
(async, off the display path). Prune = sort entries by stamp ascending, delete until
`usage ≤ budget`; runs after every store and on budget decrease. `clear()` deletes the
directory contents. Corrupt/unreadable file on read → treat as miss, delete the file
(FR-320-09). Write failure (disk full) → swallow, drop the incremental usage delta, keep
playing (FR-320-09).

**Rationale**: Index-free and crash-safe — the filesystem *is* the index (a killed app never
leaves the index out of sync with the files; iOS purging files self-heals on the next scan).
An actor serializes store/prune/clear races (spec edge case) idiomatically in Swift 6. The
injected `Date` source makes LRU order fully deterministic in tests (mtime granularity would
otherwise flake); wall-clock recency is fine per the spec's Assumptions (eviction ordering is
a heuristic — unlike 310's monotonic backoff).

**Alternatives considered**: a sidecar index file (SQLite/JSON) — rejected: a second source
of truth that desyncs on crash/purge for zero functional gain at this scale; `NSCache`-style
disk wrappers or a third-party cache library — rejected (no new dependencies; trivial needs);
LRU by access via `URLResourceValues.contentAccessDate` — rejected (APFS lazy atime is
unreliable; explicit stamping is deterministic).

## R3 — Source snapshot store

**Decision**: `SourceSnapshotStoring` protocol with `save(_ assets: [Asset], forKey:)`,
`load(forKey:) -> [Asset]?`, `clear()`. File-backed impl: one JSON file per key under an
injected root (prod: `Application Support/SourceSnapshots/`, created with
`isExcludedFromBackup = true`). Key = the view model's `albumID` (what the engine knows;
shared links resolve to an album ID upstream — same identity 310 uses for rebinding).
Snapshot content: the already-`Codable` `Asset` (id + type — nothing else exists on the type;
non-secret by construction). Hook: 310's `markRefreshSucceeded()` additionally saves the
snapshot (it is called on exactly every successful list fetch — start, refresh, retry).

**Rationale**: `markRefreshSucceeded` is the single choke point 310 built for "list fetch
succeeded" — the snapshot rides it with one line. `Asset: Codable` already, so the JSON is
free. Application Support (not Caches) because losing the *list* silently while keeping
gigabytes of images would waste the cache — the list is KB-sized and pins the offline
experience; backup exclusion because it is reconstructible device-local state.

**Alternatives considered**: UserDefaults — rejected (thousands of entries in a plist);
storing the snapshot inside the image cache dir — rejected (iOS purge would kill the map to
otherwise-surviving state, and Clear semantics differ); snapshotting *all* saved sources
proactively — rejected (spec Assumption: active-source-on-play is enough).

## R4 — Offline startup fallback placement

**Decision**: In `start()`'s catch (and only there): if a snapshot exists for `albumID`,
load it into `imageAssets`, rebuild the sequence, and run the normal show-from-cursor path —
photos come from the disk tier via the unchanged `loadFromCursor` walk. `failureReason` stays
set and the sourceReload retry is armed exactly as 310 does today (the snapshot path replaces
only the *dead-end*, not the recovery). If no photo loads (purged images), the existing
exhaustion path yields `.failed` + retry (SC-320-06). When a later fetch succeeds,
`markRefreshSucceeded` + the reconcile branch merge the live list — 310's machinery unchanged.

**Rationale**: Smallest possible diff on the hot path; every 310 acceptance scenario keeps
its meaning (the fallback only engages when a snapshot exists, which no existing test sets
up). Stale-beats-broken extends naturally from "keep the current image" to "keep the last
known album".

**Alternatives considered**: fallback in `reloadSource()` too — rejected: mid-session
failures already keep the in-memory list (310 FR-310-09); the snapshot only matters when
memory is empty, i.e. at start.

## R5 — Budget setting: store and UI

**Decision**: `CacheBudget` value type in SlideshowKit — raw byte count with the fixed step
list (100 MB, 250 MB, 500 MB, 1 GB, 2 GB) and `.default = 500 MB` — plus a
`CacheBudgetStore` protocol with a UserDefaults implementation (one integer key), mirroring
the `HAPublishOptions` pattern. The Settings "Storage" `Section` (in `SlideshowSettingsView`,
same Form as everything else) shows: usage label (`ByteCountFormatter`-style, refreshed on
appear and after Clear), a budget `Picker` over the steps, and a Clear button behind a
confirmation dialog. Budget changes call `diskCache.setBudget(_:)` (immediate prune,
FR-320-04); Clear calls `diskCache.clear()` + `snapshots.clear()`.

**Rationale**: Storage policy is not a display preference — it stays out of `ThemeSettings`
(which is synced 1:1 to HA entities in 710; a new field there would silently demand a new HA
entity). The HAPublishOptions precedent is exactly this shape. Confirmation on Clear because
it is the one destructive action in Settings.

**Alternatives considered**: extending `ThemeSettings` — rejected (above); free-form MB entry
— rejected by spec (fixed steps, ease-of-use); iCloud-synced setting — rejected (device-local
concern).

## R6 — App wiring

**Decision**: `Immich_SlideshowApp` creates one `DiskImageCache` (root:
`Library/Caches/ImageCache/`, budget from the store), one `FileSourceSnapshotStore`, and one
`UserDefaultsCacheBudgetStore` at startup, and passes them to `makeSlideshow` (new optional
view-model init params) and to `SlideshowSettingsView`. The UITest seam (`UITestSupport`)
passes temp-dir instances so the hermetic build exercises the same code paths.

**Rationale**: The view model is rebuilt on connection changes (full-rebuild path) — the
cache must outlive it, so the app owns the instance (same reasoning as `sourceStore`). One
shared actor instance also makes Settings' usage label and the engine's writes consistent.

**Alternatives considered**: per-view-model cache instances — rejected (usage/Clear in
Settings would act on a different instance than the engine writes to).
