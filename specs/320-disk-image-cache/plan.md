# Implementation Plan: Disk Image Cache (Offline Photo Survival)

**Branch**: `320-disk-image-cache` (branch off `310-slideshow-resilience` — 310 is a hard
prerequisite) | **Date**: 2026-07-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/320-disk-image-cache/spec.md`

## Summary

Add the persistence tier under the existing engine: image loading becomes RAM (`ImageCache`,
unchanged) → disk (`DiskImageCache`, new: byte-capped LRU actor over a directory of files) →
network, with write-through on fetch. The active source's asset list is snapshotted to disk on
every successful fetch (hooked into 310's `markRefreshSucceeded`), and `start()` gains an
offline fallback: source fetch fails + snapshot exists → play the snapshot from disk while
310's retry recovers live data (its reconciler already merges the live list back — zero new
recovery machinery). A Settings "Storage" section surfaces the budget (fixed steps, 500 MB
default via a UserDefaults-backed `CacheBudgetStore`), live usage, and Clear. Both new stores
are injectable and optional on the view model (`nil` = exact 310 behavior, so every existing
test stays green unchanged); host tests run the real file-backed stores against temp
directories with an injected time source.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: Foundation (FileManager), Observation, Swift Testing; existing
packages SlideshowKit (host of all new logic), ImmichClient (Asset type, unchanged), ThemeKit
(unchanged). No new external dependencies.

**Storage**: Image files under `Library/Caches/ImageCache/` (app-private, iOS-purgeable, not
backed up — the right semantics for re-fetchable data). Snapshot JSON files under
`Library/Application Support/SourceSnapshots/` with `isExcludedFromBackup` set (tiny,
non-secret: asset IDs + type only). One UserDefaults key for the budget (non-secret integer).

**Testing**: Swift Testing on the host (`swift test` in `Packages/SlideshowKit`): real
`DiskImageCache`/`FileSourceSnapshotStore` against temp directories (hermetic, fast) with an
injected `now: () -> Date` for deterministic LRU; engine-level offline scenarios reuse 310's
`TestClock` + `StubImmichAPI` harness. XcodeBuildMCP `test_sim` (whole classes) for the app
target; full XCUITest before merging the SwiftUI changes (Settings section).

**Target Platform**: iPadOS 26+ on `main` (no API newer than iOS 17 used — same posture as 310)

**Project Type**: Mobile app (SwiftUI, MVVM with `@Observable`), Swift Package Manager modules

**Performance Goals**: disk hit adds no visible loading state vs RAM hit (SC-320-05); store/
prune never block or delay a slide transition (FR-320-11 — writes are fire-and-forget off the
display path); relaunch-offline reaches playback without user input (SC-320-02).

**Constraints**: usage ≤ budget after every completed store (FR-320-03); silent degradation on
write failure/corruption/purge (FR-320-09/10); no secrets in snapshots or logs (FR-320-10);
Clear wipes images + snapshots without touching the on-screen photo (FR-320-05); everything
injectable for host tests (FR-320-12).

**Scale/Scope**: one package (SlideshowKit: 3 new source files, 1 modified) + 2 app files;
~3 new host test suites; budget default 500 MB ≈ 1,000–2,500 preview photos.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Test-First (NON-NEGOTIABLE)**: PASS — every slice red-first on the host: cache
  cap/LRU/corruption/clear against a temp dir, snapshot round-trip, engine offline scenarios
  under `TestClock`. Settings UI verified by preview + UITest per house rules.
- **II. Modular Isolation**: PASS — `DiskImageStoring`, `SourceSnapshotStoring`, and
  `CacheBudgetStore` are protocols with injectable roots/time; the view model takes them as
  optional dependencies (nil = 310 behavior). No hidden singletons.
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)**: PASS — snapshots persist asset IDs +
  type only (FR-320-06/10); no credentials, no URLs. Image bytes are personal-but-not-secret
  content inside the app sandbox, never leaving the device.
- **IV. Transport-Layer Security**: PASS — no transport changes; fewer network fetches, same
  TLS-validated client.
- **V. Respect Platform Boundaries**: PASS — designed *with* the platform: Caches directory
  is purgeable by iOS and the spec tolerates purges (US2-4); backup exclusion set explicitly;
  no fighting storage pressure.
- **VI. Verifiable Acceptance Criteria**: PASS — SC-320-01…06 map to deterministic host
  tests (temp dirs, byte counts, call counts) plus one UITest for the Settings section.
- **VII. Plain and Light by Default**: PASS — zero new visual behavior by default; one calm
  Settings section; fixed budget steps instead of a free-form field (ease-of-use goal).

**Result**: PASS — no violations; Complexity Tracking left empty.

## Project Structure

### Documentation (this feature)

```text
specs/320-disk-image-cache/
├── plan.md                      # This file
├── research.md                  # Phase 0 — tier composition, LRU mechanics, snapshot store,
│                                #   budget store placement, backup/purge posture
├── data-model.md                # Phase 1 — DiskImageCache, SourceSnapshot, CacheBudget,
│                                #   offline startup fallback rules
├── quickstart.md                # Phase 1 — validation scenarios mapped to FR/SC
├── checklists/requirements.md   # spec quality gate (passed 2026-07-09)
├── contracts/
│   └── disk-cache-api.md        # Phase 1 — protocols + SlideshowViewModel additions
└── tasks.md                     # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Packages/SlideshowKit/Sources/SlideshowKit/
├── DiskImageCache.swift         # NEW: DiskImageStoring protocol + DiskImageCache actor —
│                                #   files under an injected root, filename = sanitized cache
│                                #   key, LRU by access stamp (injected now()), incremental
│                                #   usage accounting (init scan), prune-to-budget, clear
├── SourceSnapshotStore.swift    # NEW: SourceSnapshotStoring protocol + file-backed impl —
│                                #   one JSON per source key (albumID), replace-on-save,
│                                #   backup-excluded root
├── CacheBudget.swift            # NEW: CacheBudget value (bytes; steps 100 MB/250 MB/500 MB/
│                                #   1 GB/2 GB; default 500 MB) + CacheBudgetStore protocol +
│                                #   UserDefaults impl (HAPublishOptions precedent)
├── SlideshowViewModel.swift     # loadImageData: RAM → disk → network with write-through;
│                                #   prefetch writes through too; markRefreshSucceeded also
│                                #   saves the snapshot; start() catch: snapshot fallback
│                                #   before handleFailure; both stores optional (nil = 310)
└── ImageCache.swift             # UNCHANGED (RAM tier)

Packages/SlideshowKit/Tests/SlideshowKitTests/
├── DiskImageCacheTests.swift    # NEW: cap/LRU/eviction order (injected now), corruption→miss
│                                #   +delete, write-failure degrade, clear, prune-on-budget-cut,
│                                #   usage accounting, key sanitization
├── SourceSnapshotStoreTests.swift # NEW: round-trip, replace, per-source isolation, clear,
│                                #   corrupt-file → nil
├── SlideshowOfflineTests.swift  # NEW: US1/US2 engine scenarios (TestClock + StubImmichAPI +
│                                #   real stores in temp dirs)
└── Fakes.swift                  # + temp-dir helper; existing fakes unchanged

Immich Slideshow/
├── Immich_SlideshowApp.swift    # create ONE shared DiskImageCache + snapshot store + budget
│                                #   store at startup; inject into makeSlideshow (the VM's new
│                                #   optional params) and into Settings
└── Slideshow/SlideshowSettingsView.swift  # "Storage" Section: usage label, budget picker
                                 #   (fixed steps), Clear button (confirmation dialog)

Immich SlideshowUITests/
└── SettingsStorageUITests.swift # NEW: storage section present, picker persists, Clear resets
                                 #   the usage label (hermetic --uitest build)
```

**Structure Decision**: The two stores live in `SlideshowKit` next to the engine that uses
them — same boundary as `ImageCache`. The view model keeps sole ownership of load ordering
(RAM → disk → network) rather than hiding the tiers behind a composite cache type: the tiers
have different natures (sync RAM, async file I/O, async network) and 310's failure handling
already sits in the view model's load path. Both new dependencies are optional with `nil`
defaults, which keeps the entire existing 310/300 test suite green without modification and
makes the app target's wiring (one shared instance of each, created at startup) the only
place that turns the feature on. The budget setting follows the `HAPublishOptions` precedent
(own small store in the owning package) rather than growing `ThemeSettings` — storage policy
is not a display preference.

## Complexity Tracking

> No constitution violations — section intentionally empty.
