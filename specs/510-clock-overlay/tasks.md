# Tasks: Clock Overlay Renderer (510)

**Input**: `specs/510-clock-overlay/` — plan.md, research.md, data-model.md,
contracts/clock-overlay.md, quickstart.md. Binding contract: 500 US4 + FR-500-12/17/18/19,
SC-500-07/08; FR-710-01/02; renderer FR-510-01…06.

**Organization**: single user story (500 US4 — "Optional clock overlay"), so phases are
Setup → Foundational (ThemeKit model, blocks everything) → US4 slices (renderer → settings
rows → HA) → Polish/gates. TDD per task: every implementation task names the red test that
precedes it. iOS/iPadOS only (session scoping in plan.md).

## Phase 1: Setup

- [ ] T001 Verify baseline green on `510-clock-overlay`: app target builds and full test
      suite passes via XcodeBuildMCP (26.x iPad sim), `swift test` green for
      `Packages/ThemeKit` and `Packages/HAControlKit`. No code changes.

## Phase 2: Foundational — ThemeKit model widening (blocks all US4 slices)

- [ ] T002 Red tests in `Packages/ThemeKit/Tests/ThemeKitTests/ClockSettingsTests.swift`:
      `ClockStyle`/`ClockPlace`/`ClockSize` cases + raw values per data-model.md; widened
      `ClockSettings` defaults (off · digits · bottomTrailing · room · no date); legacy
      corner raws decode into `ClockPlace`; unknown raws → field defaults; new keys
      `theme.clock.style`/`theme.clock.size` persist and round-trip; key name
      `theme.clock.corner` unchanged for place.
- [ ] T003 Green: widen `Packages/ThemeKit/Sources/ThemeKit/ThemeSettings.swift`
      (`ClockStyle`, `ClockPlace` superseding `ClockCorner`, `ClockSize`, `ClockSettings`
      fields `style`/`place`/`size`) and
      `Packages/ThemeKit/Sources/ThemeKit/UserDefaultsThemeStore.swift` (two new keys,
      place load/persist on the existing key). Mechanical `corner` → `place` rename across
      packages/app until everything compiles; all pre-existing suites stay green.
- [ ] T004 Red tests (same test file): `RandomPlacePicking` — no relocation before the
      6-minute cadence; relocates on first call after cadence; never returns `current`;
      respects `occupied`; deterministic under a seeded RNG; monotonic `Duration` input.
      Also red: size-constants table meets the Room floor (≥ 74 pt iPhone / ≥ 62 pt iPad,
      SC-500-08).
- [ ] T005 Green: add `Packages/ThemeKit/Sources/ThemeKit/ClockPlacement.swift` —
      `RandomPlacePicking` protocol + production impl (seedable RNG injected),
      `ClockPlace.fixedPlaces`, and the per-idiom size-constants table (digits pt, analog Ø
      per data-model.md). T004 goes green here.

## Phase 3: US4 slice A — renderer + seams (depends on Phase 2)

- [ ] T006 [US4] Red XCUITests in
      `Immich SlideshowUITests/ClockOverlayUITests.swift` (hermetic
      `--uitest --uitest-slideshow` launches per contracts/clock-overlay.md):
      (a) `--uitest-clock` shows `slideshow.clock` with `slideshow.clock.digits`;
      (b) chrome reveal hides the clock while `slideshow.chrome.playPause` is hittable,
      auto-hide returns it (SC-500-07); (c) swipe advances without revealing chrome and
      without hiding the clock; (d) `--uitest-assets-fail` pinned-chrome phase keeps the
      clock hidden.
- [ ] T007 [US4] Green: create `Immich Slideshow/Slideshow/ClockOverlayView.swift` —
      `TimelineView(.everyMinute)` container, digits style (rounded semibold, tabular
      numerals, soft halo + text shadow, optional date line), glass via existing
      `View+Compat` shims only, `.allowsHitTesting(false)`, a11y ids per contract.
- [ ] T008 [US4] Green: ambient-layer slot in
      `Immich Slideshow/Slideshow/SlideshowView.swift` — sibling of the chrome branch,
      chrome-parity insets (32/44), visibility `clock.isOn && !chromeVisible && playing`
      with 0.3 s ease (FR-510-02); parse seams `--uitest-clock`,
      `--uitest-clock-style/place/size=<raw>`, `--uitest-clock-date`,
      `--uitest-clock-seed=<n>`. T006 tests go green here.
- [ ] T009 [US4] Red-then-green: pill + analog styles in `ClockOverlayView.swift` with
      XCUITest sweep (styles × representative places `topCenter`/`bottomLeading`/
      `bottomCenter`, size cozy, date line digits/pill-only, screen-third assertions per
      contract invariant 4, plus rotation: clock re-anchors to its place with chrome-parity
      insets after orientation change) extended in `ClockOverlayUITests.swift`.
- [ ] T010 [US4] Red-then-green: Random wiring — photo-advance hook in `SlideshowView`
      calls the injected picker only when `place == .random`; XCUITest with
      `--uitest-clock-place=random --uitest-clock-seed=1` asserts the seeded place and
      no relocation across several fast advances (cadence not elapsed).

## Phase 4: US4 slice B — live settings rows (depends on Phase 2; UI after slice A)

- [ ] T011 [US4] Red XCUITest (settings scenario in `ClockOverlayUITests.swift`): open
      settings via chrome, toggle Clock on, set style/place/size/date via the new rows,
      dismiss; overlay reflects choices; relaunch without seams persists them (FR-500-05).
      Includes a Random relaunch sanity: place Random persists as Random and the clock
      appears at some fixed place after relaunch (fresh pick, no stored position).
- [ ] T012 [US4] Green: replace the clock placeholder row in
      `Immich Slideshow/Slideshow/SlideshowSettingsView.swift` with live rows bound to the
      store (Clock toggle · Clock style · Clock place · Clock size · Date line), ids
      `settings.clock*`, sentence-case copy per the Quiet Glass settings mock.

## Phase 5: US4 slice C — HA widening (depends on Phase 2; parallel to Phases 3–4)

- [ ] T013 [P] [US4] Red tests in `Packages/HAControlKit/Tests/`: discovery publishes
      `clock_style`/`clock_size` selects and widens `clock_corner` options to the seven
      `ClockPlace` raws (id/topics unchanged, display name "Slideshow Clock Place");
      snapshot round-trips style/place/size; inbound unknown option is ignored
      gracefully (retained-state rule in contracts/clock-overlay.md).
- [ ] T014 [US4] Green: widen
      `Packages/HAControlKit/Sources/HAControlKit/HAEntityState.swift` (+`clock_style`,
      `clock_size`), `HADiscovery.swift` (two selects, options from `allCases`),
      `RemoteControlling.swift` (`ThemeSettingsSnapshot` fields), and
      `HAControlCoordinator` publish/command paths.
- [ ] T015 [US4] Green: bridge the widened fields in
      `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift` (raw-value mapping
      both directions, same pattern as existing clock fields); host tests for the mapping.

## Phase 6: Polish & gates

- [ ] T016 Screenshot gate: quickstart scenarios 3 + 5 captured on iOS 26.x iPad (glass)
      and scenario 3 on the 17.5 iPad sim (material fallback); visual check that digits
      meet the Room presence and halo reads over the bright/dark stub photos. Includes
      quickstart scenario 8 (minute rollover observed once: time updates, siblings do not
      reflow — FR-510-01/SC-510-02).
- [ ] T017 Full-suite gate (SC-510-01): entire XCUITest suite + all host suites green via
      XcodeBuildMCP on 26.x; `swift test` green for ThemeKit, HAControlKit, SlideshowKit.
      (Memory: broker-toggle full-suite flake — rerun that class alone before blaming
      this diff.)
- [ ] T018 Docs + traceability: mark FR-510-01…06 / SC-510-01…02 rows done in
      `specs/510-clock-overlay/spec.md` status, flip the 300 roadmap clock note to
      "implemented (510)" in `specs/300-slideshow/spec.md`, update
      `docs/spec-overview.md` deferred-list line, and note the two new HA entities in the
      HA docs section touched by 710.

## Dependencies & execution order

```text
T001 → T002 → T003 → T004 → T005 ─┬→ T006 → T007 → T008 → T009 → T010 → T011 → T012 ─┐
                                  └→ T013 [P] → T014 [P] → T015 ─────────────────────┴→ T016 → T017 → T018
```

- Phase 2 blocks everything (model types are the shared vocabulary).
- Phases 3–4 are sequential (renderer before settings UI — the settings scenario drives
  the overlay). Phase 5 is parallel to 3–4 (different packages/files) until T015 (app
  target file, after T008 to avoid `SlideshowView` merge friction).
- MVP cut, if needed mid-session: stop after T010 — clock renders with seams and vanish
  rule; settings rows + HA follow next session. (Not preferred; the feature is small.)

## Implementation strategy

Subagent delegation per the sanctioned model (Opus/Sonnet subagents; Codex off): Phase 2 +
Phase 5 are clean host-test slices for one subagent each; Phases 3–4 (SwiftUI + timer/
animation semantics + simulator verification) stay inline with Fable per CLAUDE.md
delegation rules (chrome/timer test design is explicitly keep-inline). Screenshots and
gates (T016–T017) inline via XcodeBuildMCP.
