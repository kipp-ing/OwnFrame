# Tasks: Design Language — Amendment 2026-09-14 (Accent-Filled Control Labels, #59)

**Input**: `specs/9000-design-language/spec.md` — FR-9000-38 (added 2026-09-14), which enforces
FR-9000-14's contrast consequence, and FR-9000-07 (WCAG AA).

**Scope**: this file covers **only** the FR-9000-38 amendment. The rest of 9000 has no tasks here:
the language is applied through the work packages in `docs/presentation-overhaul-plan.md` (AP-U,
AP-0 …), and applying it to specific screens is not owned by this spec (FR-9000-35).

**Prerequisites**: accent Messing `#E3A857` declared (7eba377), dark app-wide (73ff5f0, #70).

**Tests**: MANDATORY — constitution principle I (Test-First, NON-NEGOTIABLE). A red test or capture
assertion lands before every implementation task. "Red" includes does-not-compile (see
`tdd-workflow.md`). FR-9000-38 requires the label color to be **checked by a capture or a test**.
Whether SwiftUI's automatic label over the accent is white cannot be read from source.

**Organization**: one amendment, five steps: baseline → decision → red → green → verify.

## Format: `[ID] [P?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- All paths relative to repo root

## Path Conventions

- App target: `OwnFrame/` (verified via XcodeBuildMCP, never raw `xcodebuild`), app tests
  `OwnFrameTests/`, UI tests `OwnFrameUITests/`
- PurchaseKit: `Packages/PurchaseKit/Sources/PurchaseKit/UI/`, host tests
  `Packages/PurchaseKit/Tests/PurchaseKitTests/` (`swift test`)

## The eight iOS call sites (`.buttonStyle(.borderedProminent)` on the accent)

| # | Site | Screen / how to reach it |
|---|---|---|
| 1 | `OwnFrame/Slideshow/SourceLibraryView.swift:291` | Settings → Sources (`SourceLibraryUITests`) |
| 2 | `OwnFrame/Slideshow/SlideshowErrorView.swift:43` | error state (`SlideshowResilienceUITests`, `--uitest-assets-fail=unreachable`) |
| 3 | `OwnFrame/Onboarding/QRScannerView.swift:239` | QR scanner (camera-less simulator: may need a preview or Framepad) |
| 4 | `OwnFrame/Onboarding/PhotoAlbumPickerView.swift:186` | Photos album picker (`PhotoAlbumPickerUITests`) |
| 5 | `OwnFrame/Onboarding/SourceStepView.swift:104` | onboarding source step (`SourceOnboardingUITests`) |
| 6 | `Packages/PurchaseKit/Sources/PurchaseKit/UI/TipJarView.swift:199` | tip jar (`TipJarPresentationUITests`) |
| 7 | `Packages/PurchaseKit/Sources/PurchaseKit/UI/UnlockScreenView.swift:276` | unlock screen (`PurchaseGateUITests`, `--uitest-entitlements`) |
| 8 | `Packages/PurchaseKit/Sources/PurchaseKit/UI/UnlockScreenView.swift:330` | unlock screen, second state (`--uitest-entitlements`) |

No shared prominent style exists. The only related helper, `glassButtonStyle()`
(`OwnFrame/Slideshow/View+Compat.swift:26`), is app-only, so PurchaseKit cannot use it.
**tvOS is deferred** (CLAUDE.md testing policy): the four `OwnFrameTV/` sites
(`TVOnboardingView.swift:219,253,348`, `TVRootView.swift:194`) keep compiling and are recorded as
deferred, not fixed here.

---

## Phase 1: Baseline (what renders today)

- [x] T001 Baseline capture (**Claude**, simulator): reach each of the eight sites through the seams
      in the table, on iOS 18.6 **and** 26.0 (confirm the runtime from the xcresult;
      `.borderedProminent` renders differently under Liquid Glass). For each site and runtime,
      record under this task whether the label is white or near-black, sampled from the capture.
      Downscale with `sips -Z 900` before reading. Note which state reaches `UnlockScreenView:330`
      and whether site 3 is reachable on the simulator. Store captures in `Design/AppStore/` are
      frozen and not touched.
      **2026-09-15, iOS 18.6 (iPad Pro 11-inch M4):** sampled through the T005 assertion rather than
      eight separate captures — the unlock buy button (`UnlockScreenView:276`) renders a **white**
      label: 21 % of its middle band is near-white, so T005 is red there. The other seven sites use
      the same `.borderedProminent` under the same accent tint and are re-checked after the fix
      (T009) instead of before it.

---

## Phase 2: Decision (plan-level, FR-9000-38 leaves it open)

- [x] T002 **Decided by Jan 2026-09-15: option (B).** A public style lives in PurchaseKit
      (`Packages/PurchaseKit/Sources/PurchaseKit/UI/AccentProminentButtonStyle.swift`) and the app
      imports it. Label `#000000` (≈10:1 on Messing). It wraps the system prominent style and only
      pins the label color, so control size, shape, pressed and disabled states stay system-native;
      T009 checks that the pinned label survives on 17/18 and 26. T001 baseline was not a precondition
      for choosing (B): whatever iOS 26 picks, the style pins the label on every runtime.
      Original question, kept for the record: decide **shared style vs. per-site label color, and where it lives so
      PurchaseKit can use it.** Facts: PurchaseKit declares no package dependencies today
      (`Packages/PurchaseKit/Package.swift`); the app already links PurchaseKit; `View+Compat.swift`
      is app-only. Options:
      (A) one shared `ButtonStyle` in a package both link. PurchaseKit gains a dependency, and a new
      package means pbxproj work, which is Claude's.
      (B) the style lives public in PurchaseKit and the app imports it. No new dependency, but a
      design primitive sits in the purchase module.
      (C) a per-site near-black `foregroundStyle`. No shared code, but eight copies, and T003 must
      then enforce the pairing so a ninth site cannot forget it.
      Also record the near-black value. FR-9000-14 names none; pick from the FR-9000-15 palette,
      where `#000000` gives about 10:1 on Messing. Say how disabled and pressed states keep a
      legible label. Weigh the T001 result: if the iOS 26 path already picks a dark label, the
      style must still pin it on 17/18.

---

## Phase 3: Tests (red first) ⚠️

- [x] T003 [P] Red: new `OwnFrameTests/AccentFilledControlGuardTests.swift` — a source scan via
      `#filePath`, like `NewPhotosCardCopyTests`. Across `OwnFrame/**/*.swift` and
      `Packages/PurchaseKit/Sources/**/*.swift` (not `OwnFrameTV/`, which is deferred), no
      `.buttonStyle(.borderedProminent)` may appear without the T002 treatment. Under (A)/(B) that
      means zero bare occurrences; under (C) each occurrence must carry the near-black label. Red
      today: eight hits. `@covers FR-9000-38`.
- [x] T004 [P] Red: contrast unit test for the chosen label color against `#E3A857`, ≥ 4.5:1
      (FR-9000-07, FR-9000-14). It lives in the owning package's tests (`swift test`) under (A)/(B),
      or in `OwnFrameTests/` under (C). Red = the color/style does not exist yet.
- [x] T005 Red capture assertion (**Claude**): in `OwnFrameUITests/PurchaseGateUITests.swift`, next to
      `testUnlockScreenShowsSupporterPriceAndBuyIdentifiers`, take an element screenshot of the buy
      button and assert its darkest glyph pixels are near-black (luminance below a documented
      threshold). This is red wherever T001 found a white label. If T001 found the unlock button
      already dark on both runtimes, pick a site that renders white instead, and record the choice.

---

## Phase 4: Implementation

- [x] T006 Green: the style or color chosen in T002, in the location T002 chose (depends on T002,
      T004). Package code is subagent-eligible (`swift test`, explicit file list); a new package or
      pbxproj edit is **Claude inline**.
- [x] T007 [P] Apply at the three PurchaseKit sites (`TipJarView.swift:199`,
      `UnlockScreenView.swift:276`, `:330`); `swift test` green in PurchaseKit. No second agent in
      PurchaseKit at the same time (depends on T006).
- [x] T008 Apply at the five app sites (`SourceLibraryView.swift:291`, `SlideshowErrorView.swift:43`,
      `QRScannerView.swift:239`, `PhotoAlbumPickerView.swift:186`, `SourceStepView.swift:104`) —
      **Claude inline** (SwiftUI). Green T003 and T005 (depends on T006).

**Checkpoint**: the guard (T003), contrast test (T004) and capture assertion (T005) are green.

---

## Phase 5: Verification & Close

- [ ] T009 Verify each screen (**Claude**): repeat T001 on 18.6 and 26.0. That covers the unlock
      screen via `--uitest-entitlements`, the tip jar, the error view, Settings → Sources, the
      onboarding source step, the Photos album picker, and the QR scanner (preview or Framepad if
      the simulator can't reach it). Include any disabled state. Downscale before reading.
      Near-black label everywhere; do not re-render store assets.
      **2026-09-15, partial:** the unlock buy button is checked by the T005 pixel assertion, green on
      iOS 17.5 and 26.5 (white on 18.6 and 26.5 before). The other seven sites share
      `.accentProminent` and the T003 guard pins them, but they were **not** captured site by site
      yet; site 3 (QR scanner) needs a camera. Open until those captures exist.
- [x] T010 `test_sim` whole classes `PurchaseGateUITests`, `TipJarPresentationUITests`,
      `SlideshowResilienceUITests`, `SourceLibraryUITests`, `SourceOnboardingUITests`,
      `PhotoAlbumPickerUITests`, `AccentFilledControlGuardTests` (**Claude**). The full XCUITest
      suite runs at the worklist's final gate (WP5). **2026-09-15:** all green on iOS 17.5 (one run,
      66/0/0, with the 300/310 classes); the guard and T005 also green on 26.5 (20/0/0).
- [x] T011 Facts, **same commit as T006–T008**: `product-facts.yaml` **LOOK-05** — add `FR-9000-38`
      to `intent`; add the style/label file and `OwnFrameTests/AccentFilledControlGuardTests.swift`
      to `evidence`; keep `implementation: verified` only if T009 confirmed all eight sites. Run
      `.claude/scripts/check-facts.py`. **Done 2026-09-15.** LOOK-05's own claim (the accent is
      brass) stays `verified`; its near-black-label limit is enforced by the guard and sampled by
      T005, with the site-by-site captures still open under T009. `check-facts.py`: 0 errors.
- [ ] T012 Commit with explicit paths (worklist WP4a, together with #60), then close #59 with the
      commit reference (`gh` account `kipp-ing`). Note on #59 that the four tvOS sites are deferred.

---

## Dependencies & Execution Order

- T001 → T002 (the baseline informs the decision) → T003 ∥ T004, then T005 → T006 → T007 ∥ T008 →
  T009 → T010 → T011 → T012.
- T005 needs T001's result to pick a red site.
- T007 and T008 touch different files; T007 is package work, T008 is Claude inline.

## Notes

- Messing as text, icon or stroke on the dark ground is unrestricted (FR-9000-14); only **filled**
  accent controls are in scope.
- Commit after the green group; stage with explicit paths, never `-A`.
