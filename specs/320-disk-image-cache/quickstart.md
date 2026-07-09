# Quickstart — Validating 320 Disk Image Cache

Contracts: [contracts/disk-cache-api.md](./contracts/disk-cache-api.md); entity rules:
[data-model.md](./data-model.md).

## Prerequisites

- Branch `320-disk-image-cache`, based on `310-slideshow-resilience` (hard dependency: the
  offline fallback leans on 310's retry/refresh/reconciler).
- No server, no network: host scenarios run `StubImmichAPI` + `TestClock` + **real**
  `DiskImageCache`/`FileSourceSnapshotStore` in per-test temp directories with an injected
  `now: () -> Date`.
- Simulator gates via XcodeBuildMCP (memory `sim-build-destination`; whole test classes only).

## Host gate (primary)

```bash
cd Packages/SlideshowKit && swift test
```

| Suite | Proves | Spec IDs |
|---|---|---|
| `DiskImageCacheTests` | round-trip, budget cap after every store, deterministic LRU eviction order, read re-stamps recency, corrupt→miss+delete, entry>budget skipped, prune on budget cut, clear, usage accounting, key sanitization | FR-320-03/04/09, SC-320-03/04 |
| `SourceSnapshotStoreTests` | round-trip, replace-on-save, per-source isolation, corrupt→nil, clear | FR-320-06/10 |
| `SlideshowOfflineTests` | the scenario table below | US1/US2, FR-320-01/02/07/08 |
| Existing 300/310 suites | unchanged and green with `diskCache/snapshots == nil` — the compatibility guarantee | contract |

### Engine scenarios → tests

1. **Write-through** — play two photos online: both present on disk afterwards; prefetched
   photo also present (FR-320-01).
2. **Disk hit, no network** — evict RAM (existing trick), keep disk: advance shows the photo
   with zero new `preview()` calls (FR-320-02, SC-320-05).
3. **Whole-album offline** — play through once, kill the fake network, advance a full cycle:
   every photo appears, zero network calls (US1, SC-320-01).
4. **Offline relaunch** — play, tear down the VM, build a fresh VM (same temp stores) with the
   source fetch failing: `.playing` from the snapshot without user input; `assetsCallCount`
   confirms the fetch was attempted and failed (US2-1, SC-320-02).
5. **Recovery after snapshot start** — fake recovers, advance `TestClock` one backoff: live
   list merges (an asset added server-side enters rotation), snapshot replaced (US2-2).
6. **Purged photos** — snapshot present, cache directory emptied: fresh VM lands `.failed` +
   retry armed, no crash (US2-4, SC-320-06).
7. **No snapshot** — 310's dead-server-at-launch scenario byte-for-byte (US2-3).
8. **Clear semantics** — clear both stores mid-show: current photo stays; next advance
   re-fetches from network online (US3-4/5).

## Simulator gates (Claude-owned, after host green)

1. XcodeBuildMCP `test_sim` on the app scheme — includes new `SettingsStorageUITests`
   (storage section present, budget picker persists across relaunch, Clear resets the usage
   label after confirmation).
2. `SlideshowSettingsView` preview renders the Storage section (usage, picker, Clear).
3. Full XCUITest suite before merge (SwiftUI touched — repo rule).

## Manual smoke (optional, live server)

Let the frame play through an album once, enable Airplane Mode on the iPad, watch a full
rotation (all photos, no stalls). Then force-quit and relaunch while still offline — the show
must come back on its own. Disable Airplane Mode — additions/removals resume within one
refresh interval. Check Settings → Storage shows plausible usage; Clear returns it to zero.
