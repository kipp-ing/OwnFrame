# Tasks: Slideshow — Amendment 2026-09-14 (Chrome Legibility Below iOS 26, #72)

**Input**: `specs/300-slideshow/spec.md` — FR-300-34 (chrome legible over any photo, near-white and
near-black included) and FR-300-15 (Liquid Glass chrome). Design record
`docs/design/quiet-glass-2026-07-18.html`: the "One material, three tiers" and "Scrims that whisper"
cards (~:486-500), the scrim CSS (:110-114), and the implementation map (~:700-721).

**Scope**: this file covers **only** the #72 amendment. The rest of 300 was built from the specs it
consolidates and has no tasks here. From the design record's implementation map, only the
**soft-glass tier** and the **scrims** rows are tasked. Out of scope: the caption pill redesign of
`PhotoInfoView`, the ambient layer split, the clock renderer, and the gear glyph swap to
`slider.horizontal.3`.

**Gap (fact LOOK-03)**:
- Below iOS 26, `glassButtonStyle()` falls back to `.bordered`, a tinted fill with no material
  (`OwnFrame/Slideshow/View+Compat.swift:26-31`).
- Legibility rests on fixed 160 pt linear 45%-to-clear edge gradients
  (`OwnFrame/Slideshow/SlideshowChrome.swift:56-71`).
- No test or capture checks FR-300-34.

**Design record, verbatim intent**:
- iOS 26+ keeps Liquid Glass as-is. iOS 17–25 gets **soft glass**: the existing `ultraThinMaterial`
  fallback with a baked-in dark tint (≈ `black.opacity(0.2)` inside the shape), so white symbols
  always sit on a mid-dark ground.
- A new `glassPill()` helper serves caption/clock. `glassCard`/`glassButtonStyle`/`glassGroup` keep
  their iOS 26 paths untouched.
- The scrims become eased four-stop gradients with a 34% peak (stops 0.34 → 0.18 @ 40% → 0.06 @ 75%
  → clear) over ~26% of screen height.

The record's "suggested order" puts the soft-glass tier and scrims first, as a pure re-skin that can
be screenshot-diffed.

**Coordination**: 310 Phase 7's #60 part (new-photos card scrim, FR-310-15) uses the **same helper**.
T005 gives `glassCard` an optional in-shape `scrim` layer, and 310 T037 opts the card into it. **T005
lands before 310 T037 or in the same commit** (worklist WP4a, with #59/#60). 9000 (#59) changes
filled accent controls, not glass, so there are no shared files.

**Tests**: MANDATORY — constitution principle I (Test-First, NON-NEGOTIABLE). A red test lands
before every implementation task; "red" includes does-not-compile (see `tdd-workflow.md`). The
visual gate is captures, because material blur cannot be asserted numerically.

## Format: `[ID] [P?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- All paths relative to repo root

## Path Conventions

- App target: `OwnFrame/` (verified via XcodeBuildMCP, never raw `xcodebuild`), app tests
  `OwnFrameTests/`, UI tests `OwnFrameUITests/`
- Everything here is app target, so every task is **Claude inline** (SwiftUI + simulator), except the
  optional SlideshowKit slice in T008.

---

## Phase 1: Capture seam & baseline

- [ ] T001 Red+Green capture seam (**Claude**): a DEBUG-only launch argument
      `--uitest-photo-tone=white|black` makes the hermetic stub renderer
      (`renderPortrait(for:)`, `OwnFrame/OwnFrameApp.swift` ~:1250-1274) paint a full-bleed
      near-white (`#F8F8F8`) or near-black (`#080808`) image with no border and no dot. Default
      renders stay unchanged. Red first in new `OwnFrameTests/UITestPhotoToneSeamTests.swift`
      (pattern: `UITestNewPhotosCardSeamTests`).
- [ ] T002 Baseline captures (**Claude**): new `OwnFrameUITests/ChromeLegibilityCaptureUITests.swift`,
      opt-in like `AppStoreScreenshotUITests` so the default suite only records it as a skip. It
      launches `--uitest --uitest-slideshow --uitest-photo-tone=white|black`, reveals the chrome,
      opens photo info, and attaches captures; add one capture with the clock pill (entitlements
      seam, as in `ClockOverlayUITests`). Run on **iOS 18.6** (soft-glass path) and **iOS 26.0**
      (glass path), confirming the runtime from the xcresult. Downscale (`sips -Z 900`) before
      reading. Record under this task, per tone and runtime, whether the top-bar and bottom-bar
      glyphs, the info card and the clock read.

---

## Phase 2: Tests (red first) ⚠️

- [ ] T003 [P] Red: new `OwnFrameTests/SoftGlassTierTests.swift` — structure pinned to the design
      record: a named soft-glass tint constant ≈ 0.2 black, used inside the shape below iOS 26; the
      scrim stops are `[(0.34, 0.0), (0.18, 0.40), (0.06, 0.75), (0.0, 1.0)]` (record CSS :111-112);
      the scrim band height is 0.26 of the screen height. Red = the constants don't exist.
- [ ] T004 [P] Red: same file, worst-case legibility arithmetic. A white glyph over a pure-white photo
      sits under the scrim value at the bars' vertical position: the 44 pt inset plus half a control,
      as a fraction of the 26% band on the smallest supported iPad/iPhone screen height. Composite
      that scrim with the soft-glass tint, ignoring blur, and require ≥ 3:1. That number is the icon
      threshold of FR-9000-07; FR-300-34 names none, so it is this plan's choice. **If the record's
      values fail the bound, stop and report to Jan. Do not re-tune the record's numbers silently.**

---

## Phase 3: Implementation

- [ ] T005 Green: soft-glass tier in `OwnFrame/Slideshow/View+Compat.swift`:
      - **Below iOS 26:** `glassCard(cornerRadius:)` = `ultraThinMaterial` plus the tint fill inside
        the same `RoundedRectangle`. `glassButtonStyle()` becomes a material button style (shape
        filled with `ultraThinMaterial` plus the tint, white label, a pressed state) instead of
        `.bordered`.
      - **New optional parameter** `glassCard(cornerRadius:scrim:)`: an in-shape dark layer at the
        darker of tint and `scrim` below iOS 26, and at `scrim` on iOS 26. With `scrim == nil`, the
        iOS 26 path is today's, unchanged. 310 T037 (#60) consumes it.
      - **New `glassPill()`**: a capsule in the same tier, `glassEffect(in: .capsule)` on iOS 26.
      - The iOS 26 branches of `glassCard`, `glassButtonStyle` and `glassGroup` stay untouched.

      Green T003.
- [ ] T006 Green: `OwnFrame/Slideshow/SlideshowChrome.swift:56-71` `edgeScrims` — the eased four-stop
      gradients from T003's constants over 26% of the screen height (read from the container)
      replace the fixed 160 pt 45% linear bands. Keep `.ignoresSafeArea()` and
      `.allowsHitTesting(false)`, and update the comments at :8-11 and :55-59. The scrims apply on
      **every** runtime (they are not a glass path), so iOS 26 captures change here and only here.
      Green T004.
- [ ] T007 `OwnFrame/Slideshow/ClockOverlayView.swift:160` (`glassCard(cornerRadius: 999)`) →
      `glassPill()`. `PhotoInfoView.swift:39` stays a card: the caption pill is a separate row of the
      record, not #72.
- [ ] T008 Decision (record here; **ask Jan**): the record also scales scrim opacity by the current
      photo's edge luminance, with one `CIAreaAverage` over the top/bottom fifths of the decoded
      image, cached per asset. The scrim fades toward ~15% over already-dark photos; the mock uses
      45% of the scrim for dark photos (CSS :114). That calms dark photos rather than fixing
      legibility. **Default if undecided: not in #72.** If in scope: Red host test in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/` for a pure opacity mapping (bright → 1.0,
      dark → 0.45), then Green in SlideshowKit (subagent-eligible) and the app wiring (**Claude**).
      Also note that the record's "video-luminance harness" does not exist in the repo; T002/T009
      captures stand in for it.

---

## Phase 4: Verification & Close

- [ ] T009 Re-capture (**Claude**): the T002 matrix on 18.6 and 26.0 (bars, info card, clock pill over
      near-white and near-black), compared against the baseline. On iOS 26 only the scrims may
      differ. Downscale before reading.
- [ ] T010 **Jan (HITL)**: eyeball on **Framepad** (iPad Pro 10.5, iOS 17.7.10, the deployment floor)
      over a near-white and a near-black photo, via `.claude/scripts/framepad.sh` (recipes in
      `docs/device-testing.md`). Queue it in `docs/hitl.md`.
- [ ] T011 `test_sim` whole classes `SoftGlassTierTests`, `UITestPhotoToneSeamTests`,
      `SlideshowChromeUITests`, `ClockOverlayUITests`, `PhotoInfoUITests`, `AlbumBrowserUITests`
      (its card uses `glassCard`, `AlbumBrowserView.swift:141`) (**Claude**). The full XCUITest suite
      runs at the worklist's final gate (WP5).
- [ ] T012 Facts, **same commit as T005/T006**: `product-facts.yaml` **LOOK-03** →
      `implementation: verified` on the T009 captures; remove `mismatch`/`candidate_issue`; refresh
      `evidence` (tier lines in `View+Compat.swift`, scrim lines in `SlideshowChrome.swift`,
      `SoftGlassTierTests.swift`). If T010 later disagrees, set it back to `mismatch`. Run
      `.claude/scripts/check-facts.py`.
- [ ] T013 Commit with explicit paths (WP4a; before or with 310 T037). Close #72 once T010 is done;
      until then, comment on #72 naming T010 as the open step.

---

## Dependencies & Execution Order

- T001 → T002 (the baseline needs the seam) → T003 ∥ T004 → T005 (→ unblocks 310 T037) → T006 →
  T007 → T009 → T010/T011 → T012 → T013. T008 is decided before T005 starts; if it is in scope, its
  tasks slot in after T006.
- T003/T004 share one new file, so write them sequentially despite `[P]` against T001/T002.

## Notes

- The iOS 26 glass code paths must stay unchanged; review the T005 diff for that before commit.
- Store captures in `Design/AppStore/` are frozen and are not re-rendered.
- Stage with explicit paths, never `-A`.
