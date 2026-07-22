# Quickstart — 510 Clock Overlay validation

**Date**: 2026-07-18. All scenarios are hermetic (no server): host tests via `swift test`,
app scenarios via the `--uitest` stub build on the simulator through XcodeBuildMCP.
Sim notes: pin `simulatorId` only; run whole test classes (single-`@Test` false-green
gotcha); full XCUITest suite before merge.

## Prerequisites

- Branch `510-clock-overlay`; XcodeBuildMCP session defaults set (project, scheme
  `OwnFrame`, an iOS 26.x iPad simulator id; repeat key scenarios once on the
  iOS 17.5 iPad for the material fallback).

## Host (Swift Testing)

1. **ThemeKit model** — `swift test --package-path Packages/ThemeKit`:
   decode legacy corner raws into `ClockPlace`; unknown raws → defaults; new keys
   persist/round-trip; size-constants table meets the Room floor (≥ 74 pt iPhone /
   ≥ 62 pt iPad); `RandomPlacePicking`: no move before cadence, moves on first advance
   after cadence, never repeats current, respects `occupied`, deterministic under seed.
2. **HAControlKit** — `swift test --package-path Packages/HAControlKit`:
   discovery contains `clock_style`/`clock_size` selects and widened `clock_corner`
   options; snapshot round-trip carries style/place/size; inbound invalid option ignored.

## Simulator (XCUITest, hermetic)

3. **Presence & default styling** — launch
   `--uitest --uitest-slideshow --uitest-clock`: `slideshow.clock` exists with
   `slideshow.clock.digits`; screenshot gate on 26.x (glass) and 17.5 (fallback).
4. **Vanish/return (SC-500-07)** — same launch; tap to reveal chrome → clock disappears
   while `slideshow.chrome.playPause` is hittable; wait past 4.5 s auto-hide → clock back.
   With `--uitest-assets-fail=…` (chrome pinned in failed phase): clock stays hidden.
5. **Styles & places sweep** — parameterized launches over
   `--uitest-clock-style=pill|analog` and representative places (`topCenter`,
   `bottomLeading`, `bottomCenter`): correct child id, correct screen third, insets match
   chrome padding; `--uitest-clock-date` shows the date line for digits/pill and not for
   analog.
6. **Random determinism** — `--uitest-clock-place=random --uitest-clock-seed=1`: place is
   the seeded expectation; swipe several advances within cadence → no move.
7. **Persistence (FR-500-05)** — enable via live settings rows (scenario: settings sheet →
   set style/place/size/date), relaunch without seams, verify the rows and the overlay
   reflect the choices.
8. **Minute rollover** — with a mocked/near-boundary time or a ≤ 70 s wait: time text
   updates, layout width stable (no reflow of siblings). *(Manual-observation fallback:
   simulator video + frame diff.)*

## Gates

- All host suites green; full XCUITest suite green (SC-510-01) on 26.x; scenario 3 also on
  17.5. Build of the app target green. No new per-second timers (code review + Instruments
  spot-check if in doubt, SC-510-02).
