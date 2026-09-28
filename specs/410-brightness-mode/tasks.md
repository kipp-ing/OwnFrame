# Tasks: Brightness Mode (410)

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

**Tests are REQUIRED** (Constitution I): each implementation task follows a red test.
Phases 2–3 (PowerKit) and Phase 4 (HAControlKit) touch disjoint packages and run in parallel.

## Phase 1: Baseline

- [x] T001 Green baseline: `swift test` in PowerKit and HAControlKit.

## Phase 2: PowerKit foundations

- [x] T002 [P] Red tests: `NightWindow.contains` — same-day window, across midnight, start == end
  (no window), disabled, DST/time-zone evaluated on wall-clock minutes. → implement `NightWindow`.
- [x] T003 [P] Red tests: `BrightnessSettings` defaults (Automatic, night off, night level 0.0,
  night level clamped to 0.0…0.3) and `UserDefaultsBrightnessStore` round trip incl.
  `preNightBaseline`. → implement settings + stores.
- [x] T004 Red tests: `PowerManager.restore(to:)` (animated write, exit restore no longer fires),
  `deactivate(restoringTo:)`, `isRamping`. → implement (existing PowerManager tests stay green).

## Phase 3: BrightnessController (US1, US2, US3-core, US4)

- [x] T005 US1 red: Automatic — activate, tick ×N with a drifting screen, background/foreground,
  exit: zero writes (SC-410-01). → controller skeleton + target derivation.
- [x] T006 US2 red: Fixed — activate applies the preset; drift is re-applied within one tick
  (SC-410-02); no write while a ramp runs; background stops the loop; relaunch re-applies
  (SC-410-03); switching to Automatic restores the session baseline once and then stops
  (FR-410-10). → implement hold + mode events.
- [x] T007 US3 red: remote level holds for the session and leaves the store untouched
  (SC-410-04); remote `auto` stops writes; remote `fixed` applies the preset; in-app control
  ends an override; a new controller (relaunch) ignores the old override. → implement.
- [x] T008 US4 red: window start fades to the night level; end returns to Fixed preset / restores
  the pre-night baseline in Automatic (SC-410-08); launch inside the window starts at night;
  relaunch inside the window then window end restores the remembered pre-night value, never the
  night level (SC-410-09); remote level inside the window holds until the end, daytime remote is
  replaced at start (SC-410-10); launch outside the window with a stale pre-night baseline
  restores it once. → implement window events + pre-night baseline.
- [x] T009 US4 red: peek — tap at night shows the day level; back to the holder within 70 s of
  the last tap; repeated taps extend; peek during a remote level returns to the remote level
  (SC-410-11); tap by day does nothing. → implement.
- [x] T010 Red: reported brightness — immediate for held levels; Automatic reports only on
  ≥ 0.05 and ≥ 5 s apart (FR-410-09). → implement.

## Phase 4: HAControlKit (delegated, parallel to Phases 2–3)

- [x] T011 Red tests + implementation: `BrightnessModeControlling` protocol; `brightness_mode`
  select (`auto`/`fixed`, gated control), `night_window` switch (gated control), `night_active`
  binary_sensor (free, read-only); discovery, state echo on change, command routing, omitted
  without a source; existing entities unchanged.

## Phase 5: App wiring

- [x] T012 Adapter: `setBrightness` → `remoteSetLevel`; `brightness` = `reportedBrightness`
  (SC-410-05, drop the hard-coded 1.0); `BrightnessModeControlling` conformance; echo on
  reported/mode/night changes. Update `SlideshowRemoteControlAdapterTests` first (red).
- [x] T013 Composition: one `BrightnessController` per `PowerManager` in `OwnFrameApp`
  (production + `--uitest` factories); `SlideshowView` lifecycle calls go through the
  controller; chrome tap calls `userTapped()`; coordinator gets the mode source.
- [x] T014 Settings UI: Automatic/Fixed picker; level slider only in Fixed with the
  covered-sensor hint (FR-410-11, positive copy); Night section (toggle, from/to, night level).
  EN + DE strings in the catalog. Simulator screenshot check.
- [x] T015 Gate: host suites (PowerKit, HAControlKit, AppIntentsKit), iOS app build + unit tests
  (OwnFrameTests) and SettingsUITests via XcodeBuildMCP; tvOS build still compiles.

## Phase 6: Records

- [x] T016 product-facts.yaml: UNATT-02 (level remembered in Fixed; Automatic default), new fact
  for the night window, REMOTE-05 (mode select, night switch); run `check-facts.py`.
- [x] T017 Spec Status + hitl (open device items queued in hitl): device checks SC-410-02 (device half), SC-410-06 (#91 rerun),
  SC-410-07; Jan's calls (P-5, full-text review). Close #91 once SC-410-06 passes on device.

## Build notes (2026-09-28)

- The adversarial review found three controller races (a ramp outliving a newer Automatic event;
  a pre-night value surviving an exit after a hand-back; a tick loop restarted after exit) — each
  pinned by `BrightnessControllerRaceTests` and fixed (`applied` recorded before awaiting, the
  pre-night value consumed on every exit, a restore that knows about newer writes).
- The device run found finding 11 (software dimming breaks the hold) — fixed in
  `UIScreenController` (only below 0.02).
- The DEBUG `BrightnessTraceSeam` (`--brightness-fixed`, `--brightness-trace`) and
  `.claude/scripts/brightness-probe/ownframe-cycle.sh` are the device rig for SC-410-02/07.
