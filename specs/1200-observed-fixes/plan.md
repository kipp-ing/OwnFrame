# Implementation Plan: Observed Frame Fixes (1200)

**Branch**: `1200-observed-fixes` | **Date**: 2026-07-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/1200-observed-fixes/spec.md`

## Summary

Three independent fixes on one branch, each realizing an amended module requirement:

1. **Album-tab no-server guidance** (FR-210-30) — split the single `.failed` state in the
   add-source album picker into "no server configured" (guide → server-connection editor) vs
   "network/load error" (existing retryable message). The two branches are already separated in the
   data flow; this is a UI-state split plus one new string.
2. **Ken Burns honors Fit** (FR-500-20, reconciling FR-300-33) — remove the `|| effectiveKenBurns`
   fill-forcing; when fit is Fit, render fitted and drive a **centered zoom with pan = 0**; when fit
   is Fill, unchanged. Applied at both renderer decision sites (iPad + tvOS) and in the motion
   engine (`KenBurnsMotionModifier` pan parameter becomes fit-aware).
3. **Battery + charging telemetry** (FR-710-23) — add two read-only diagnostic entities
   (`battery` sensor, `charging` binary_sensor) to `HAControlKit`, sourced event-driven behind an
   injectable protocol; omitted on non-battery devices (tvOS).

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: SwiftUI, UIKit (battery read), `HAControlKit` (+ `HAControlMQTT`),
`SlideshowKit`, `ThemeKit`, `OnboardingKit`, `ImmichClient`

**Storage**: UserDefaults (server base URL, non-secret settings); Keychain (API key) — read-only here

**Testing**: Swift Testing (`@Test`) host tests for pure logic (`HAControlKit`, drift geometry,
picker view-model state); XcodeBuildMCP simulator for the app targets + UI insets test

**Target Platform**: iPadOS/iOS 17+ (iPad-first, iPhone); tvOS builds and stays compiling

**Project Type**: Mobile app (multi-package SPM workspace + two app targets: `OwnFrame`, `OwnFrameTV`)

**Performance Goals**: Ken Burns motion stays judder-free (existing decode-ahead unchanged); battery
publish is event-driven (no polling loop)

**Constraints**: No secrets in code/UserDefaults/logs; TLS never disabled; battery entities absent
on non-battery devices; existing HA entities unchanged in topic/payload/behavior (FR-710-08)

**Scale/Scope**: 3 fixes, ~4 packages/targets touched, disjoint blast radii

## Constitution Check

*GATE: Must pass before Phase 0. Re-checked after design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Test-First (NON-NEGOTIABLE) | PASS | Each fix leads with a red test: picker VM state test, drift-geometry/`fillsScreen` test, `HAControlKit` discovery+echo test with fake transport + injected battery source. |
| II. Modular Isolation | PASS | Battery read behind an injectable protocol (no `UIDevice` in `HAControlKit`); picker no-server check moved into a view-model for host-testability; drift math already pure. |
| III. No Secrets in Plaintext | PASS | No secret handling changed; battery/charging carry no secrets; picker only *reads* whether a key exists, never its value. |
| IV. Transport-Layer Security | PASS | No transport changes; MQTT stays over TLS; no new network path. |
| V. Respect Platform Boundaries | PASS | Battery is a read-only OS signal; no background claims. tvOS omits battery (no such hardware). |
| VI. Verifiable Acceptance Criteria | PASS | Each story maps to a module SC (SC-210-13 / SC-500-09 + SC-300-13 / SC-710-07), each expressible as a test. |
| VII. Plain and Light by Default | PASS | No default changes; Ken Burns stays opt-in; honoring Fit is *more* faithful to the user's choice. |

**Gate result: PASS — no violations, Complexity Tracking not required.**

## Project Structure

### Documentation (this feature)

```text
specs/1200-observed-fixes/
├── spec.md              # Work-order bundle (done)
├── plan.md              # This file
├── research.md          # Phase 0 — the three design decisions + geometry note
├── data-model.md        # Phase 1 — BatteryReading + picker load-state model
├── quickstart.md        # Phase 1 — how to verify each fix
├── contracts/           # → reuses specs/710-*/contracts/ha-mqtt-entities.md (amended)
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root) — files in scope per fix

```text
# Fix 1 — Album-tab no-server guidance (OnboardingKit + app UI)
OwnFrame/Slideshow/SourceLibraryView.swift        # AddAlbumPicker.task: split .failed → .noServer / .failed
OwnFrame/Slideshow/AlbumBrowserView.swift         # same distinction for the runtime browser
OwnFrame/Localizable.xcstrings                     # new English string(s): "add a server / check connection"
Packages/OnboardingKit/Sources/OnboardingKit/…    # host-testable no-server predicate (VM or helper)
Packages/OnboardingKit/Tests/…                     # red test first

# Fix 2 — Ken Burns honors Fit (SlideshowKit + both renderers)
Packages/SlideshowKit/Sources/SlideshowKit/KenBurnsMotionModifier.swift  # pan becomes fit-aware (0 when Fit)
Packages/SlideshowKit/Sources/SlideshowKit/KenBurnsDrift.swift           # keep floor math; pan suppression seam
OwnFrame/Slideshow/SlideshowView.swift            # fillsScreen: drop `|| effectiveKenBurns`; pass fit into motion
OwnFrameTV/TVSlideshowView.swift                  # mirror the same change
Packages/SlideshowKit/Tests/…                     # red tests: fillsScreen honors fit; pan=0 under Fit

# Fix 3 — Battery + charging telemetry (HAControlKit + adapters)
Packages/HAControlKit/Sources/HAControlKit/HAEntityState.swift    # + .battery, .charging; read-only classification
Packages/HAControlKit/Sources/HAControlKit/HATopics.swift         # component(for:) → sensor / binary_sensor
Packages/HAControlKit/Sources/HAControlKit/HADiscovery.swift      # device_class/unit/state_class + names
Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift  # echo(_:) emits battery/charging
Packages/HAControlKit/Sources/HAControlKit/PhotoReport.swift OR new BatteryReporting protocol  # injectable seam
OwnFrame/Slideshow/SlideshowRemoteControlAdapter.swift  # real UIDevice battery read + notifications
OwnFrame/OwnFrameApp.swift                        # enable battery monitoring; add entities to enabledEntities
OwnFrameTV/TVRemoteControlAdapter.swift           # returns nil (no battery); entities omitted
Packages/HAControlKit/Tests/…                     # red tests: discovery payload + echo + omit-on-no-battery
```

**Structure Decision**: Multi-package SPM workspace with two app targets. Durable requirements live
in the module specs (210/500/300/710); this feature folder is the cross-cutting work order. Each fix
is isolated to its package(s) so the three can be implemented and reviewed in parallel with no merge
contention (disjoint file sets).

## Design Notes (per fix)

### Fix 1 — load-state split
`AddAlbumPicker.task` (`SourceLibraryView.swift`) already branches: `makeServerAPI()` returning
`nil` = no server (no network call), `catch` = network error. Introduce a `noServer` phase (or an
associated message on `.failed`) and render an "add a server" `ContentUnavailableView` whose action
opens the server-connection editor (FR-210-29). Lift the "is a server configured?" predicate into an
`OnboardingKit` helper/VM so it is host-testable without the view. Mirror in `AlbumBrowserView`.

### Fix 2 — pan-suppressed zoom under Fit
`fillsScreen` = `themeStore.settings.fit == .fill` (drop `|| effectiveKenBurns`). Under Fit the image
renders `scaledToFit`; the motion modifier receives `pan: 0` (or a `fit`-flag) so it applies a
centered `scaleEffect` only — the letterbox shrinks as it zooms, never revealing a side gap.
`KenBurnsDrift.floorScale`/`startScale` are unchanged (a centered zoom from 1.10→~1.0 with no offset
is safe on a fitted image). Under Fill, pass the existing pan (16 iPad / 24 tvOS) — no regression.
Chrome-inset stability (FR-300-33/SC-300-13) holds because framing no longer changes when toggling
Ken Burns.

### Fix 3 — read-only battery diagnostics
New `BatteryReporting` protocol (`level: Int?` 0–100, `isOnPower: Bool`, plus a change signal), so
`HAControlKit` never imports UIKit. App adapter implements it via `UIDevice.current` with
`isBatteryMonitoringEnabled = true`, observing `batteryLevelDidChange`/`batteryStateDidChange`.
`charging` ON = `batteryState ∈ {.charging, .full}`. `battery`/`charging` are classified read-only
(free telemetry, FR-1100-03a) and only added to `enabledEntities` when the adapter reports a battery
present → tvOS omits them. Discovery adds `device_class`/`unit_of_measurement`/`state_class` (new
keys for this codebase) per the amended `ha-mqtt-entities.md` contract.

## Complexity Tracking

*No constitution violations — section intentionally empty.*
