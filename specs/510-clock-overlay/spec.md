# Feature Specification: Clock Overlay Renderer

**Feature Branch**: `510-clock-overlay`

**Created**: 2026-07-18

**Status**: Specced (design agreed 2026-07-18 — "Quiet Glass" clock round)

**Input**: Sub-spec of topic 500. The clock's user-facing contract lives in the durable
module spec [500-display-options](../500-display-options/spec.md) — **FR-500-12
(ambient-layer + vanish-on-chrome), FR-500-17 (styles), FR-500-18 (places incl. Random),
FR-500-19 (sizes/readability), FR-500-03 (defaults), FR-500-13 (live settings rows),
SC-500-07/08** — and in [710-ha-full-control](../710-ha-full-control/spec.md) FR-710-01/02
(clock entities). This sub-spec adds only the renderer-specific requirements needed to
implement that contract in the slideshow view. Interactive design record:
Quiet Glass artifact (2026-07-18), clock round.

## Session scoping

Two-session aim (agreed 2026-07-18): this feature ships **iOS/iPadOS only** in the
*housekeeping* session (alongside the 900/800/220 merge train). tvOS rendering of the same
components ships with topic **1000 (Apple TV)** in the following session; this feature must
keep the renderer portable (no UIKit-only dependencies in layout/typography decisions) but
MUST NOT add tvOS targets or tvOS-only code.

## User Scenarios & Testing *(mandatory)*

User stories and acceptance scenarios are those of **500 / User Story 4** (unchanged here).
Renderer-specific test surface:

**Independent Test**: With the hermetic `--uitest` build, launch straight into the stub
slideshow with the clock enabled in each style/place/size combination the seams expose;
verify presence, vanish-on-chrome, return-after-auto-hide, caption yield, and persistence —
without a server, deterministic under XCUITest.

### Edge Cases

- **Minute rollover while visible**: the displayed time updates on the minute boundary
  without visible re-layout jitter (digits width is stable via tabular numerals).
- **Chrome pinned visible** (failed phase pins chrome per 300): the clock stays hidden the
  whole time chrome is pinned; no flicker loop.
- **Random place with details disabled**: with the caption off, Random may use all six
  places; enabling details mid-show re-applies the no-overlap rule on the next relocation.
- **Rotation / size-class change**: the clock re-anchors to its place using the same safe-area
  insets as the chrome (300, FR-300-33); Room/Cozy point sizes are per-device constants and do
  not change with orientation.
- **App relaunch with Random**: Random needs no persisted position; a fresh pick at slideshow
  start is correct behavior.

## Requirements *(mandatory)*

### Functional Requirements

Binding user-facing requirements: **FR-500-12, FR-500-17, FR-500-18, FR-500-19** (plus
FR-500-03/13) and **FR-710-01/02**. Renderer-specific additions:

- **FR-510-01**: The clock MUST update on minute boundaries driven by the view's existing
  time-source patterns (e.g. `TimelineView`), with no per-second timers, no additional
  wakeups while the app is backgrounded, and stable layout across updates (tabular numerals).
  (Ken Burns lesson applies: rendering must not be cancelled by in-flight `withAnimation` —
  see memory 9a1e252.)
- **FR-510-02**: The vanish rule MUST be implemented as an opacity fade of ~0.3 s matching
  the chrome's own transition timing (300, FR-300-15/16), driven by the same
  `chromeVisible` state — a sibling ambient layer, not a child of the chrome branch.
- **FR-510-03**: Random relocation MUST occur only on a photo-advance boundary, at most once
  per configured cadence (5–10 min, plan detail), never landing on the caption's place and
  never repeating the current place. The pick MUST be injectable/deterministic under test.
- **FR-510-04**: The renderer MUST expose stable accessibility identifiers
  (`slideshow.clock`, plus style-distinguishing traits) and hermetic launch seams
  (`--uitest-clock`, `--uitest-clock-style=<raw>`, `--uitest-clock-place=<raw>`,
  `--uitest-clock-size=<raw>`) so XCUITests can drive every combination without settings UI
  navigation.
- **FR-510-05**: The widened `ClockSettings` model (style/place/size) MUST decode legacy
  stored values (four-corner `theme.clock.corner` keys) per FR-500-18 and keep the HA
  `clock.place` entity id + corner raw values per FR-710-01; new enum cases flow into HA
  discovery from `allCases` with no discovery-schema change.
- **FR-510-06**: Digits/Pill/Analog MUST use the shared glass/legibility treatment
  (`View+Compat` shims: Liquid Glass on iOS 26+, existing material fallback pre-26) — no
  clock-only material variants in this feature. (The broader "soft glass" fallback re-tint is
  Quiet Glass scope, not 510.)

### Key Entities

- **ClockOverlayView**: the ambient-layer renderer (styles, places, sizes, date line).
- **ClockSettings (widened)**: see 500 Key Entities; owned by ThemeKit.
- **Random place picker**: injectable strategy choosing among fixed places (FR-510-03).

## Success Criteria *(mandatory)*

Binding: **SC-500-07** (never co-visible with chrome) and **SC-500-08** (Room digit-height
floor; no caption overlap). Renderer-specific:

- **SC-510-01**: Full-suite XCUITest passes with clock scenarios included (per repo rule:
  run full suite before merge), and all existing chrome/info tests stay green unchanged.
- **SC-510-02**: With the clock visible for one hour of simulated playback, no timer churn
  beyond minute updates is observable (no per-second CPU wakeups attributable to the clock).

## Assumptions

- The photo-details caption remains the current `PhotoInfoView` (chrome-coupled) for now;
  the caption-yield rule in this feature therefore only needs to account for the caption
  when it is visible. The full ambient caption ("Always" mode) is Quiet Glass scope, later.
- Analog hand rendering is pure SwiftUI shapes/rotations; no assets needed.
- HAControlKit already round-trips clock settings; only enum widening + one new select per
  new field is expected there.
