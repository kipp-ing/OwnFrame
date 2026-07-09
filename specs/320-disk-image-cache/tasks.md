# Tasks: Disk Image Cache (Offline Photo Survival)

**Input**: Design documents from `/specs/320-disk-image-cache/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/disk-cache-api.md,
quickstart.md. **310 must be on the base branch** — the offline fallback rides its
retry/refresh/reconciler and `markRefreshSucceeded` hook.

**Tests**: MANDATORY — constitution principle I (Test-First, NON-NEGOTIABLE). Red before
green for every pair; "red" includes does-not-compile against the not-yet-added API.

**Delegation**: none — Codex is disabled per Jan (2026-07-09). Everything is inline; the
timer-free file-store logic would otherwise have been the delegable slice.

**Organization**: US1 (whole-album offline) is the MVP and the user's felt need; US2
(relaunch survival) completes the appliance story; US3 (Settings budget/Clear) is the
explicitly requested control surface.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 / US2 / US3 from spec.md
- All package paths relative to repo root

## Path Conventions

- Engine: `Packages/SlideshowKit/Sources/SlideshowKit/`
- Host tests: `Packages/SlideshowKit/Tests/SlideshowKitTests/` (Swift Testing, `swift test`)
- App target: `Immich Slideshow/` + `Immich SlideshowUITests/` (XcodeBuildMCP only)

---

## Phase 1: Setup

- [x] T001 Create branch `320-disk-image-cache` off `310-slideshow-resilience` (or off `main`
      once 310 is merged); confirm `.specify/feature.json` points at
      `specs/320-disk-image-cache` and `cd Packages/SlideshowKit && swift test` is green
      before writing anything

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the two file-backed stores and the budget type — pure, engine-independent, each
with an exhaustive host suite against a temp directory.

- [x] T002 Red: `Packages/SlideshowKit/Tests/SlideshowKitTests/DiskImageCacheTests.swift` —
      per-test temp dir (add a small helper to
      `Packages/SlideshowKit/Tests/SlideshowKitTests/Fakes.swift`), injected `now` closure:
      store/read round-trip (distinct quality keys), usage ≤ budget after every store,
      deterministic LRU eviction order, read re-stamps recency (read-then-fill evicts the
      *other* entry), corrupt file → miss + file deleted, entry > budget not persisted,
      `setBudget` prunes immediately, `clear` → usage 0 + empty dir, usage accounting matches
      file byte sum, `#` → `_` key sanitization (FR-320-03/04/09, SC-320-03/04); plus
      `CacheBudget` steps/default and `UserDefaultsCacheBudgetStore` round-trip (FR-320-04)
- [x] T003 Green: `Packages/SlideshowKit/Sources/SlideshowKit/DiskImageCache.swift` —
      `DiskImageStoring` protocol + `actor DiskImageCache` per
      contracts/disk-cache-api.md and data-model.md (one file per entry, filesystem-as-index,
      lazy usage scan, atomic writes, swallow write failures) (depends on T002)
- [x] T004 [P] Red:
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SourceSnapshotStoreTests.swift` —
      round-trip equality, replace-on-save, per-key isolation, corrupt file → nil (never
      throws), `clear()` empties the root (FR-320-06/10)
- [x] T005 Green: `Packages/SlideshowKit/Sources/SlideshowKit/SourceSnapshotStore.swift` —
      `SourceSnapshotStoring` + `FileSourceSnapshotStore` (JSON per key, backup-excluded root
      creation) (depends on T004)
- [x] T006 Green: `Packages/SlideshowKit/Sources/SlideshowKit/CacheBudget.swift` —
      `CacheBudget` (bytes; steps 100 MB/250 MB/500 MB/1 GB/2 GB; default 500 MB) +
      `CacheBudgetStore` protocol + `UserDefaultsCacheBudgetStore` (red assertions landed in
      T002) (depends on T002)

**Checkpoint**: `swift test` green — stores proven standalone; engine work can begin.

---

## Phase 3: User Story 1 — Whole album keeps playing offline (Priority: P1) 🎯 MVP

**Goal**: every displayed/prefetched photo persists; loading consults RAM → disk → network;
an outage mid-run rotates the entire cached album, not the ~5 RAM entries.

**Independent Test**: quickstart scenarios 1–3 — play through once against the fake, cut it,
advance a full cycle: every photo appears, zero network calls.

- [x] T007 [US1] Red: scenarios 1–3 in new
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowOfflineTests.swift`
      (TestClock + StubImmichAPI + real `DiskImageCache` in a temp dir) — (a) write-through:
      shown AND prefetched photos are on disk afterwards (FR-320-01); (b) disk hit: evict RAM
      (existing unrelated-keys trick), keep disk, advance → photo shown with zero new
      `preview()` calls and RAM repopulated (FR-320-02, SC-320-05); (c) whole-album offline:
      play through once, `setPreviewError` on everything, advance a full cycle → all photos
      appear from disk, zero network image calls (US1, SC-320-01). **Engine/concurrency test
      design — inline.**
- [x] T008 [US1] Green: two-tier loading in
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowViewModel.swift` — new
      `diskCache: (any DiskImageStoring)? = nil` init param; `loadImageData(for:)` RAM → disk
      (repopulate RAM) → network (write RAM sync + disk fire-and-forget, FR-320-11);
      `prefetchImages()` same tiering + write-through (depends on T003, T007)

**Checkpoint**: `swift test` green incl. all 310 suites untouched — the MVP outage story
works end to end on the host.

---

## Phase 4: User Story 2 — Offline relaunch survival (Priority: P1)

**Goal**: the active source's list is remembered on every successful fetch; a launch with a
dead source plays the remembered list from disk, and 310's machinery recovers live data.

**Independent Test**: quickstart scenarios 4–7 — tear the VM down, rebuild against the same
temp stores with the fetch failing: playback resumes; recovery merges; purge degrades calmly.

- [x] T009 [US2] Red: scenarios 4–7 in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowOfflineTests.swift` —
      (a) offline relaunch: play, discard the VM, fresh VM (same stores) + `setAssetsError` →
      `.playing` from snapshot, no user input, retry armed (US2-1, SC-320-02, FR-320-07);
      (b) recovery: fake returns with an added asset, advance one backoff → live list merges
      per 310 reconciliation, snapshot replaced (US2-2); (c) purged photos: empty the cache
      dir, fresh VM offline → `.failed` + retry, no crash (US2-4, SC-320-06); (d) no
      snapshot: dead-server launch behaves exactly like 310 (US2-3). **Inline.**
- [x] T010 [US2] Green: snapshot integration in
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowViewModel.swift` — new
      `snapshots: (any SourceSnapshotStoring)? = nil` init param; `markRefreshSucceeded()`
      saves `imageAssets` under `albumID` (FR-320-06); `start()` catch tries the snapshot
      before `handleFailure` per data-model's fallback state chart (FR-320-07) (depends on
      T005, T008, T009)

**Checkpoint**: the compound failure (power cut + dead router) survives on the host suite.

---

## Phase 5: User Story 3 — Storage under the user's control (Priority: P1)

**Goal**: Settings shows usage, offers the fixed-step budget (default 500 MB), and Clear;
budget cuts prune immediately; Clear never touches the on-screen photo.

**Independent Test**: quickstart scenario 8 + `SettingsStorageUITests` on the hermetic build.

- [x] T011 [US3] Red+Green (verification): scenario 8 in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowOfflineTests.swift` — clear
      both stores mid-show: current photo + phase untouched; next advance (online) re-fetches
      from network and re-fills the cache (US3-4/5, FR-320-05); no engine change expected —
      fix whatever red reveals
- [x] T012 [US3] Storage `Section` in
      `Immich Slideshow/Slideshow/SlideshowSettingsView.swift` — usage label (refreshed on
      appear + after Clear), budget `Picker` over `CacheBudget.steps` bound to
      `CacheBudgetStore` and calling `setBudget` (immediate prune, FR-320-04), Clear button
      behind a confirmation dialog invoking both stores' `clear()` (FR-320-05); accessibility
      IDs `settings.storage.usage`/`.budget`/`.clear`; `#Preview` renders the section
      (depends on T006)
- [x] T013 [US3] App wiring in `Immich Slideshow/Immich_SlideshowApp.swift` — create one
      shared `DiskImageCache` (root `Library/Caches/ImageCache/`, budget from
      `UserDefaultsCacheBudgetStore`), one `FileSourceSnapshotStore`
      (`Application Support/SourceSnapshots/`, backup-excluded); pass into `makeSlideshow`
      (both VM params) and `SlideshowSettingsView`; `UITestSupport` gets temp-dir instances
      so the hermetic build exercises the real paths (depends on T008, T010, T012)
- [x] T014 [US3] Red→Green: `Immich SlideshowUITests/SettingsStorageUITests.swift` — storage
      section present with usage label, budget selection persists across relaunch, Clear
      (confirm dialog) resets the usage label (hermetic `--uitest` seams, portrait reset per
      memory `uitest-launch-seams`) (depends on T013)

**Checkpoint**: feature complete — all three stories live in the app target.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T015 [P] Privacy/robustness audit (FR-320-10): snapshot root provably backup-excluded
      (assert resource value in `SourceSnapshotStoreTests`); grep the 320 diff — no secrets,
      no URLs, no logging of photo content; snapshot JSON contains ids + type only
- [x] T016 Verification gate (Claude-owned): XcodeBuildMCP `build_sim` + `test_sim` on the
      app scheme — whole classes only (memory `xcodebuildmcp-single-test-false-green`)
- [x] T017 Full XCUITest suite via `test_sim` before merge (SwiftUI touched — repo rule,
      memory `run-full-xcuitest-before-merge`)
- [x] T018 [P] Docs: add the 320 section to `docs/spec-traceability.md` (FR/SC → tests);
      update `docs/spec-overview.md` (320 row Active, dependency line); flip
      `specs/320-disk-image-cache/spec.md` Status to Implemented; note the promotion of
      FR-300-08/27 out of topic 300's Roadmap in `specs/300-slideshow/spec.md`; check off
      this file's boxes
- [x] T019 Run the quickstart validation pass end-to-end (host + sim gates); optional live
      smoke: Airplane Mode mid-show → full rotation continues; force-quit + relaunch offline
      → show returns; Settings usage plausible, Clear → 0

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 2** after T001. Internal: T002→T003, T004→T005, T006 after T002; T002 ∥ T004
  (different files).
- **Phase 3 (US1)** after T003 (+T007 red first).
- **Phase 4 (US2)** after Phase 3 (same `SlideshowViewModel.swift` + the disk tier is what
  the snapshot plays from) and T005.
- **Phase 5 (US3)** after Phase 4 (T011 exercises both stores through the engine); T012
  needs only T006; T013 needs T008+T010+T012; T014 last.
- **Phase 6** after Phase 5; T015 ∥ T018; T017 last before merge.

### Within Each Story

Red before green: T002→T003, T004→T005, T007→T008, T009→T010, T014 red-then-green in place.
`SlideshowOfflineTests.swift` is shared by T007/T009/T011 — sequential by design.

### Parallel Opportunities

- T002 ∥ T004 (two independent red suites); T015 ∥ T018 in polish.
- No Codex delegation (disabled) — parallelism is within-session only.

---

## Implementation Strategy

### MVP First (US1 only)

Phase 2 + Phase 3 already deliver the felt need: an outage mid-run keeps the whole album on
the wall. **STOP and VALIDATE** on the host suite; US2/US3 build on the same stores.

### Incremental Delivery

US1 (outage depth) → US2 (relaunch survival — the appliance story) → US3 (Settings control,
explicitly requested) → Phase 6 gates → merge. Release timing per
`docs/handover-release-prep.md`: 310 gates the App Store release; 320 can ship in 1.0 if it
lands before submission, else it is the first 1.0.x update.

---

## Notes

- Commit after each red+green pair; stage with explicit paths, never `-A`.
- Both VM params default to nil — if any existing 300/310 test needs modification, that is a
  design smell: stop and re-check (the contract promises byte-for-byte 310 behavior).
- Disk I/O in tests is real but tmp-dir-local and fast; keep per-test dirs unique
  (`FileManager.temporaryDirectory` + UUID) so parallel test execution never collides.
