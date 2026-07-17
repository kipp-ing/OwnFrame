# Tasks: App Intents (Shortcuts, Siri, Apple Automations)

**Input**: Design documents from `/specs/800-app-intents/`

**Prerequisites**: plan.md, spec.md, research.md (R1–R9), data-model.md,
contracts/app-intents-surface.md, quickstart.md

**Tests**: INCLUDED — TDD is constitution principle I (NON-NEGOTIABLE). Every
implementation task is preceded by its red test task; subagent reports must show the
red run. A task whose red state is "suite doesn't compile yet" says so explicitly.

**Organization**: Setup → Foundational (registry + the adapter-hoisting refactor —
blocks everything) → user stories in priority order (US1, US2 both P1; US3 P2) →
polish. Delegation per the 900 model (Fable orchestrates, Opus subagents implement):
package-only slices are delegable; everything touching `Immich_SlideshowApp.swift`,
the AppIntents shells, or the simulator stays Fable-inline (CLAUDE.md: entry-point /
cross-cutting work is not delegated).

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Scaffold `Packages/AppIntentsKit` (Package.swift: platforms to match
      HAControlKit, dependency `../HAControlKit` — the `HAControlKit` product only,
      never `HAControlMQTT`; products `AppIntentsKit` + `AppIntentsTestSupport`;
      empty source/test targets so `swift test` runs zero tests green)
- [x] T002 Add the package reference to `Immich Slideshow.xcodeproj/project.pbxproj`
      and link the `AppIntentsKit` product to the app target (pbxproj explicitly IN
      SCOPE for this task only); create the synchronized group folder
      `Immich Slideshow/Intents/` (empty)

---

## Phase 2: Foundational (registry + broker-less command surface — BLOCKS all user stories)

**Purpose**: FR-800-02's "one command path" precondition. The registry exists, and
the single `SlideshowRemoteControlAdapter` is built for every user — broker or not
(research R2/R3/R8). No intent can land before this phase completes.

- [x] T003 [P] Red tests: `Packages/AppIntentsKit/Tests/AppIntentsKitTests/RegistryTests.swift` —
      state derivation (`.notConfigured` beats `.notLive`; `.ready` only while an
      adapter is registered), register replaces previous / unregister clears / the
      reference is weak (a dropped adapter → `.notLive`), and `awaitReady(timeout:)`
      via an injected test clock: unconfigured → immediate `.notConfigured` throw;
      configured-but-empty → `.frameNotOpen` after timeout; register mid-wait →
      waiter resumes with the adapter (data-model.md transitions)
- [x] T004 Implement `Packages/AppIntentsKit/Sources/AppIntentsKit/FrameControlRegistry.swift`,
      `FrameCommandError.swift`, `SourceOption.swift` per data-model.md — green T003;
      the awaitReady grace is a named constant (`coldLaunchGrace = 5.0 s`) referenced
      by tests, contract copy, and the manual drills (analyze A1)
- [x] T005 [P] Implement `Packages/AppIntentsKit/Sources/AppIntentsTestSupport/RecordingControlSurface.swift` —
      scriptable `PlaybackControlling & PhotoReporting` fake: records every call with
      arguments in order, scriptable `playbackState`/`brightness`/`currentAlbum`/
      `currentPhotoReport` (parity with the HAControlKit test fakes' surface)
- [x] T006 Red tests (app-hosted): extend
      `Immich SlideshowTests/SlideshowRemoteControlAdapterTests.swift` —
      `updateAlbums(_:)` after init feeds `albumOptions` (legacy no-library fallback),
      photo-report `albumName`/`photoCount` enrichment, and a sources-present adapter
      ignores albums for options (900 semantics unchanged)
- [x] T007 Implement `updateAlbums(_:)` in
      `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift` (albums becomes
      private var; `albums:` init parameter keeps its default — existing tests compile
      unchanged) — green T006
- [x] T008 Hoist the adapter in `Immich Slideshow/Immich_SlideshowApp.swift`
      (Fable-inline): extract `makeAdapter` from `makeCoordinator` and build the ONE
      adapter per slideshow generation unconditionally (sync — sources from the loaded
      library); `makeCoordinator(adapter:)` keeps its broker gate and its async
      best-effort `albums()` fetch, now ending in `adapter.updateAlbums(_:)`; register
      the process-stable `FrameControlRegistry` in `AppDependencyManager` at app init
      with `sourceOptions` wired to the source-library store and `isConfigured` to the
      startup gate; `registry.register(adapter)` per generation,
      `registry.unregister()` on teardown (contracts § Dependency contract). The
      generation-scoped slideshow wiring RETAINS the adapter (the registry ref is
      weak and the coordinator no longer exists broker-less — analyze U1). Red
      coverage is implicit: `HAControlRoundTripTests` +
      `SlideshowRemoteControlAdapterTests` gate the refactor by staying green
- [x] T009 **Checkpoint**: `swift test` green in `Packages/AppIntentsKit`;
      XcodeBuildMCP `build_sim` green; app-hosted `SlideshowRemoteControlAdapterTests`
      + `HAControlRoundTripTests` green — zero observable HA behavior change

---

## Phase 3: User Story 1 — Control playback and brightness from Shortcuts/Siri (P1) 🎯 MVP

**Goal**: Pause / Resume / Next / Previous / Set Brightness intents drive the live
frame through the exact HA command path (FR-800-01/02/03/04/08).

**Independent Test**: quickstart Phase-1 gate — every service verb against
`RecordingControlSurface` produces the HA-identical call sequence (SC-800-01);
out-of-range brightness rejected with zero calls; shells forward and map errors
(app-hosted glue).

- [x] T010 [P] [US1] Red tests:
      `Packages/AppIntentsKit/Tests/AppIntentsKitTests/FrameCommandServiceTests.swift` —
      pause/resume/next/previous each produce exactly the call sequence the HA entity
      command produces (expected sequences documented inline next to their
      HAControlKit counterparts); paused + next steps without resuming (topic-710 US3
      parity); every verb runs `awaitReady` first (`.notConfigured`/`.frameNotOpen`
      surface unchanged from T003 semantics, state untouched)
- [x] T011 [P] [US1] Red tests:
      `Packages/AppIntentsKit/Tests/AppIntentsKitTests/BrightnessValidationTests.swift` —
      0 and 100 pass and map to `setBrightness(0.0)` / `setBrightness(1.0)`; 40 →
      0.4; −1 and 101 throw `.brightnessOutOfRange` with ZERO recorded calls
      (US1 acceptance 4, research R5); plus the race pin (spec Edge #2): two
      interleaved setBrightness calls on the MainActor → last write wins, the
      recorded call order ends with the second value (analyze G1)
- [x] T012 [US1] Implement
      `Packages/AppIntentsKit/Sources/AppIntentsKit/FrameCommandService.swift`
      (pause/resume/nextPhoto/previousPhoto/setBrightness + the shared awaitReady
      plumbing) — green T010 + T011
- [x] T013 [US1] Red tests (app-hosted): new
      `Immich SlideshowTests/FrameIntentGlueTests.swift` — each of the five control
      shells forwards to the matching service verb against a fake-backed registry;
      `FrameCommandError` cases map to the contract's exact localized copy;
      `openAppWhenRun == true` on all five; HA and the intents resolve the SAME
      adapter instance (the hoisting invariant, contracts § Dependency contract).
      Injection route (analyze U2): tests use the app's REAL registry and
      `register(...)` a `RecordingControlSurface` into it — never re-register
      `AppDependencyManager`. Expected red = suite doesn't compile until T014
- [x] T014 [US1] Implement the five `AppIntent` shells + localized error mapping in
      `Immich Slideshow/Intents/FrameIntents.swift` (`openAppWhenRun = true`,
      `ParameterSummary` on every intent, brightness `Int` parameter with
      `inclusiveRange` 0–100 — contracts § Intents) — green T013
- [x] T015 [US1] Implement `Immich Slideshow/Intents/FrameAppShortcuts.swift`
      (`AppShortcutsProvider`) with the five US1 phrases from contracts § App
      Shortcuts (every phrase carries `\(.applicationName)`; English-only).
      No red pair — phrases are extracted metadata, manual-gated by SC-800-03
      (analyze I1; same stance for the T024 phrase additions)
- [x] T016 [US1] **Checkpoint (MVP)**: quickstart Phase-1 gate green (`swift test` in
      the package), `FrameIntentGlueTests` green via `test_sim`, `build_sim` green;
      simulator spot-check: Shortcuts app lists the five actions and Pause/Resume
      work against the running frame

---

## Phase 4: User Story 2 — Scheduled automations on the frame itself (P1)

**Goal**: The US1 intents run unattended in personal automations (night dim /
morning wake) — no prompts, ever (FR-800-05) — and the recipe docs ship
(FR-800-10).

**Independent Test**: the CI-testable half is prompt-freedom (pinned app-hosted);
the automation triggers themselves are OS-owned → quickstart manual gate SC-800-02.

- [x] T017 [P] [US2] Red-then-green (app-hosted): unattended-conformance pins in
      `Immich SlideshowTests/FrameIntentGlueTests.swift` — every control intent
      declares `openAppWhenRun == true`, no intent invokes
      `requestConfirmation`/dialog APIs in any service path (recording fake shows
      command calls only), and a fully-parameterized SetBrightness/SelectSource
      resolves without parameter prompts (US2 independent test)
- [x] T018 [P] [US2] Write `docs/automation-recipes.md` — the 22:00 dim+pause and
      07:00 wake+resume recipes step by step on the frame iPad
      (Ask-Before-Running off), the foreground + never-locked operating assumptions
      stated plainly, and the HomeKit boundary: what works today via HA's HomeKit
      Bridge, what iOS does not allow (accessory-event triggers, hub-run intents)
      — US2 acceptance 2, spec's out-of-scope list
- [x] T019 [US2] **Checkpoint**: T017 green in `test_sim`; docs page committed;
      SC-800-02 (overnight cycle) recorded as a pending manual device gate in
      quickstart — not claimable from the simulator

---

## Phase 5: User Story 3 — Select the source and read frame state (P2)

**Goal**: Set Frame Source (options = the saved source library, switch = the HA
select path) and Get Frame State (six whitelisted fields, nothing else) —
FR-800-06/07.

**Independent Test**: package tests over fakes — options equal the injected
library, stale id errors with state untouched, snapshot is structurally incapable
of leaking (SC-800-04).

- [x] T020 [P] [US3] Red tests:
      `Packages/AppIntentsKit/Tests/AppIntentsKitTests/SourceSelectTests.swift` —
      a live id resolves and applies via `selectAlbum(label)` (the recorded call is
      the label, byte-identical to the HA path); a stale id throws
      `.sourceMissing` with zero calls; duplicate labels: first match wins (HA
      parity, contracts § SourceEntity)
- [x] T021 [P] [US3] Red tests:
      `Packages/AppIntentsKit/Tests/AppIntentsKitTests/FrameStateSnapshotTests.swift` —
      from a fully-populated fake `PhotoReport` (bytes, asset/album IDs, region,
      version all planted): the snapshot carries exactly the six whitelisted fields
      and `Mirror`-reflection shows no other stored properties (structural
      whitelist, SC-800-04); `brightnessPercent` rounds 0.0/0.4/1.0 → 0/40/100;
      `isPlaying` maps from `playbackState`
- [x] T022 [US3] Implement `selectSource(id:)` + `frameState()` in
      `Packages/AppIntentsKit/Sources/AppIntentsKit/FrameCommandService.swift` and
      `FrameStateSnapshot.swift` — green T020 + T021
- [x] T023 [US3] Red tests (app-hosted): extend
      `Immich SlideshowTests/FrameIntentGlueTests.swift` — SelectSourceIntent and
      GetFrameStateIntent forward correctly; `GetFrameStateIntent.openAppWhenRun ==
      false`; `SourceEntity` query answers `entities(for:)` and
      `suggestedEntities()` from the registry's `sourceOptions` (same closure the HA
      select list is built from); `FrameStateEntity` mirrors the snapshot
      field-for-field. Expected red = doesn't compile until T024
- [x] T024 [US3] Implement `Immich Slideshow/Intents/SourceEntity.swift`
      (`AppEntity` + query), `Immich Slideshow/Intents/FrameStateEntity.swift`
      (`TransientAppEntity` mirror), the two shells in
      `Immich Slideshow/Intents/FrameIntents.swift`, and the two remaining
      AppShortcuts phrases in `Immich Slideshow/Intents/FrameAppShortcuts.swift`
      (7 total, cap 10) — green T023
- [~] T025 [US3] **Checkpoint**: all AppIntentsKit suites (40) + `FrameIntentGlueTests`
      (13) green via `test_sim` ✅ (2026-07-17); `build_sim` clean ✅. PENDING: the
      simulator spot-check — Set Frame Source shows the saved sources, a switch
      restarts the show exactly like the in-app/HA switch; Get Frame State returns
      the six fields in Shortcuts (folds into the T028 sim pass)

---

## Phase 6: Polish & Ship Gates

- [x] T026 [P] Record the FR-800-xx / SC-800-xx traceability rows in
      `docs/spec-traceability.md` (test names per requirement, manual gates marked)
- [x] T027 Flip `specs/800-app-intents/spec.md` Status to implemented-on-branch and
      update the 800 row in `docs/spec-overview.md`
- [ ] T028 Full XCUITest suite via XcodeBuildMCP `test_sim` before merge (standing
      rule — SwiftUI/app-target changes shipped; broker-toggle flake: rerun
      `BrokerSetupUITests` isolated before suspecting the diff) + the complete
      quickstart Phase-2 gate
- [ ] T029 Manual device checklist from `specs/800-app-intents/quickstart.md`
      (SC-800-03 Siri/Shortcuts discovery, US1 sweep, FR-800-04 honesty drills,
      deleted-source + fresh-reset edges, and the SC-800-02 overnight automation —
      ship gate, real frame iPad)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none — start immediately; T001 and T002 sequential (T002
  references the package from T001).
- **Foundational (Phase 2)**: needs Setup. T003 → T004; T005 parallel to both;
  T006 → T007 → T008 (the hoist consumes `updateAlbums` and the registry from
  T004); T009 gates the phase.
- **US1 (Phase 3)**: needs Phase 2. BLOCKS US2 (US2 automates US1's intents).
- **US2 (Phase 4)**: needs US1 (T017 pins US1's shells; T018 documents them).
- **US3 (Phase 5)**: needs Phase 2 only — independent of US1/US2 at the code level
  (own service verbs, own shells); runs after US2 here purely by priority.
- **Polish (Phase 6)**: needs all desired stories; T026 [P] anytime after US3;
  T028 before merge; T029 is the ship gate on real hardware.

### Parallel Opportunities

- T003 ∥ T005 (different files); T006 can start with T003 (app-hosted vs package).
- T010 ∥ T011 (different test files); T020 ∥ T021 likewise.
- T017 ∥ T018 (test file vs docs page).
- Delegation slices: **A** = T003–T005 (package foundational, Opus subagent),
  **B** = T010–T012 (US1 service, Opus subagent), **C** = T020–T022 (US3 service,
  Opus subagent), docs T018 delegable; T006–T008, T013–T016, T023–T025 and all
  checkpoints are Fable-inline (app target / simulator / entry point).

### Within Each Story

Red test task strictly before its implementation task; package before shells;
shells before phrases; checkpoint last. Commit per task or logical pair
(explicit `git add` paths — new intent error strings will also touch
`Immich Slideshow/Localizable.xcstrings` via Xcode's auto-extraction; stage it
with the shell commits).

---

## Implementation Strategy

**MVP = Phase 1 + 2 + US1 (T001–T016)**: after T016 the frame is scriptable —
pause/resume/next/previous/brightness from Shortcuts and Siri with zero extra
infrastructure. Stop, validate, demo.

**Increment 2 = US2 (T017–T019)**: the unattended-automation guarantees + the
recipe docs — the "HomeKit-ish without HA" story becomes shippable.

**Increment 3 = US3 (T020–T025)**: source select + state read for branching
automations.

**Ship**: Polish gates T026–T028 on the branch; T029 rides the same real-hardware
session as the 900 quickstart checklist (one device day covers both features'
manual gates).
