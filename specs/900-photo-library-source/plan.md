# Implementation Plan: Photo Library Source (Apple Photos / iCloud Albums)

**Branch**: `900-photo-library-source` (branch off `main` @ d533f2d) | **Date**: 2026-07-16 |
**Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/900-photo-library-source/spec.md` (amended
2026-07-16 with the authorization/quality/iOS-27 research); portability audit + session plan
in `docs/implementation-session-plan.md`.

## Summary

Two deliveries in one feature. **First, the load-bearing refactor (FR-900-01)**: a new
Foundation-only package `PhotoSourceKit` defines the backend-neutral source contract —
`PhotoSourceProviding` (collections, assets, image data by fidelity tier, metadata,
readiness) plus neutral types (`SourceAsset`, `SourceCollection`, `AssetMetadata`,
`SourceFailure`). SlideshowKit's engine drops its `ImmichClient` dependency entirely and
consumes only this protocol; `ImmichClient` conforms in-package (mapping its REST endpoints,
version gate, and `ImmichError` onto the contract); the persisted snapshot JSON keeps its
on-disk shape (`{id, type}`) so fielded frames need no migration. **Second, the feature
(US1–US3)**: a new `PhotoLibraryKit` package implements the same protocol over PhotoKit
behind a `PhotoLibraryGateway` seam (no PhotoKit in unit tests, FR-900-13), with the
access-level-aware authorization state machine (full/limited/denied + mid-life downgrade),
the limited-mode "Selected Photos" source, change observation + foreground refetch, and the
vanish handling (FR-900-16). OnboardingKit's `SourceKind` gains `photoLibrary`; the app
target adds the Photos album picker (full-access gate, honest limited mode) and wires the
new backend through the existing rebuild restart strategy. HA (700/710) sees a Photos source
like any other.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: Foundation, Observation, Swift Testing (existing posture). New
package `PhotoSourceKit` (Foundation-only, zero deps). New package `PhotoLibraryKit`
(depends on PhotoSourceKit; imports Photos/CoreLocation **only** inside the thin gateway
adapter). Existing packages: SlideshowKit (loses its ImmichClient dependency, gains
PhotoSourceKit), ImmichClient (gains PhotoSourceKit conformance), OnboardingKit (SourceKind
extension), ThemeKit/HAControlKit (unchanged code, HA adapter re-wired in app target). No
third-party dependencies.

**Storage**: No new persistent stores. Snapshot JSON keeps the exact `{id, type}` wire
format under `Application Support/SourceSnapshots` (decode-tolerant round-trip through the
neutral `SourceAsset`). Disk image cache unchanged (keys stay `assetID#tier`). One new
`SourceKind` case persisted by the existing `UserDefaultsSourceLibraryStore` (non-secret:
collection identifier + label only).

**Testing**: Swift Testing on the host for everything behind protocols: engine suites run
against BOTH `StubPhotoSource` (renamed/generalized `StubImmichAPI`) and the new
`FakePhotoLibraryGateway` (SC-900-03); authorization state machine, Selected-Photos source,
change-reconciliation, and vanish cases are pure host tests. XcodeBuildMCP `test_sim` for
app-target integration (whole classes — single-`@Test` runs false-green); full XCUITest
before merge (standing rule); device spot-check with real iCloud content before feature
release (SC-900-02) and the iOS-27-beta pass (SC-900-07) as the ship gate, not this session.

**Target Platform**: iPadOS/iOS 17+ (re-verified: every PhotoKit API used is iOS 15 or
older; `.readWrite` authorization API is iOS 14+)

**Project Type**: Mobile app (SwiftUI, MVVM `@Observable`), SPM modules

**Performance Goals**: no blank frames with iCloud-resident originals (SC-900-02) — the
existing prefetch (FR-300-06) + slow-connection rules carry the latency; enumeration of
10k+-asset albums stays lazy/windowed (spec edge case) — collection fetch returns counts
without materializing assets; degraded PhotoKit deliveries are filtered, never rendered
(FR-900-07).

**Constraints**: full-access gate for album listing (FR-900-03/04 — `.readWrite`
access-level API only); limited mode = exactly one Selected-Photos source; source vanish
(incl. iOS 27 upgrade) is a first-class calm state (FR-900-16); legacy shared-album ceiling
2048 px — never implied otherwise (FR-900-15); nothing leaves the device beyond existing HA
opt-ins (FR-900-14); no PhotoKit import outside the gateway adapter (FR-900-13);
engine references no concrete backend (FR-900-01).

**Scale/Scope**: 2 new packages (PhotoSourceKit ~4 source files; PhotoLibraryKit ~6),
refactor touches SlideshowKit (~6 files), ImmichClient (+1 conformance file), OnboardingKit
(~3 files), app target (~5 files: picker UI, wiring, HA adapter mapping). ~8 new/renamed
host test suites. Delegation per `docs/implementation-session-plan.md` (Opus subagents,
sequential on the shared protocol boundary).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Test-First (NON-NEGOTIABLE)**: PASS — refactor slices are red-first by construction:
  the generalized engine suites are written against the new protocol before the engine
  compiles against it; PhotoLibraryKit logic is specified by failing host tests against
  `FakePhotoLibraryGateway`. Subagent briefings require the red test in the report
  (session-plan operating rules).
- **II. Modular Isolation**: PASS — the entire feature *is* an isolation move: engine ↔
  backend decoupled via `PhotoSourceProviding`; PhotoKit behind `PhotoLibraryGateway`;
  authorization behind a protocol; no hidden singletons (PHPhotoLibrary access lives only in
  the injected gateway adapter).
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)**: PASS — this backend has no
  credentials at all; persisted data is collection IDs, asset IDs, and titles (non-secret).
  Library content stays on-device except the existing explicit HA opt-ins (FR-900-12/14).
- **IV. Transport-Layer Security**: PASS — no app-managed transport is added; PhotoKit's
  iCloud fetches are system-internal. Immich TLS posture untouched.
- **V. Respect Platform Boundaries**: PASS — designed with the platform: full-access
  requirement encoded instead of worked around; limited mode gets its honest reduced
  surface; no real-time guarantee claimed for shared-album sync (FR-900-09); iOS 27
  upgraded-album opacity handled as a calm state, not fought (FR-900-16).
- **VI. Verifiable Acceptance Criteria**: PASS — SC-900-01…07 map to host tests (dual-fake
  engine suites, authorization matrix, vanish drill), UI tests (calm states, picker), and
  two explicitly scheduled real-device gates (SC-900-02 spot-check, SC-900-07 beta pass).
- **VII. Plain and Light by Default**: PASS — no new visual defaults; the Photos source
  plays through the existing calm engine; picker reuses the 210 pattern; limited/denied
  states are quiet text, not modal nagging.

**Result**: PASS — no violations; Complexity Tracking left empty. (The one debatable
addition — a second new package — is justified under II: `PhotoSourceKit` must sit below
both ImmichClient and PhotoLibraryKit, and neither may depend on the other.)

## Project Structure

### Documentation (this feature)

```text
specs/900-photo-library-source/
├── plan.md              # This file
├── research.md          # Phase 0 — protocol placement, wire-format, error taxonomy,
│                        #   PhotoKit seam, authorization, geocoding, Live-Photo stills
├── data-model.md        # Phase 1 — neutral types, authorization states, SourceKind change
├── quickstart.md        # Phase 1 — validation scenarios mapped to FR/SC
├── contracts/
│   └── photo-source-protocol.md   # Phase 1 — PhotoSourceKit + PhotoLibraryKit public API,
│                                  #   engine/Onboarding deltas
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
Packages/PhotoSourceKit/                    # NEW — Foundation-only contract package
├── Sources/PhotoSourceKit/
│   ├── PhotoSourceProviding.swift          # the protocol (collections/assets/image/metadata/readiness)
│   ├── SourceModels.swift                  # SourceAsset, SourceCollection, AssetMetadata, ImageFidelity
│   ├── SourceFailure.swift                 # neutral failure taxonomy (transient/auth/notFound/permanent)
│   └── PhotoSourceTestSupport (product)    # StubPhotoSource for downstream suites
└── Tests/PhotoSourceKitTests/

Packages/PhotoLibraryKit/                   # NEW — PhotoKit-backed provider
├── Sources/PhotoLibraryKit/
│   ├── PhotoLibraryProvider.swift          # PhotoSourceProviding conformance (pure logic)
│   ├── PhotoLibraryGateway.swift           # seam: collections/assets/image-request/observer/auth
│   ├── PhotoLibraryAuthorization.swift     # state machine: full/limited/denied + downgrade
│   ├── SelectedPhotosSource.swift          # the limited-mode single source
│   └── PHKitGateway.swift                  # the ONLY file importing Photos (thin adapter)
└── Tests/PhotoLibraryKitTests/             # FakePhotoLibraryGateway + all logic suites

Packages/SlideshowKit/                      # REFACTOR — drops ImmichClient dependency
├── Sources/SlideshowKit/
│   ├── SlideshowViewModel.swift            # api: any PhotoSourceProviding; neutral errors
│   ├── SourceSnapshotStore.swift           # persists [SourceAsset], same {id,type} wire format
│   └── RetryPolicy.swift                   # classifies SourceFailure instead of ImmichError
└── Tests/SlideshowKitTests/                # suites run against StubPhotoSource (dual-fake gate)

Packages/ImmichClient/
└── Sources/ImmichClient/
    └── ImmichPhotoSource.swift             # NEW — PhotoSourceProviding conformance over ImmichAPI

Packages/OnboardingKit/
└── Sources/OnboardingKit/Source.swift      # SourceKind + .photoLibrary case (+ library/vm updates)

OwnFrame/                           # app target
├── Onboarding/PhotoAlbumPickerView.swift   # NEW — Photos album picker (full-access gate, 210 pattern)
├── Slideshow/…                             # wiring: provider factory, restart strategy, calm states
└── Slideshow/SlideshowRemoteControlAdapter.swift  # HA mapping via neutral collections
```

**Structure Decision**: Two new SPM packages. `PhotoSourceKit` is the shared floor (both
backends and the engine depend on it; it depends on nothing). `PhotoLibraryKit` mirrors the
house pattern of ImmichClient: logic host-testable, the platform adapter (`PHKitGateway`)
kept to one file, injected from the app target — exactly like `UIScreenController` stays out
of PowerKit.

## Complexity Tracking

> No constitution violations — table intentionally empty.
