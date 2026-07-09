# Feature Specification: Disk Image Cache (Offline Photo Survival)

**Feature Branch**: `320-disk-image-cache`

**Created**: 2026-07-09

**Status**: Implemented (2026-07-09) — disk tier, source snapshots, offline startup fallback, and
the Settings Storage section are built and gated (host suites + sim + `SettingsStorageUITests`).
Traceability in `docs/spec-traceability.md`.

**Input**: Sub-spec of `specs/300-slideshow`. Promotes the disk image cache from topic 300's
Roadmap (was FR-300-08 + the Clear-cache part of FR-300-27) into buildable requirements. A
photo frame must keep showing photos when the network breaks — today the show survives an
outage on a handful of RAM-cached photos (topic 310 keeps it alive and self-healing), but the
*whole album* goes dark the moment the app relaunches offline. This spec adds the missing
layer: photos persist on disk (byte-capped, least-recently-used eviction, max size
configurable in Settings, default 500 MB) and the active source's last known photo list is
remembered, so an offline frame — even after a relaunch — plays everything it has ever shown.
310's auto-retry/refresh machinery remains the recovery path back to live data. Out of scope:
proactively downloading albums that have not played yet (passive fill via playback/prefetch
only, see Assumptions); caching for the album browser's thumbnails or photo-info details
(both fetch on demand); encrypting cached bytes (the app sandbox is the boundary).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The whole album keeps playing when the network breaks (Priority: P1)

The frame has been running for a while — every photo it has shown or prefetched is kept on
disk. The Wi-Fi drops. The slideshow keeps rotating through the *entire* cached album, not
just the last few photos held in memory, until the connection returns.

**Why this priority**: This is the gap the user actually feels. 310 guarantees the frame
never goes dark and heals itself, but an evening-long outage today means the same ~5 photos
loop on the wall. With the album on disk, an outage becomes invisible.

**Independent Test**: With a fake photo source and a real cache directory in a temp folder:
play through an album once, cut the fake network, keep advancing — every photo of the album
still appears, in rotation order, with zero network requests.

**Acceptance Scenarios**:

1. **Given** the album has played through at least once, **When** the network becomes
   unavailable and the slideshow keeps advancing, **Then** every photo of the album continues
   to appear from local storage, honoring the active order (sequential/shuffle).
2. **Given** a photo is available locally, **When** it is displayed, **Then** no network
   request is made for it and there is no visible loading delay.
3. **Given** some photos of the album never played (and are therefore not stored), **When**
   the network is unavailable, **Then** those photos are skipped (existing skip-walk) and the
   cached ones keep rotating — no error surface while something can be shown.
4. **Given** the network returns, **Then** 310's retry/refresh resumes live fetching and the
   skipped photos re-enter rotation without a restart.

---

### User Story 2 - The frame survives an offline relaunch (Priority: P1)

The power blips at 3 a.m. — or iOS quietly kills the app overnight — and the network is also
down (router still rebooting). The frame relaunches, remembers what the active album
contained, finds the photos on disk, and resumes the slideshow. Nobody notices anything.

**Why this priority**: An appliance must survive the compound failure. Relaunch-while-offline
is exactly what happens after a power cut, and today it strands on the calm error state until
the network returns.

**Independent Test**: Play an album, persist state, tear the engine down, recreate it with
the source fetch failing (network dead): playback starts from the remembered list + stored
photos without user input; when the fake source recovers, the live list takes over via 310's
reconciliation.

**Acceptance Scenarios**:

1. **Given** the active source has played before (a remembered photo list and stored photos
   exist), **When** the app launches and the source fetch fails, **Then** the slideshow
   starts from the remembered list and plays the locally stored photos — no error screen, no
   user input.
2. **Given** the slideshow is playing from remembered offline data, **When** 310's background
   retry reaches the server again, **Then** the live photo list replaces the remembered one
   seamlessly (310's reconciliation rules: current photo undisturbed, additions/removals
   applied).
3. **Given** no remembered list exists for the active source (first run, or after Clear
   cache), **When** the app launches offline, **Then** the existing 310 behavior applies:
   calm error state with auto-retry behind it.
4. **Given** a remembered list exists but the stored photos were removed (system reclaimed
   storage), **When** the app launches offline, **Then** the calm error state appears with
   auto-retry behind it — never a crash or a blank loop.
5. **Given** the remembered list is for source A, **When** the user switched the active
   source to B and the frame relaunches offline, **Then** B has its own remembered list if it
   played before; otherwise the calm error state applies.

---

### User Story 3 - Storage stays under the user's control (Priority: P1)

In Settings, the user sees how much space cached photos occupy, can pick a maximum size
(default 500 MB), and can clear the cache entirely. The frame respects the budget on its own:
oldest-unused photos make room for new ones.

**Why this priority**: Explicitly requested scope. A cache that silently grows is a support
problem; a visible budget with a one-tap Clear keeps trust — and it is the App Store-friendly
answer to "why is this app using 2 GB?".

**Independent Test**: Drive the store past the configured budget with generated images and
verify usage never exceeds it and the least-recently-shown photos were evicted first; change
the budget down and verify immediate pruning; clear and verify zero usage while the on-screen
photo stays.

**Acceptance Scenarios**:

1. **Given** the Settings screen, **Then** a storage section shows the current cache usage in
   human-readable form and the configured maximum.
2. **Given** the cache is at its cap, **When** a new photo is stored, **Then** the
   least-recently-used photos are evicted until the new photo fits — usage never exceeds the
   cap after the store completes.
3. **Given** the user selects a smaller maximum, **Then** the cache prunes to the new cap
   immediately.
4. **Given** the user taps Clear cache, **Then** all stored photos and remembered lists are
   removed, usage shows zero, and the currently displayed photo is not interrupted.
5. **Given** the cache was cleared while online, **Then** subsequent photos come from the
   network and re-fill the cache as they play (no restart needed).
6. **Given** the maximum size options, **Then** the choices are fixed steps (100 MB, 250 MB,
   500 MB, 1 GB, 2 GB) with 500 MB as the default — no free-form entry.

---

### Edge Cases

- **Device storage full / write fails**: storing silently stops (no error surface, nothing
  logged beyond a debug note); playback is unaffected; storing resumes when writes succeed
  again.
- **Corrupt or unreadable stored photo**: treated as a miss — the entry is deleted and the
  photo is fetched from the network (or skipped while offline).
- **System reclaims cache storage** (iOS purges caches under pressure): tolerated — photos
  re-fetch when online; offline relaunch degrades to the calm error state (US2 scenario 4).
- **Cap smaller than a single photo** (e.g. original-quality photo > cap): the photo still
  displays (memory path); it simply is not persisted; no crash, usage stays under cap.
- **Quality switch (preview ↔ original)**: variants are stored under distinct keys and count
  toward the same budget; eviction may drop the unused variant first (it becomes least
  recently used naturally).
- **Clear cache while offline**: the on-screen photo stays (memory); subsequent advances find
  nothing and 310's machinery holds the current photo with background retries; recovery on
  reconnect.
- **Source switch**: stored photos are keyed by photo identity, not by source — a photo
  appearing in both an album and a shared link is stored once. Remembered lists are
  per-source.
- **Rapid cap changes / concurrent stores**: pruning and storing serialize safely; the last
  selected cap wins.
- **Time jumps** (clock changes): recency ordering for eviction may reorder — harmless;
  eviction order is a heuristic, not a correctness property.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-320-01**: Every photo the slideshow displays or prefetches MUST be persisted to an
  on-device store, per quality variant, subject to the size budget.
- **FR-320-02**: Photo loading MUST consult memory first, then the disk store, then the
  network; a disk hit repopulates the memory cache, refreshes the entry's recency, and makes
  no network request.
- **FR-320-03**: The disk store MUST enforce a configurable byte budget with
  least-recently-used eviction; after any store operation completes, usage is at or under the
  budget.
- **FR-320-04**: The budget MUST default to 500 MB and be user-selectable in Settings from
  fixed steps (100 MB, 250 MB, 500 MB, 1 GB, 2 GB); selecting a smaller budget prunes
  immediately.
- **FR-320-05**: Settings MUST display current usage (human-readable) and offer a Clear
  action that removes all stored photos AND remembered lists without interrupting the
  currently displayed photo.
- **FR-320-06**: After every successful photo-list fetch, the active source's list MUST be
  remembered on device (photo identifiers and type only — never credentials, URLs with
  secrets, or passwords), replacing that source's previous remembered list.
- **FR-320-07**: When the photo-list fetch fails at launch (or on source switch) and a
  remembered list exists for the active source, playback MUST start from the remembered list
  and stored photos (stale-but-working) while 310's auto-retry recovers live data; a later
  successful fetch replaces the rotation via 310's reconciliation rules.
- **FR-320-08**: While the app is running offline, rotation MUST continue across all stored
  photos of the active source (not only memory-cached ones); photos with no stored copy are
  skipped (existing skip-walk) until the network returns.
- **FR-320-09**: Store failures MUST degrade gracefully: unreadable entries are misses (and
  are removed); write failures disable persisting silently without affecting playback.
- **FR-320-10**: Stored photos and remembered lists MUST live in app-private storage, never
  leave the device, be excluded from cloud backup, and contain no secrets; system-initiated
  purges MUST be tolerated (FR-320-09/US2-4 paths).
- **FR-320-11**: Disk work MUST never block or delay the visible slide transition — storing
  and pruning happen off the display path (SC-300-03 continues to hold).
- **FR-320-12**: The store's location, budget, and time source MUST be injectable so all
  cache behavior is unit-testable on the host against a temporary directory (constitution:
  testability; no simulator required for logic).

### Key Entities

- **Disk Image Store**: byte-capped, least-recently-used photo store; per-variant entries;
  usage accounting; prune/clear operations.
- **Cache Budget**: the user-selected maximum (default 500 MB) plus live usage — the pair
  shown in Settings.
- **Source Snapshot**: the remembered photo list of a source (identifiers + type only),
  replaced on every successful fetch, removed by Clear.
- **Offline Startup Fallback**: the launch decision — live fetch failed → remembered list +
  stored photos if available, else the 310 calm-error path.

### Roadmap / Deferred (not yet built)

- **Proactive album download** ("fill the cache now" instead of passive fill via playback) —
  only if users ask; passive fill matches the always-running frame use case.
- **Per-source usage breakdown** in Settings — single total suffices for v1.
- **Cache usage as an HA diagnostics attribute** (topic 710 family).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-320-01**: An album (within budget) that has played through once keeps rotating in full
  with the network cut — zero network requests, no visible change in slide cadence.
- **SC-320-02**: After playing through once, killing the network AND relaunching the app, the
  slideshow reaches playback without any user input and rotates the full album offline.
- **SC-320-03**: Usage never exceeds the configured budget after any store completes; filling
  past the budget evicts least-recently-shown photos first.
- **SC-320-04**: Clear cache brings usage to zero without interrupting the on-screen photo;
  lowering the budget prunes to the new value immediately.
- **SC-320-05**: A photo served from the store produces no network request and no visible
  loading state.
- **SC-320-06**: Offline relaunch with a remembered list but no stored photos (system purge)
  lands on the calm error state with auto-retry — no crash, no blank loop.

## Assumptions

- **Passive fill is enough**: a wall frame plays continuously, so every photo passes through
  the show (and its prefetch) within one cycle — after that, the album is offline-complete.
  Proactive downloading adds network/battery churn for little gain (Roadmap).
- **500 MB default ≈ 1,000–2,500 preview-quality photos** — comfortably a whole frame album;
  original-quality users can step up to 1–2 GB.
- **Fixed steps, no free-form entry** for the budget (ease-of-use goal: no keyboard for a
  number nobody should have to think about).
- **Photo identifiers are globally unique** for one Immich server, and this is a
  single-server product today — the store is keyed by photo identity, not source. Revisit if
  multi-server ever lands.
- **Only the active source's snapshot matters at launch**; saved-but-inactive sources get a
  snapshot when they play. Switching to a never-played source while offline shows the calm
  error state — acceptable.
- **Recency by wall clock is acceptable** for eviction ordering (unlike 310's backoff, no
  correctness depends on monotonicity; a clock jump merely reorders evictions).
- **310 is a prerequisite**: the retry/refresh/reconciliation machinery this spec leans on
  (FR-320-07/08, US1-4, US2-2) shipped with `310-slideshow-resilience`.
