# Tasks: Photo Library Source (Apple Photos / iCloud Albums)

**Input**: Design documents from `/specs/900-photo-library-source/`

**Prerequisites**: plan.md, spec.md, research.md (R1–R12), data-model.md,
contracts/photo-source-protocol.md, quickstart.md

**Tests**: INCLUDED — TDD is constitution principle I (NON-NEGOTIABLE). Every
implementation task is preceded by its red test task; subagent reports must show the red
run.

**Organization**: Setup → Foundational (the FR-900-01 refactor — blocks everything) → user
stories in priority order → polish. Delegation slices per
`docs/implementation-session-plan.md`: Foundational = slices A/B (sequential Opus
subagents), US1–US3 = slices C/D/E, app-target/UI tasks are Fable-inline.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Scaffold `Packages/PhotoSourceKit` (Package.swift: platforms iOS 17/macOS 14,
      products `PhotoSourceKit` + `PhotoSourceTestSupport`, empty source/test targets)
- [x] T002 [P] Scaffold `Packages/PhotoLibraryKit` (Package.swift: depends on
      `../PhotoSourceKit`, source + test targets)
- [x] T003 Add both package references to `Immich Slideshow.xcodeproj/project.pbxproj`
      (pbxproj explicitly IN SCOPE for this task only) and link products to the app target

---

## Phase 2: Foundational (the source-protocol refactor — BLOCKS all user stories)

**Purpose**: FR-900-01/02 — engine consumes only `PhotoSourceProviding`; ImmichClient
becomes a peer conformer; snapshot wire format preserved (R2).

- [x] T004 [P] Red tests: neutral model semantics in
      `Packages/PhotoSourceKit/Tests/PhotoSourceKitTests/SourceModelsTests.swift` —
      `SourceAsset` encodes/decodes the exact `{id, type}` shape (checked-in legacy JSON
      fixture), unknown `type` string → `.other`, `SourceFailure` case surface per
      data-model.md
- [x] T005 Implement `Packages/PhotoSourceKit/Sources/PhotoSourceKit/`
      (`PhotoSourceProviding.swift`, `SourceModels.swift`, `SourceFailure.swift`) per
      contracts — green T004
- [x] T006 [P] Implement scriptable `StubPhotoSource` in
      `Packages/PhotoSourceKit/Sources/PhotoSourceTestSupport/StubPhotoSource.swift`
      (per-call results/delays/errors — feature parity with today's `StubImmichAPI`)
- [x] T007 Red tests: Immich conformance + error mapping in
      `Packages/ImmichClient/Tests/ImmichClientTests/ImmichPhotoSourceTests.swift`
      (MockTransport-driven: collections/assets/imageData/metadata mapping; the full
      ImmichError → SourceFailure table from data-model.md)
- [x] T008 Implement `Packages/ImmichClient/Sources/ImmichClient/ImmichPhotoSource.swift`
      (+ Package.swift dep on PhotoSourceKit) — green T007
- [x] T009 Migrate SlideshowKit test doubles: replace `StubImmichAPI` usage with
      `StubPhotoSource` across `Packages/SlideshowKit/Tests/SlideshowKitTests/` (Fakes.swift
      first) — suites red/non-compiling against the yet-unchanged engine is the expected
      state before T010
- [x] T010 Refactor `Packages/SlideshowKit/Sources/SlideshowKit/` to the neutral contract:
      `SlideshowViewModel.swift` (`source: any PhotoSourceProviding`, `ensureReady()`,
      `kind == .image` filter, `SourceFailure` paths), `RetryPolicy.swift`
      (`classify(SourceFailure)`), `SourceSnapshotStore.swift` (`[SourceAsset]`, wire
      compat), Package.swift (drop ImmichClient, add PhotoSourceKit) — ALL suites green
      incl. the legacy-fixture decode
- [x] T011 Red-then-green: `SourceKind.photoLibrary(collectionID:)` + selected-photos
      sentinel in `Packages/OnboardingKit` — tests in
      `Tests/OnboardingKitTests/SourceLibraryTests.swift` +
      `SourceLibraryViewModelTests.swift`, impl in `Sources/OnboardingKit/Source.swift`,
      `SourceLibrary.swift`, `SourceLibraryViewModel.swift` (additive codable, R11)
- [x] T012 Rewire app target to neutral types (Fable-inline):
      `Immich Slideshow/Immich_SlideshowApp.swift` (factories build
      `ImmichPhotoSource`-backed provider),
      `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift` +
      `AlbumBrowserView.swift` (consume `[SourceCollection]`) — build green; red coverage
      is implicit: the existing app-side suites (adapter tests, HA round-trip) go red
      during the rewiring and gate it
- [x] T013 **Checkpoint (quickstart Phase-1 gate)**: `swift test` green for PhotoSourceKit,
      SlideshowKit, ImmichClient, OnboardingKit; XcodeBuildMCP `build_sim` + app-bundle
      `test_sim` green; zero behavioral test edits beyond renames

---

## Phase 3: User Story 1 — Add a Photos album as a source (P1) 🎯 MVP

**Goal**: Pick "Photos album" → grant access → choose album (incl. iCloud Shared Album) →
it plays like any source, persists, survives relaunch, participates in switching.

**Independent Test**: spec US1 — fake provider behind the protocol: album list enumerates,
selected album plays through the unchanged engine, source persists in the 120 library.

- [x] T014 [P] [US1] Red tests: provider happy path in
      `Packages/PhotoLibraryKit/Tests/PhotoLibraryKitTests/PhotoLibraryProviderTests.swift`
      against a new `FakePhotoLibraryGateway` (collections incl. shared albums; windowed
      assets; `ensureReady()` full→ok, notDetermined→`.authentication`; vanish →
      `.notFound`)
- [x] T015 [US1] Implement `Packages/PhotoLibraryKit/Sources/PhotoLibraryKit/`
      (`PhotoLibraryProvider.swift`, `PhotoLibraryGateway.swift`,
      `PhotoLibraryAuthorization.swift` basic states) — green T014
- [x] T016 [P] [US1] Seam guard test in
      `Packages/PhotoLibraryKit/Tests/PhotoLibraryKitTests/SeamTests.swift`: `import Photos`
      appears in `PHKitGateway.swift` only (source-grep assertion)
- [x] T017 [US1] Implement `Packages/PhotoLibraryKit/Sources/PhotoLibraryKit/PHKitGateway.swift`
      (the ONLY Photos import): `.readWrite` authorization, user albums +
      `.albumCloudShared` fetch, windowed asset fetch, final-quality image request (R5/R6) —
      Fable-inline (privacy-adjacent thin adapter)
- [x] T018 [US1] Red UITest: full-access picker flow in
      `Immich SlideshowUITests/PhotoAlbumPickerUITests.swift` (hermetic `--uitest-photos`
      seam with in-memory fake gateway: entry point → request → searchable album list →
      select → slideshow)
- [x] T019 [US1] Implement `Immich Slideshow/Onboarding/PhotoAlbumPickerView.swift`
      (reuse `AlbumPickerView` 210 pattern) + entry points in `SourceStepView.swift` and
      `SourceLibraryView.swift`; wire the hermetic `--uitest-photos` seam
      (FakePhotoLibraryGateway injection) in `Immich Slideshow/Immich_SlideshowApp.swift`;
      add `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` to
      `Immich Slideshow.xcodeproj/project.pbxproj` (pbxproj explicitly IN SCOPE for this
      key only) — green T018
- [x] T020 [US1] Cross-backend switching: red engine test (backend change → `.rebuild`, no
      leaked timers — SC-900-06 seed) in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowViewModelTests.swift`; wire
      provider factory by `SourceKind` in `Immich Slideshow/Immich_SlideshowApp.swift`
- [x] T021 [US1] **Checkpoint**: US1 acceptance 1–5 pass (saved Photos source persists,
      relaunch resumes, app-UI switching works) — `test_sim` whole classes + new UITest

---

## Phase 4: User Story 2 — iCloud originals arrive gracefully (P1)

**Goal**: Optimized-storage albums play without blank frames; failures skip; only
final-quality renders; Live Photos show their still; library changes reach the rotation.

**Independent Test**: spec US2 — fake gateway with delayed/failed delivery: no-blank rules
hold, skips accumulate calmly, prefetch flows through the abstraction.

- [x] T022 [P] [US2] Red tests: delivery semantics in
      `Packages/PhotoLibraryKit/Tests/PhotoLibraryKitTests/ImageDeliveryTests.swift`
      (degraded delivery dropped — FR-900-07; iCloud error → `.transient`; Live Photo →
      `.image` kind — FR-900-08) and engine slow-source scenario additions in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowResilienceTests.swift`
- [x] T023 [US2] Implement delivery paths in `PhotoLibraryProvider.swift` +
      `PHKitGateway.swift` (network-allowed, single high-quality delivery, degraded guard,
      Live-Photo still mapping) — green T022
- [x] T024 [US2] Red tests: change observation + refetch in
      `Packages/PhotoLibraryKit/Tests/PhotoLibraryKitTests/ChangeObservationTests.swift`
      (change handler fires engine refresh; mid-play vanish → `.notFound` calm — FR-900-09/16)
- [x] T025 [US2] Implement change-handler wiring (`setChangeHandler` → engine refresh path)
      + foreground refetch hook in `Immich Slideshow/Immich_SlideshowApp.swift` scenePhase
      observer — green T024
- [x] T026 [US2] **Dual-fake gate (SC-900-03)**: parameterized engine scenario suite in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/DualBackendScenarioTests.swift` running
      identical assertions over `StubPhotoSource` AND
      `PhotoLibraryProvider(FakePhotoLibraryGateway)` — both green

---

## Phase 5: User Story 3 — Permissions handled honestly (P2)

**Goal**: Denied/limited/downgraded access never dead-ends: Selected-Photos source under
limited, calm actionable states, downgrade mid-life handled.

**Independent Test**: spec US3 — fake authorization states drive picker content and calm
states; revoked-while-active errors like a failed Immich source.

- [x] T027 [P] [US3] Red tests: full authorization matrix in
      `Packages/PhotoLibraryKit/Tests/PhotoLibraryKitTests/AuthorizationTests.swift`
      (data-model table: limited → albums `.authentication` / selected-photos OK; downgrade
      transition mid-session; denied; platform add-only status maps to `.denied` at the
      gateway — FR-900-04)
- [x] T028 [US3] Implement complete state machine + 
      `Packages/PhotoLibraryKit/Sources/PhotoLibraryKit/SelectedPhotosSource.swift`
      (granted-pool enumeration via `fetchGrantedAssets`) — green T027
- [x] T029 [US3] Red UITests: limited/denied/downgrade surfaces in
      `Immich SlideshowUITests/PhotoAlbumPickerUITests.swift` (Selected-Photos row +
      manage-selection + honest album note; denied message + Settings path; downgrade →
      calm unavailable with cause copy incl. iOS-27 wording — US3-1/2/4, FR-900-16)
- [x] T030 [US3] Implement calm-state UI: picker limited/denied variants in
      `PhotoAlbumPickerView.swift`, vanish/downgrade copy in
      `Immich Slideshow/Slideshow/SlideshowErrorView.swift` — green T029

---

## Phase 6: Polish & Cross-Cutting

- [x] T031 [P] HA parity (FR-900-11/12): Photos sources in the HA source select +
      current-photo metadata (date + coordinates, no placeName — R7) in
      `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift`; red round-trip
      addition in `Immich SlideshowTests/HAControlRoundTripTests.swift`; publish-images
      opt-in copy covers all sources
- [x] T032 [P] Info overlay (FR-900-10): verify date-only rendering for Photos assets in
      `Immich Slideshow/Slideshow/PhotoInfoView.swift` (absent placeName renders nothing —
      existing FR-300-24 path; add test/preview case)
- [x] T033 Quality honesty (FR-900-15): Settings copy notes the shared-album ceiling where
      the quality picker shows for a Photos source, in
      `Immich Slideshow/Slideshow/SlideshowSettingsView.swift`
- [x] T034 [P] Docs: flip 900 status in `docs/spec-overview.md` (Deferred → Active/
      Implemented as reached) and record FR→test traceability in
      `docs/spec-traceability.md` (900 section)
- [x] T035 Full XCUITest suite via XcodeBuildMCP `test_sim` (standing pre-merge rule;
      broker-toggle class re-run isolated if it flakes) + quickstart.md Phase-1/2/3 gate
      commands re-run clean + FR-900-14 egress review: grep PhotoLibraryKit for any network
      API use — only the gateway's PhotoKit calls are permitted
- [x] T036 Schedule (do NOT execute now) the manual release gates: SC-900-01/02/04 device
      passes and the SC-900-07 iOS-27-beta ship gate — tracked as a checklist in
      `specs/900-photo-library-source/quickstart.md`

---

## Dependencies & Execution Order

- **Setup (T001–T003)** → **Foundational (T004–T013)** → user stories.
- Within Foundational: T004→T005→T006 and T007→T008 (T007 needs T005); T009→T010 (needs
  T005/T006); T011 independent after T005; T012 needs T008+T010+T011; T013 gates.
- **US1 (T014–T021)** first (MVP). **US2 (T022–T026)** needs US1's provider (T015/T017).
  **US3 (T027–T030)** needs T015; independent of US2 — can run parallel to US2 on disjoint
  files (worktree isolation per session plan).
- Polish (T031–T036) after US1–US3; T031/T032/T034 parallelizable.

## Parallel Opportunities

- T001 ∥ T002; T004 ∥ T006 (after T001); T007 ∥ T009 prep; T014 ∥ T016; T022 ∥ T027 (US2 ∥
  US3 across packages/files); T031 ∥ T032 ∥ T034.
- Delegation: slice A = T009–T010, slice B = T007–T008 (sequential with A — shared
  boundary), slice C = T014–T015, slice D = T027–T028, slice E = T022–T025. Fable-inline:
  T003, T012, T017, T018–T019, T029–T030, all checkpoints/gates.

## Implementation Strategy

**MVP = Phase 1 + 2 + US1**: after T021 a user can play an iCloud album on the frame — 
demoable increment. US2 hardens it for real iCloud conditions; US3 completes the permission
honesty; polish delivers HA/overlay parity. Stop-and-validate at every checkpoint (T013,
T021, T026, T030, T035). Commit after each green task or logical pair (red+green together).
