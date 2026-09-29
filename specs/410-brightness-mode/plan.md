# Implementation Plan: Brightness Mode (410)

**Branch**: `main` (single work package) | **Date**: 2026-09-28 | **Spec**: [spec.md](./spec.md)

## Summary

A new policy layer, `BrightnessController` (PowerKit), decides **whether and when** OwnFrame writes
brightness; `PowerManager` (400) keeps the mechanics (keep-awake, clamping, soft dim, baseline,
foreground gating). The controller is built on three ideas:

1. **Target, not writes.** At any moment the controller has one *target*: `.automatic` (write
   nothing) or `.level(x)` (hold x). The target is derived from the **event holder** (D-410-5,
   last event wins) plus the settings.
2. **One writer.** A 1 s tick is the only place that writes outside an explicit event: it
   re-applies a held level when the read value drifted (FR-410-04/05), crosses night-window
   edges, and ends a peek. Source switches, playback and view lifecycle never write (#91).
3. **Automatic = hands off.** Returning to Automatic restores once (the pre-night brightness if
   one is remembered, else the session baseline if the app wrote this session) and then stops.

## Technical Context

**Language/Version**: Swift 6 · **UI**: SwiftUI · **Architecture**: MVVM, `@Observable`

**Packages touched**: `PowerKit` (policy + store, host-tested), `HAControlKit` (three entities,
host-tested), app target `OwnFrame` (wiring, settings UI, tap peek). `AppIntentsKit` unchanged —
the intents already go through `FrameIntentSurface.brightness`/`setBrightness`, which the adapter
now routes to the controller. **tvOS unchanged** (deferred policy): `OwnFrameTV` keeps using
`PowerManager` directly; every `PowerManager` API it uses stays source-compatible.

**Storage**: UserDefaults — one JSON-encoded `BrightnessSettings` value plus the optional
pre-night baseline (FR-410-12, FR-410-17). Not secrets.

**Testing**: Swift Testing host tests in PowerKit (fake screen with iOS-like drift, injected
wall clock, manual tick) and HAControlKit (fake transport); app target via XcodeBuildMCP.

## Design

### PowerKit

- `BrightnessSettings` (Codable, Equatable): `mode: .automatic | .fixed` (default automatic),
  `preset: Double` (default 0.6), `night: NightWindow`.
- `NightWindow`: `isEnabled` (default false), `startMinute`/`endMinute` (minutes after local
  midnight, default 23:00–07:00), `level` (default 0.0 = the darkest the frame shows: iOS
  `UIScreenController` already sets `wantsSoftwareDimming`, so 0.0 is hardware minimum plus
  software dim — FR-410-13). The night level is bounded to 0.0…`NightWindow.maxLevel` (0.3).
  `contains(_ date:, calendar:)` evaluates local wall-clock minutes on every call — across
  midnight, DST and time-zone changes; `start == end` means no window.
- `BrightnessSettingsStore` protocol (`settings`, `preNightBaseline`) with
  `UserDefaultsBrightnessStore` and `InMemoryBrightnessStore`.
- `PowerManager` gains three small, backward-compatible seams: `isRamping`,
  `restore(to:)` (animated write that marks the session as "not changed" — used when handing
  back to Automatic, FR-410-10), and `deactivate(restoringTo:)` (exit restore to a chosen value).
- `BrightnessController` (`@MainActor @Observable`), owning the policy:
  - **Holder**: `.setting` (the in-app mode/preset), `.night`, `.remote(.level(x) | .automatic |
    .preset)`. Target: setting → automatic or preset; night → night level; remote → as given.
  - **Events** (each sets the holder and applies the new target with a soft dim): in-app
    `setMode`/`setPreset` (persisted, D-410-2, FR-410-06); remote `remoteSetLevel` /
    `remoteSetMode` (session only, FR-410-07); window start/end, detected by the tick as a change
    of `NightWindow.contains(now)` (FR-410-14); `setNightWindow` / `remoteSetNightWindowEnabled`
    (re-derive from the time, like a launch).
  - **Launch** (`activate`): derive from the time (FR-410-15) — inside the window → `.night`,
    outside → `.setting`; a remembered pre-night baseline found outside the window is a missed
    window end (crash overnight) and is restored once in Automatic.
  - **Foreground return**: the holder stays (an override survives a short background); a window
    edge crossed while backgrounded is picked up by the next tick, which compares against the
    last seen window state. This is how "derive from the time" and "last event wins" agree.
  - **Pre-night baseline** (FR-410-17): captured when night starts while the target is
    Automatic, persisted, only if none is stored (a relaunch inside the window must not capture
    the night level — SC-410-09). Consumed (restored + cleared) at window end in Automatic, and
    at slideshow exit (the exit restore uses it; re-entry at night then captures afresh).
  - **Peek** (FR-410-18): `userTapped()` while the window is active shows the *day* target
    (preset, or the pre-night/session baseline in Automatic) until `now + 60 s`; repeated taps
    extend it; the tick fades back to the current holder's target. A peek is not an event.
  - **Hold** (FR-410-04): on each foreground tick, if the target is a level, no ramp is running
    and `|read − target| > 0.025` (half of iOS's 0.05 step), write the target unanimated.
  - **Report** (FR-410-09): `effectiveBrightness` = the held target, or the read value in
    Automatic. `reportedBrightness` (observable, what HA/intents echo) follows it immediately for
    held levels, and in Automatic only on a change ≥ 0.05 and at most every 5 s.
  - **Tick loop**: a `Task` sleeping 1 s on the injected `PowerClock`, started on activate /
    foreground, cancelled on background / exit. Tests drive `tick()` directly.

### HAControlKit (delegated slice, see tasks Phase 4)

`BrightnessModeControlling` (optional, like `BatteryReporting`): effective mode (`auto`/`fixed`),
`isNightActive`, `isNightWindowEnabled`, `setBrightnessMode`, `setNightWindowEnabled`, change
callback. Entities: `brightness_mode` select (control, gated), `night_window` switch (control,
gated), `night_active` binary_sensor (read-only, free), `brightness_mode_status` enum sensor
(read-only, free — the effective mode, FR-410-08). Absent when no source is injected (tvOS).

### App

`SlideshowRemoteControlAdapter` routes `setBrightness` to `controller.remoteSetLevel`, reports
`controller.reportedBrightness` (no more hard-coded `initialBrightness` 1.0, SC-410-05), implements
`BrightnessModeControlling`, and echoes on the controller's reported changes. `SlideshowView`
calls the controller's lifecycle (it forwards to `PowerManager`) and `userTapped()` on the
chrome-reveal tap. Settings: a Brightness section with an Automatic/Fixed picker, the level
slider only in Fixed (with the covered-sensor hint, FR-410-11), and a Night section (toggle,
from/to pickers, night level slider). Strings in the String Catalog (EN + DE).

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Test-First | PASS | Every controller rule gets a red host test first (fake drifting screen, injected clock). |
| II. Modular Isolation | PASS | Policy in PowerKit behind `ScreenControlling`/`PowerClock`/store protocols; HA behind an optional protocol. |
| III. No Secrets | PASS | Only brightness settings in UserDefaults (FR-410-12). |
| IV. TLS | PASS | No transport change. |
| V. Platform Boundaries | PASS | Tick loop foreground-only; no claim of reading the light sensor (FR-410-11, finding 4). |
| VI. Verifiable | PASS | SC-410-01…06, 08…11 are host tests; SC-410-07 is a device check (hitl). |
| VII. Plain by Default | PASS | Default is Automatic and the night window is off — nothing is written unless chosen. |

## Decisions made in planning

- **P-1 Foreground return keeps the holder** (see Launch/Foreground above). FR-410-15's "derive
  from the time" is satisfied at launch; on foreground return a crossed window edge counts as the
  event it is.
- **P-2 Hold tolerance 0.025**, tick 1 s (finding 3). The loop skips while a soft dim runs.
- **P-3 Night level bounds** 0.0…0.3, default 0.0. **Peek** 60 s.
- **P-4 Automatic reporting** ≥ 0.05 change and ≥ 5 s apart.
- **P-5 Mode telemetry**: the effective mode reaches HA through the gated `brightness_mode`
  select and, free for every frame, a fourth read-only entity `brightness_mode_status` (enum
  sensor, diagnostic, re-echoed on every mode change in both modes) — closes FR-410-08's
  "telemetry of the effective mode stays free" (was an open gap for Jan, hitl §2b).
- **P-6 Exit restore target**: pre-night baseline if remembered, else the session baseline — and
  only if the app wrote (FR-400-11 unchanged otherwise).
