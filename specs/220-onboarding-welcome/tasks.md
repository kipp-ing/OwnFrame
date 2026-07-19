# Tasks: Onboarding Welcome Overhaul (iCloud, Shared-Link QR, One Welcoming Screen)

**Input**: Design documents from `/specs/220-onboarding-welcome/`

**Prerequisites**: plan.md, spec.md, research.md (R1–R8), data-model.md,
contracts/onboarding-welcome-surface.md, quickstart.md

**Tests**: INCLUDED — TDD is constitution principle I (NON-NEGOTIABLE). Every
implementation task is preceded by its red test task; subagent reports must show the
red run. A task whose red state is "the app target doesn't compile yet" says so
explicitly. Camera capture (`QRScannerView`) has no host red — it is device-gated
(SC-220-07); its testable seam (`CodeScanning` + `ScannedShareLink`) is host-tested
instead.

**Organization**: Setup → Foundational (OnboardingKit deltas — the third path, the new
step, the scan seam + validator — block everything) → user stories in priority order
(US1 iCloud P1, US2 QR P1; US3 welcoming screen P2) → polish. Delegation per the 900
model (Fable orchestrates, Opus/Sonnet subagents implement): the OnboardingKit package
slice is delegable; everything touching the app target, `OnboardingFlowView`, the
camera view, the simulator, or `project.pbxproj` stays Fable-inline (CLAUDE.md:
app-target / entry-point / cross-cutting work is not delegated).

## Format: `[ID] [P?] [Story] Description`

## Status (checkboxes reconciled 2026-07-19)

T001–T020 complete — spec.md Status is `Implemented on branch (2026-07-17)`, the FR-220/SC-220
rows are recorded in `docs/spec-traceability.md` (T018), the `220` row is in
`docs/spec-overview.md` (T019), and the suite ran green (154 host + 94/0 XCUITest, T020). The
boxes were simply never ticked as the work landed; this note records the reconciliation rather
than any new work.

**Open: T021 only** — the real-hardware checklist (SC-220-01/02/04/05 + the camera-usage copy),
riding the same device day as the 900 quickstart and the 800 gates.

---

## Phase 1: Setup

- [X] T001 Confirm the baseline on branch `220-onboarding-welcome` (based on the
      `900-photo-library-source` tip): `swift test` green in `Packages/OnboardingKit`,
      XcodeBuildMCP `build_sim` green, and the reused 900 surfaces present
      (`Immich Slideshow/Onboarding/PhotoAlbumPickerView.swift`,
      `SourceKind.photoLibrary`, `SourceLibraryViewModel.addPhotoLibrarySource`). No
      code change — this pins the pre-feature green so every later red is attributable.

---

## Phase 2: Foundational (OnboardingKit deltas — BLOCKS all user stories)

**Purpose**: The host-testable core every story builds on — the third
`OnboardingPathChoice`, the `.photoLibrarySetup` step, and the scan seam + validator
(shared by US2). Adding `.photoLibrarySetup` to `OnboardingStep` deliberately breaks
the exhaustive step switches; the package is made green here, and the app target's
`OnboardingFlowView` compile-red becomes the US1 entry point.

**Delegable** as one slice (package-only, host-tested — Opus/Sonnet subagent).

- [X] T002 [P] Red tests:
      `Packages/OnboardingKit/Tests/OnboardingKitTests/OnboardingWelcomePathTests.swift` —
      `choosePath(.photoLibrary)` sets `step == .photoLibrarySetup` and clears
      `errorMessage`; `.sharedLink`/`.server` routing unchanged; `canGoBack == true`
      and `back()` → `.choice` from `.photoLibrarySetup`; `finish()` with a
      `.photoLibrary` active source sets `.done` and writes NO album config (the
      `if case .album` guard is skipped — data-model.md). Expected red: won't compile
      until `OnboardingPathChoice`/`OnboardingStep` gain their cases (T004)
- [X] T003 [P] Red tests:
      `Packages/OnboardingKit/Tests/OnboardingKitTests/ScannedShareLinkTests.swift` —
      a valid Immich share string → `.success((baseURL, slug))` byte-identical to
      `SharedLinkURL.parse`; a non-URL → `.notAURL`; an `http://` URL → `.notHTTPS`; a
      URL with no `/s/` share shape → `.notAShareLink`; every failure records NO
      persistence and makes NO network call (pure). Expected red: won't compile until
      `ScannedShareLink` exists (T005)
- [X] T004 Implement the enum + routing in
      `Packages/OnboardingKit/Sources/OnboardingKit/OnboardingViewModel.swift` and
      `Packages/OnboardingKit/Sources/OnboardingKit/OnboardingStep.swift`:
      `OnboardingPathChoice` gains `.photoLibrary`; `OnboardingStep` gains
      `.photoLibrarySetup`; `choosePath`, `canGoBack`, and `back()` handle the new
      case (contracts § OnboardingKit) — green T002. NOTE: this breaks the app target's
      `OnboardingFlowView` switch until T009 (expected compile-red — the US1 entry)
- [X] T005 [P] Implement
      `Packages/OnboardingKit/Sources/OnboardingKit/ScannedShareLink.swift`
      (`validate(_:) -> Result<ParsedSharedLink, InvalidCodeReason>` wrapping
      `SharedLinkURL.parse`) and
      `Packages/OnboardingKit/Sources/OnboardingKit/CodeScanning.swift` (the seam
      protocol — Foundation only, NO `AVFoundation`) per data-model.md — green T003
- [X] T006 [P] Red-then-green pin:
      `Packages/OnboardingKit/Tests/OnboardingKitTests/StartupGatePhotoLibraryTests.swift` —
      a `.photoLibrary`-only active source with no connection → `StartupGate.initialStep()`
      returns `.done` (US1-5 relaunch parity). Green on write — 900 already routes this
      (`StartupGate.swift`); the test pins it against regression
- [X] T007 **Checkpoint (Foundational)**: `swift test` green in `Packages/OnboardingKit`
      (all deltas). `build_sim` is expected RED here — the app's `OnboardingFlowView`
      does not yet handle `.photoLibrarySetup`; T009 restores it. Zero behaviour change
      to existing onboarding logic (existing OnboardingKit suites stay green)

---

## Phase 3: User Story 1 — Start from an iCloud album, chosen on the first screen (P1) 🎯 MVP

**Goal**: The welcome screen's top option is "Use an iCloud album"; choosing it enters
the reused Photos permission + album picker and reaches the slideshow with no server /
API key (FR-220-01/02/03).

**Independent Test**: quickstart Phase-2 iCloud row — from a fresh install with Photos
access seeded via `simctl privacy`, tap the iCloud option on the welcome screen, pick
an album, reach the running slideshow; relaunch routes straight to the slideshow.

- [X] T008 [US1] Red tests (app-hosted UITest):
      `Immich SlideshowUITests/WelcomeICloudUITests.swift` — from the welcome screen the
      top option is "Use an iCloud album"; tapping it reaches `PhotoAlbumPickerView`
      (Photos access seeded via `simctl privacy`, the 900 `PhotoAlbumPickerUITests`
      pattern); selecting an album reaches the slideshow with no connection/API key.
      Expected red = the app target doesn't compile until T009
- [X] T009 [US1] Implement (Fable-inline) the iCloud path in the app target:
      `Immich Slideshow/Onboarding/OnboardingFlowView.swift` handles `.photoLibrarySetup`
      → renders the reused `PhotoAlbumPickerView` with a completion that calls
      `onboarding.finish()` (→ `.done`); `Immich Slideshow/Onboarding/OnboardingChoiceView.swift`
      gains the iCloud option as the FIRST row → `choosePath(.photoLibrary)`. This
      restores `build_sim` — green T008 (contracts § iCloud step)
- [X] T010 [US1] **Checkpoint (MVP)**: `swift test` green; `build_sim` green;
      `WelcomeICloudUITests` green via `test_sim`; simulator spot-check — the welcome
      screen shows the iCloud option at top and picking an album plays the slideshow

---

## Phase 4: User Story 2 — Add a shared album by scanning its QR code (P1)

**Goal**: The shared-link path offers "Scan QR"; a scanned Immich shared-album code is
handled identically to a typed link (FR-220-04/05/06). New camera capability behind the
`CodeScanning` seam; camera end-to-end is a device gate.

**Independent Test**: host — a scanned valid link routes through the same resolver as a
typed link, an invalid code is rejected with nothing persisted; simulator — the Scan-QR
affordance is present and manual entry still reaches the slideshow. Camera scan itself =
SC-220-07 manual device gate.

- [X] T011 [US2] Red tests:
      `Packages/OnboardingKit/Tests/OnboardingKitTests/ScannedLinkRoutingTests.swift` —
      driving the shared-link add flow through a fake `CodeScanning`: a scanned VALID
      link triggers the exact same `SourceLibraryViewModel.resolveSharedLink` call a
      typed link makes (parity); a scanned INVALID code surfaces the calm rejection,
      makes NO resolve/network call, and persists nothing (FR-220-04/06). Delegable
      (package host test)
- [X] T012 [US2] Implement (Fable-inline — camera + simulator) the scan UI:
      `Immich Slideshow/Onboarding/QRScannerView.swift` (the ONLY `AVFoundation` file —
      `AVCaptureMetadataOutput` `.qr`, one-shot, conforms `CodeScanning`; camera-auth
      denied/restricted and no-camera → calm one-liner keeping manual entry), and a
      "Scan QR" affordance in `Immich Slideshow/Onboarding/SharedLinkSetupView.swift`
      wiring the decoded string → `ScannedShareLink.validate` → the existing resolve
      path — green T011 (research R1/R2/R8, contracts § Scan QR)
- [X] T013 [US2] Add `INFOPLIST_KEY_NSCameraUsageDescription` (English: the camera is
      used only to read a shared-album QR code; no photo is captured or stored) to
      `Immich Slideshow.xcodeproj/project.pbxproj`, beside the existing
      `NSPhotoLibraryUsageDescription` (Fable-inline; pbxproj explicitly IN SCOPE for
      this task only)
- [X] T014 [US2] **Checkpoint**: `swift test` green; `build_sim` green; `test_sim`
      shows the Scan-QR affordance present and manual link entry still reaching the
      slideshow with no API key; new intent/UI strings staged from
      `Immich Slideshow/Localizable.xcstrings` (Xcode auto-extraction) with the commit;
      camera end-to-end recorded as the SC-220-07 pending device gate (not sim-claimable)

---

## Phase 5: User Story 3 — One welcoming screen a non-technical user understands (P2)

**Goal**: The welcome screen presents exactly three friction-ordered options, each with
plain-language helper text and light decoration (FR-220-01/08).

**Independent Test**: quickstart Phase-2 welcome row — three options in order (iCloud,
shared link, server + key), each with concise helper text, no Back; existing onboarding
UITests stay green.

- [X] T015 [US3] Red tests (app-hosted UITest): extend
      `Immich SlideshowUITests/OnboardingDescriptionsUITests.swift` (and
      `OnboardingBackUITests.swift`) — the welcome screen shows EXACTLY three options in
      friction order (iCloud, shared link, server + key), each exposing concise helper
      text, and has no Back affordance. Expected red until the copy/order land (T016)
- [X] T016 [US3] Implement (Fable-inline) the welcoming presentation in
      `Immich Slideshow/Onboarding/OnboardingChoiceView.swift` — friction-ordered rows,
      concise non-technical helper text per option, and light decoration (calm/light,
      constitution VII) — green T015. English-only strings
- [X] T017 [US3] **Checkpoint**: `test_sim` green (the extended onboarding UITests plus
      `SharedLinkOnboardingUITests` / `SourceOnboardingUITests` / `ShareSheetIncomingUITests`
      staying green — FR-220-07/09, SC-220-06); simulator spot-check — the screen reads
      welcomingly to a first-time user

---

## Phase 6: Polish & Ship Gates

- [X] T018 [P] Record the FR-220-xx / SC-220-xx traceability rows in
      `docs/spec-traceability.md` (test names per requirement, manual gates marked)
- [X] T019 Flip `specs/220-onboarding-welcome/spec.md` Status to implemented-on-branch
      and ADD the `220` row to `docs/spec-overview.md` (sub-spec of 200; note the 900
      dependency) — 220 is not yet in the overview table
- [X] T020 Full XCUITest suite via XcodeBuildMCP `test_sim` before merge (standing rule
      — SwiftUI/app-target changes shipped; skip the untracked `Noob*` throwaway classes;
      broker-toggle flake: rerun `BrokerSetupUITests` isolated before suspecting the diff)
      + the complete quickstart Phase-2 gate
- [ ] T021 Manual device checklist from `specs/220-onboarding-welcome/quickstart.md`
      (SC-220-01 iCloud welcome→slideshow + relaunch, SC-220-02 QR scan→slideshow,
      SC-220-04 invalid-code rejection, SC-220-05 camera-denied fallback, the
      `NSCameraUsageDescription` copy) — ship gate on the real frame iPad, riding the
      SAME device day as the 900 quickstart and the 800 (SC-800-02/03) gates

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none — start immediately.
- **Foundational (Phase 2)**: needs Setup. T002 → T004; T003 → T005; T006 parallel;
  T004 ∥ T005 (different files). T007 gates the phase on the PACKAGE (build_sim stays
  red until US1's T009 — expected).
- **US1 (Phase 3)**: needs Phase 2. T009 restores `build_sim`. MVP.
- **US2 (Phase 4)**: needs Phase 2 (the `CodeScanning` seam + `ScannedShareLink` are
  foundational). Independent of US1 at the code level (different files); ordered after
  US1 by priority. T011 → T012; T013 parallel to T012 (pbxproj vs source).
- **US3 (Phase 5)**: needs US1 (it refines the same `OnboardingChoiceView` US1 makes
  functional). T015 → T016.
- **Polish (Phase 6)**: needs all desired stories; T018 [P] anytime after US3; T019
  before merge; T020 before merge; T021 is the ship gate on real hardware.

### Parallel Opportunities

- T002 ∥ T003 (different test files); T004 ∥ T005 (VM/step vs new files); T006 parallel.
- T012 ∥ T013 (source vs pbxproj).
- T018 [P] anytime after US3.
- **Delegation slices**: **A** = T002–T006 (OnboardingKit foundational, host-tested,
  Opus/Sonnet subagent). T008–T010, T012–T014, T015–T017, T013, and all checkpoints are
  Fable-inline (app target / camera / simulator / pbxproj). T011 delegable (package host
  test).

### Within Each Story

Red test task strictly before its implementation task; package before app target;
functional option (US1) before welcoming polish (US3); checkpoint last. Commit per task
or logical pair (explicit `git add` paths — new UI strings also touch
`Immich Slideshow/Localizable.xcstrings` via Xcode auto-extraction; stage it with the
app-target commits).

---

## Implementation Strategy

**MVP = Phase 1 + 2 + US1 (T001–T010)**: after T010 the gap is closed — a brand-new user
picks "Use an iCloud album" on the first screen and reaches the slideshow with no server.
Stop, validate, demo.

**Increment 2 = US2 (T011–T014)**: the camera QR accelerator for shared albums — the
"scan the Immich QR" story, with camera end-to-end as a device gate.

**Increment 3 = US3 (T015–T017)**: the welcoming, explained, friction-ordered
presentation — the noob-welcoming polish over the working mechanics.

**Ship**: Polish gates T018–T020 on the branch; T021 rides the same real-hardware
session as the 900 quickstart and the 800 device gates (one device day covers all three
features' manual checks). 220 cannot merge ahead of 900 (it depends on the photoLibrary
source).
