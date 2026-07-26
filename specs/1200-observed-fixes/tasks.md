# Tasks: Observed Frame Fixes (1200)

**Feature**: `1200-observed-fixes` | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

**Status (2026-07-26)**: the feature is **merged to main via PR #39** (impl commit `4d1f3de`,
2026-07-22). All three user stories shipped; the boxes below are ticked from artifacts in the
merged tree. Two implementation deviations, both intentional: T009 landed as a new shared
`Packages/SlideshowKit/Sources/SlideshowKit/KenBurnsFraming.swift` (host-testable) instead of an
edit inside `KenBurnsMotionModifier.swift`, and T021 omits the tvOS battery entities by passing no
`BatteryReporting` source to `HAControlCoordinator` in `OwnFrameTV/TVRootView.swift` (the
coordinator skips battery entities when the source is absent) rather than by adding a
`hasBattery == false` adapter. **Genuinely open:** T012 (no XCUITest asserts chrome insets across
*both* fit modes — `SlideshowChromeUITests.testChromeInsetsStableAcrossOrientationAndKenBurns`
predates 1200 and covers landscape Ken-Burns-on/off only), T024, and T025 (conditional, no
`docs/testing.md` note was added). T001/T007/T013 were one-off process gates run during the
feature with no artifact in the repo; T022/T023 are ticked against the measured post-merge gate
(2026-07-25: host suites green, full iOS suite 163/0/5). The perceived-motion and live-MQTT
device checks are not yet listed in `docs/manual-verification.md`.

**Tests are REQUIRED** — Constitution Principle I (Test-First, NON-NEGOTIABLE): every implementation
task is preceded by a demonstrably-red test. Host tests via `swift test`; app-target + UI via
XcodeBuildMCP.

**Parallelism**: The three user stories touch **disjoint file sets** (OnboardingKit/app-UI ·
SlideshowKit+renderers · HAControlKit+adapters), so US1, US2, US3 can be implemented concurrently by
separate agents after Phase 1. `[P]` marks tasks parallelizable within a story (different files).

---

## Phase 1: Setup (baseline)

- [ ] T001 Establish a green baseline before any change: run host tests for `OnboardingKit`, `SlideshowKit`, `HAControlKit` (`swift test`) and build `OwnFrame` + `OwnFrameTV` via XcodeBuildMCP; record the pre-change pass/fail so regressions are attributable.

## Phase 2: Foundational

No foundational prerequisites. The three user stories are independent and introduce no shared
infrastructure — proceed directly to the story phases.

---

## Phase 3: User Story 1 — Album-tab no-server guidance (Priority: P1)

**Goal**: The Album tab distinguishes "no server configured" (guide → server-connection editor) from
a network/load error, instead of a single "Couldn't load albums".

**Independent test**: With a shared-link-only setup, opening the Album tab shows an add-a-server
prompt that routes to the connection editor; with a configured-but-unreachable server it shows the
retryable "Couldn't load albums" (SC-210-13).

- [x] T002 [P] [US1] Red: host test for the "server configured" predicate in `Packages/OnboardingKit/Tests/OnboardingKitTests/` — asserts `false` when base URL and/or API key is missing, `true` only when both are present.
- [x] T003 [US1] Add the host-testable `serverConfigured` predicate/helper (reads `ConfigStore.loadBaseURL()` presence + `KeychainAPIKeyStore.read()` presence) in `Packages/OnboardingKit/Sources/OnboardingKit/` — make T002 green.
- [x] T004 [US1] Add a `noServer` load phase and render an "Add a server" `ContentUnavailableView` whose action opens the server-connection editor (FR-210-29) in `OwnFrame/Slideshow/SourceLibraryView.swift` (`AddAlbumPicker`), keeping the `catch` path on the existing `.failed` message.
- [x] T005 [P] [US1] Add the new English string(s) for the no-server guidance ("Add a server or check your connection" + action label) in `OwnFrame/Localizable.xcstrings`.
- [x] T006 [US1] Apply the same no-server vs network-error distinction in `OwnFrame/Slideshow/AlbumBrowserView.swift` (runtime album browser) so the two surfaces stay consistent (FR-210-27).
- [ ] T007 [US1] Simulator verify via XcodeBuildMCP per `quickstart.md` Fix 1: no-server setup → add-a-server routing; configured + unreachable → retryable error.

**Checkpoint**: US1 independently shippable (MVP).

---

## Phase 4: User Story 2 — Ken Burns honors Fit (Priority: P2)

**Goal**: With fit Fit, Ken Burns keeps the whole photo visible with a centered zoom (pan suppressed),
never switching to Fill; with fit Fill, motion is unchanged.

**Independent test**: `fillsScreen` is `false` under Fit regardless of Ken Burns; Ken Burns pan input
is `0` under Fit and `basePan` under Fill (SC-500-09); chrome insets pixel-identical KB on/off in both
fit modes (SC-300-13).

- [x] T008 [P] [US2] Red: host tests in `Packages/SlideshowKit/Tests/SlideshowKitTests/` — `fillsScreen == false` when `fit == .fit` (KB on and off) and `true` when `fit == .fill`; Ken Burns pan input `== 0` under Fit, `== basePan` under Fill.
- [x] T009 [US2] Make the Ken Burns pan input fit-aware (pan `0` under Fit; centered zoom only) in `Packages/SlideshowKit/Sources/SlideshowKit/KenBurnsMotionModifier.swift` (and any `KenBurnsDrift.swift` seam) — leave the scale envelope unchanged; make T008 green.
- [x] T010 [US2] Remove `|| effectiveKenBurns` from `fillsScreen` and pass the fit-aware pan into `.kenBurnsMotion` in `OwnFrame/Slideshow/SlideshowView.swift`.
- [x] T011 [P] [US2] Mirror the identical change (`fillsScreen` + fit-aware `contentMode`/pan) in `OwnFrameTV/TVSlideshowView.swift`.
- [ ] T012 [US2] Red→green UI inset regression: XCUITest asserting chrome edge insets are pixel-identical Ken-Burns-on vs off in **both** Fit and Fill, portrait + landscape (SC-300-13), in the `OwnFrame` UI test target.
- [ ] T013 [US2] Build `OwnFrame` + `OwnFrameTV` via XcodeBuildMCP and run the iOS suite green; record the Framepad perceived-motion check as a manual gate (out of automated scope).

**Checkpoint**: US2 independently verifiable (host + UI regression); perceived motion is a device gate.

---

## Phase 5: User Story 3 — Battery + charging telemetry (Priority: P3)

**Goal**: Publish `battery` (%) and `charging` diagnostic entities as free, event-driven, read-only
telemetry; omit both on non-battery devices (tvOS).

**Independent test**: With a fake `MQTTTransport` + injected `BatteryReporting`, discovery/echo for
`battery`/`charging` match the contract; when `hasBattery == false` neither entity is announced;
both publish in telemetry-only (unentitled) mode (SC-710-07).

- [x] T014 [P] [US3] Red: host tests in `Packages/HAControlKit/Tests/HAControlKitTests/` — `battery` discovery has `device_class: battery`, `unit_of_measurement: "%"`, `state_class: measurement`, `entity_category: diagnostic`, no `command_topic`; `charging` is `binary_sensor` with `device_class: battery_charging` + `payload_on/off`; echo publishes `level 87 → "87"` and `isOnPower → "ON"/"OFF"`; `hasBattery == false` omits both from announce; both publish under telemetry-only mode.
- [x] T015 [US3] Add `BatteryReading` + `BatteryReporting` protocol (`hasBattery`, `current`, change signal) in a new `Packages/HAControlKit/Sources/HAControlKit/BatteryReporting.swift` (UIKit-free).
- [x] T016 [US3] Add `.battery` and `.charging` cases to `HAEntity` and classify them read-only (free telemetry) in `Packages/HAControlKit/Sources/HAControlKit/HAEntityState.swift`.
- [x] T017 [US3] Map `.battery → sensor` and `.charging → binary_sensor` in `component(for:)` in `Packages/HAControlKit/Sources/HAControlKit/HATopics.swift` (adds the first `binary_sensor` component).
- [x] T018 [US3] Add discovery fields (`device_class`, `unit_of_measurement`, `state_class`, `payload_on/off`) and human names for both entities in `Packages/HAControlKit/Sources/HAControlKit/HADiscovery.swift`.
- [x] T019 [US3] Emit battery/charging state in `echo(_:)` and omit both entities from announce when `hasBattery == false` in `Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift` — make T014 green.
- [x] T020 [US3] Implement `BatteryReporting` over `UIDevice` (set `isBatteryMonitoringEnabled = true`, observe `batteryLevelDidChange`/`batteryStateDidChange`, `charging` ON for `.charging`/`.full`) in `OwnFrame/Slideshow/SlideshowRemoteControlAdapter.swift`, and enable monitoring + add the entities to `enabledEntities` in `OwnFrame/OwnFrameApp.swift`.
- [x] T021 [P] [US3] tvOS adapter reports `hasBattery == false` (entities omitted) in `OwnFrameTV/TVRemoteControlAdapter.swift`.
- [x] T022 [US3] Run `HAControlKit` host tests green and build both app targets via XcodeBuildMCP.

**Checkpoint**: US3 independently verifiable with fakes; live MQTT/HA is a device-day gate.

---

## Phase 6: Polish & Cross-Cutting

- [x] T023 Full sweep: host tests for `OnboardingKit` + `SlideshowKit` + `HAControlKit` green; full iOS XCUITest suite via XcodeBuildMCP green; `OwnFrame` + `OwnFrameTV` build — confirm no regressions vs the T001 baseline.
- [ ] T024 [P] Run `/speckit-analyze` for cross-artifact consistency (spec ↔ plan ↔ tasks ↔ amended module FRs 210/500/300/710).
- [ ] T025 [P] If new reusable test seams warrant it, note the battery fake, the `fillsScreen`-honors-Fit case, and the no-server predicate in `docs/testing.md`.
- [x] T026 Verify no secrets on the touched surfaces (Fix 1 reads only key *presence*; Fixes 2/3 touch none) in code/UserDefaults/logs; commit the branch with the spec + plan + implementation.

---

## Dependencies & Execution Order

- **Phase 1 (T001)** precedes everything.
- **US1, US2, US3 are mutually independent** (disjoint files) — assign one agent per story to run in
  parallel (the competing-agents phase).
- **Within each story**: the red test (`T002` / `T008` / `T014`) precedes its implementation tasks;
  the build/verify task closes the story.
- **Phase 6** runs after all three stories land.

## Parallel Execution Example

```
# After T001, three agents run concurrently:
Agent A → US1: T002 → T003 → T004 → {T005 ∥ T006} → T007
Agent B → US2: T008 → T009 → {T010 ∥ T011} → T012 → T013
Agent C → US3: T014 → T015 → T016 → T017 → T018 → T019 → T020 ∥ T021 → T022
# Then Phase 6 (T023–T026) once A, B, C are green.
```

## MVP Scope

**User Story 1 alone** (P1, T001–T007) is a shippable ease-of-use polish improvement and the minimal
first increment.
