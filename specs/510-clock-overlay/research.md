# Research — 510 Clock Overlay Renderer

**Date**: 2026-07-18. Most design questions were settled interactively in the Quiet Glass
clock round (mocks artifact) and the 2026-07-18 code inventory; this file records the
remaining implementation decisions. No open NEEDS CLARIFICATION.

## D1 — Model widening: `ClockCorner` → `ClockPlace`

- **Decision**: Introduce `ClockPlace: String, CaseIterable` with cases `topLeading`,
  `topCenter`, `topTrailing`, `bottomLeading`, `bottomCenter`, `bottomTrailing`, `random`.
  The four corner raw values are byte-identical to today's `ClockCorner` raws, so stored
  values and HA retained states decode unchanged. `ClockCorner` is removed (internal enum,
  only ThemeKit/HAControlKit/adapter reference it — all updated in this feature).
  `ClockSettings` gains `style: ClockStyle` (.digits default), `place: ClockPlace`
  (.bottomTrailing default), `size: ClockSize` (.room default); `corner` is renamed `place`.
- **Rationale**: Raw-value stability is the compatibility contract (FR-510-05, FR-710-01);
  a parallel legacy enum would just duplicate four strings.
- **Alternatives**: keep `ClockCorner` + separate `ClockPlacement` wrapper — rejected,
  two types for one concept; migration shim — unnecessary given identical raws.

## D2 — Storage keys

- **Decision**: Keep `theme.clock.isOn`, `theme.clock.corner` (now holding `ClockPlace`
  raws — key name unchanged), `theme.clock.showDate`; add `theme.clock.style`,
  `theme.clock.size`. Unknown/missing values fall back to defaults (FR-500-16 pattern).
- **Rationale**: Renaming the key buys nothing and costs a migration; the store already
  falls back gracefully on unknown raws.

## D3 — HA entities

- **Decision**: `clock_corner` entity id stays (select, options now the six places +
  `random`); add selects `clock_style`, `clock_size`; `clock`, `clock_date` switches
  unchanged. Discovery names: existing "Slideshow Clock Corner" display name becomes
  "Slideshow Clock Place"; new "Slideshow Clock Style", "Slideshow Clock Size". Options
  come from `allCases` raws (FR-710-02), so no schema special-casing.
- **Rationale**: Retained-state compatibility (memory: HA retained state survives
  reinstall); entity-id rename would orphan retained values and automations.

## D4 — Random relocation cadence

- **Decision**: Relocate on the **first photo advance after ≥ 6 minutes** since the last
  relocation (within the specced 5–10 min band). Implemented in an injectable
  `RandomPlacePicking` strategy: `nextPlace(now:current:occupied:)` using the existing
  `SlideshowClock` monotonic time; seedable RNG for deterministic tests. Never repeats the
  current place; filters an `occupied` set (empty today — see D7).
- **Rationale**: Tied to photo advances so the clock never moves mid-photo (FR-510-03);
  6 min ≈ calm but visibly alive; monotonic clock avoids wall-clock-jump artifacts
  (310 lesson).

## D5 — Time display updates

- **Decision**: `TimelineView(.everyMinute)` drives all three styles (digits/pill text and
  analog hand angles — minute hand steps per minute, hour hand creeps with it). Tabular
  numerals (`.monospacedDigit()` / rounded design) keep width stable across rollovers.
- **Rationale**: Zero timer plumbing, no per-second wakeups (SC-510-02), and it is the
  TimelineView-driven pattern the Ken Burns fix already established (in-flight
  `withAnimation` cancellation lesson, memory 9a1e252).

## D6 — Sizes (per-device constants, not screen fractions)

- **Decision** (Room / Cozy, time-digit point size):
  iPhone 92 / 64 pt; iPad 76 / 52 pt. Analog face diameter: iPhone 210 / 150 pt;
  iPad 250 / 180 pt. Pill uses existing `.font(.callout)`-class sizing scaled ~1.2×.
  Chosen by idiom (`UIUserInterfaceIdiom` pad vs phone), constants injected into the view
  so 1000 can supply tvOS values later. Exact values may be visually fine-tuned during
  implementation; the ~12 mm Room floor (SC-500-08: ≥ 74 pt iPhone, ≥ 62 pt iPad) is the
  hard bound, verified in a host test over the constants table.
- **Rationale**: iOS points are near-physical (≈1/163″ iPhone, ≈1/132″ iPad), so per-device
  constants deliver the 1.5 m readability contract directly (FR-500-19 / spec math).

## D7 — Caption-yield rule is vacuous in 510 (by design)

- **Decision**: Today's photo-details card renders only inside the chrome branch, and the
  clock is hidden whenever chrome is visible (FR-500-12) — so clock and caption can never
  be co-visible in this feature. The no-overlap rule (FR-500-18) is implemented as the
  `occupied` filter hook on the place picker plus a layout guard, both fed an empty set
  now; the future ambient-caption feature (Quiet Glass) populates it.
- **Rationale**: Honors the spec contract without building UI for a caption mode that does
  not exist yet; the hook makes the later wiring a one-liner.

## D8 — Ambient layer placement in `SlideshowView`

- **Decision**: New sibling layer between `phaseContent` and the chrome ZStack, using the
  same horizontal/vertical padding constants as `SlideshowChrome` (32/44) and
  `.allowsHitTesting(false)`. Visibility = `clock.isOn && !chromeVisible && phase == playing`,
  with `.opacity` + `.animation(.easeInOut(duration: 0.3))` matching the chrome timing
  (FR-510-02). Hidden in loading/empty/failed phases (chrome is pinned in failed anyway).
- **Rationale**: Sibling-not-child is the structural rule from the design round; inset
  parity preserves FR-300-33 behavior.

## D9 — UITest seams

- **Decision**: `--uitest-clock` (enable, defaults), `--uitest-clock-style=<raw>`,
  `--uitest-clock-place=<raw>`, `--uitest-clock-size=<raw>`, `--uitest-clock-date`;
  parsed where the existing `--uitest-*` args are parsed. A11y ids: `slideshow.clock`
  on the container; style exposed via `slideshow.clock.digits|pill|analog` child ids.
  Random in UITests: launch with `--uitest-clock-place=random` + seeded picker via
  `--uitest-clock-seed=<n>` to make the chosen place deterministic.
- **Rationale**: Mirrors the established seam pattern (`--uitest-info` etc.); full-suite
  XCUITest before merge is a repo rule (SC-510-01).
