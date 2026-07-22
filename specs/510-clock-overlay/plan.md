# Implementation Plan: Clock Overlay Renderer

**Branch**: `510-clock-overlay` | **Date**: 2026-07-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/510-clock-overlay/spec.md`, binding to the
clock contract in `specs/500-display-options/spec.md` (FR-500-12/17/18/19, FR-500-03/13,
SC-500-07/08) and `specs/710-ha-full-control/spec.md` (FR-710-01/02).

## Summary

First renderer for the fully-wired clock settings: an ambient-layer `ClockOverlayView` in the
slideshow (three styles — Digits default / Pill / Analog; six places + Random; Room/Cozy
sizes; optional date line) that fades out whenever the chrome is visible. Widens the
`ClockSettings` model in ThemeKit (style/place/size, legacy-corner compatible), makes the
clock settings rows live, and widens the HA selects in HAControlKit. **iOS/iPadOS only** —
ships in the *housekeeping* session; tvOS rendering rides with topic 1000 in the following
session (components stay portable, no tvOS code here).

## Technical Context

**Language/Version**: Swift 6, SwiftUI, `@Observable` MVVM (per constitution)

**Primary Dependencies**: ThemeKit (settings model + store), SlideshowKit (playback state,
photo-advance signal for Random), HAControlKit (entity widening), app target
(`OwnFrame/Slideshow/`) for the view; `View+Compat.swift` glass shims

**Storage**: UserDefaults via `UserDefaultsThemeStore` (non-secret; existing
`theme.clock.*` keys, two new keys) — no secrets involved

**Testing**: Swift Testing on host for ThemeKit/HAControlKit/place-picker logic;
XCUITest (hermetic `--uitest` seams) for rendering/vanish/return; XcodeBuildMCP gates

**Target Platform**: iPadOS/iOS 17+ floor, built against current SDK; Liquid Glass
availability-gated to 26+ via existing shims

**Project Type**: Existing SwiftUI app + local SPM packages (no new package)

**Performance Goals**: No per-second timers; minute-boundary updates only (SC-510-02);
no extra background wakeups

**Constraints**: Clock never co-visible with chrome (SC-500-07); Room digit floor ~12 mm
(SC-500-08); layout-stable minute rollover (tabular numerals); FR-300-33 inset parity

**Scale/Scope**: ~1 new view file, ~4 touched files, 2 packages widened; single session

## Constitution Check

*GATE: evaluated 2026-07-18 pre-Phase-0; re-checked post-design — PASS, no violations.*

- **I. Test-First**: every task below starts red (host tests for model/picker/HA mapping;
  XCUITest for renderer behavior). PASS.
- **II. Modular Isolation**: time source via existing injectable clock patterns
  (`TimelineView` in the view; `SlideshowClock` where logic needs time); Random picker is an
  injectable strategy; no singletons. PASS.
- **III. No Secrets**: clock settings are non-secret UserDefaults; nothing new touches
  keychain/logs. PASS.
- **IV. TLS**: untouched. PASS.
- **V. Platform Boundaries**: overlay only; no display-off tricks. PASS.
- **VI. Verifiable Acceptance**: SC-500-07/08 + SC-510-01/02 are testable; quickstart maps
  each to a scenario. PASS.
- **VII. Plain and Light by Default**: clock stays **off** by default (FR-500-03); everything
  here is opt-in. PASS.

## Project Structure

### Documentation (this feature)

```text
specs/510-clock-overlay/
├── spec.md              # Thin sub-spec binding to 500/710 contracts
├── plan.md              # This file
├── research.md          # Phase 0 decisions
├── data-model.md        # Widened ClockSettings model + HA entities
├── quickstart.md        # Validation scenarios (hermetic)
├── contracts/
│   └── clock-overlay.md # Settings keys, HA entities, UITest seams, a11y ids
└── tasks.md             # /speckit-tasks output
```

### Source Code (repository root)

```text
Packages/ThemeKit/Sources/ThemeKit/
├── ThemeSettings.swift            # WIDEN: ClockStyle, ClockPlace (supersedes ClockCorner),
│                                  #   ClockSize; ClockSettings gains style/place/size
├── UserDefaultsThemeStore.swift   # WIDEN: 2 new keys; place decodes legacy corner raws
└── ClockPlacement.swift           # NEW: place geometry helpers + RandomPlacePicking
                                   #   strategy (pure, host-testable)
Packages/ThemeKit/Tests/ThemeKitTests/
└── ClockSettingsTests.swift       # NEW: decode/persist/legacy-fallback/picker tests

Packages/HAControlKit/Sources/HAControlKit/
├── HAEntityState.swift            # WIDEN: clock_style, clock_size (clock_corner id kept)
├── HADiscovery.swift              # WIDEN: two new selects; options from allCases
└── RemoteControlling.swift        # WIDEN: ThemeSettingsSnapshot style/place/size
Packages/HAControlKit/Tests/...    # WIDEN: discovery + round-trip tests

OwnFrame/Slideshow/
├── ClockOverlayView.swift         # NEW: ambient layer — digits/pill/analog renderers
├── SlideshowView.swift            # TOUCH: ambient layer slot + vanish binding + seams
├── SlideshowSettingsView.swift    # TOUCH: live clock rows (replaces placeholder)
└── SlideshowRemoteControlAdapter.swift  # TOUCH: raw-value mapping for new fields
OwnFrameUITests/
└── ClockOverlayUITests.swift      # NEW: presence/vanish/return/styles/places/persistence
```

**Structure Decision**: No new package. Pure, host-testable logic (model, keys, geometry,
random strategy) lives in ThemeKit; the SwiftUI renderer lives in the app target beside the
chrome it coordinates with, covered by XCUITest per house rules.

## Session Scoping (two-session aim, agreed 2026-07-18)

- **Session 1 — housekeeping**: everything in this plan, after the pending merge train
  (900 → 220, 800) is dealt with. 510 branches from the merged tip (or from 220's tip if the
  train is still open — it only touches files none of the pending branches touch).
- **Session 2 — Apple TV (topic 1000)**: reuses `ClockOverlayView` + widened model as-is;
  adds tvOS size constants, focus-independent ambient layout, and FR-1000-10 pixel-shift.
  This plan deliberately leaves those out; the only 510 obligation is portability (no
  UIKit-only APIs in layout/typography paths, size constants injected not hard-coded).

## Complexity Tracking

No constitution violations; table not needed.
