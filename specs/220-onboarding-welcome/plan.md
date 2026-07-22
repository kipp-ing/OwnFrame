# Implementation Plan: Onboarding Welcome Overhaul (iCloud, Shared-Link QR, One Welcoming Screen)

**Branch**: `220-onboarding-welcome` (branch off the `900-photo-library-source` tip @ ce961db) |
**Date**: 2026-07-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/220-onboarding-welcome/spec.md`. Sub-spec of the 200
connection-onboarding module; extends the 210 choice-first onboarding and surfaces the 900
photoLibrary source at the top level.

## Summary

A welcome-screen-only overhaul plus one genuinely new capability (camera QR). The first-run choice
screen (`OnboardingChoiceView`) grows from two options to **three friction-ordered, first-class
paths** — iCloud album (top), Immich shared link (middle), Immich server + API key (bottom) — with
plain-language copy and light decoration. Almost everything is reuse: the iCloud path routes into
the existing 900 `photoLibrary` flow (`PhotoAlbumPickerView` + `SourceLibraryViewModel`), and the
shared-link path keeps its resolve-first/password-when-needed behaviour. The only new surface is a
**camera QR scanner** for Immich shared-album codes: a decoded string is validated by the existing
`SharedLinkURL.parse` and fed into the identical resolve path, so a scanned link and a typed link
are indistinguishable downstream. Camera capture lives behind a `CodeScanning` seam so the
parse/route logic is host-tested; the camera itself is a manual device gate (it cannot run in the
simulator), riding the same device day as 900/800.

Two facts from the code make this cheap: (1) `StartupGate.initialStep()` **already** routes a
connectionless `.photoLibrary` active source straight to `.done` (900, R5), so US1's relaunch
parity is free; (2) `OnboardingViewModel`'s `choosePath`/`canGoBack`/`back` and
`OnboardingFlowView` switch exhaustively over `OnboardingStep`, so adding a step makes the suite
red (won't compile) until every site handles it — the TDD entry point.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: Existing packages only — `OnboardingKit` (path choice, step machine,
`SharedLinkURL`, `SourceLibraryViewModel`, `StartupGate`), the 900 `PhotoLibraryKit`/
`PhotoSourceKit` (photoLibrary source + album picker seam), `ImmichClient` (shared-link resolve).
New platform framework `AVFoundation` (`AVCaptureMetadataOutput`, QR) imported **only** inside one
app-target view (`QRScannerView`) behind the `CodeScanning` protocol seam. No third-party deps.

**Storage**: No new persistent stores and no new wire format. Every welcome path lands a source in
the existing `UserDefaultsSourceLibraryStore`; the `.photoLibrary` and `.sharedLink` `SourceKind`
cases already exist (900 / 110). Non-secret data only (collection id / label; shared-link base URL
+ slug). Shared-link passwords stay in the existing `SharedLinkSecretStore` (keychain).

**Testing**: Swift Testing on the host for all OnboardingKit deltas — the third `OnboardingPathChoice`
case + `choosePath` routing, the new `.photoLibrarySetup` step and its `canGoBack`/`back`
transitions, and the scanned-code validator (`ScannedShareLink.validate` over `SharedLinkURL.parse`)
against a fake `CodeScanning` (no camera). XcodeBuildMCP `test_sim` (whole classes — single-`@Test`
runs false-green) for app-target UI: the three ordered options + helper text, the iCloud path
reaching the picker, the Scan-QR affordance on the shared-link path, and the existing onboarding
UITests staying green. Full XCUITest before merge (standing rule). Camera QR **end-to-end is a
manual device gate** (SC-220-07), with the camera-permission-denied fallback.

**Target Platform**: iPadOS/iOS 17+ (`AVCaptureMetadataOutput` QR detection is iOS 7+; the whole
camera path is availability-safe on the 17 floor). iPad-first.

**Project Type**: Mobile app (SwiftUI, MVVM `@Observable`), SPM modules + app target.

**Performance Goals**: Camera preview runs at the normal capture frame rate; a well-formed QR reads
in ~1–2 s (not a hard SLA). No new load on the slideshow engine — sources join the existing
prefetch/restart machinery unchanged.

**Constraints**: camera used solely to decode a QR into a URL string — no photo captured, stored,
or uploaded (stated in `NSCameraUsageDescription`); HTTPS-only shared links enforced by
`SharedLinkURL.parse` **before** any network call (FR-220-06); no secrets outside the keychain /
secret store (FR-220-11); scanning behind a host-testable seam (FR-220-12); iCloud path reuses 900
unchanged (FR-220-03); welcome-screen-only scope — downstream steps untouched (FR-220-07);
English-only strings (FR-220-13).

**Scale/Scope**: ~4 OnboardingKit files touched (`OnboardingViewModel.swift` — path case + routing
+ transitions; `OnboardingStep.swift` — new case; new `CodeScanning.swift` seam; new
`ScannedShareLink.swift` validator), ~4 app-target files (`OnboardingChoiceView` rework, a new
`.photoLibrarySetup` case in `OnboardingFlowView`, a Scan-QR affordance in `SharedLinkSetupView`,
new `QRScannerView`), 1 pbxproj/plist change (`NSCameraUsageDescription`). ~4 new host test suites
+ UITest additions. One new manual device gate.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Test-First (NON-NEGOTIABLE)**: PASS — the OnboardingKit deltas are red-first by
  construction: adding `.photoLibrarySetup` to `OnboardingStep` breaks the exhaustive
  `choosePath`/`canGoBack`/`back`/flow switches until handled; the scanned-code validator is
  specified by failing host tests over a fake `CodeScanning` before the camera view exists. The
  camera capture itself is not host-testable (no red possible) and is therefore isolated to one
  view and covered by the manual device gate — the logic feeding it stays red-first.
- **II. Modular Isolation**: PASS — `AVFoundation` lives only inside `QRScannerView` behind the
  `CodeScanning` protocol (mirrors PhotoKit behind `PHKitGateway`, `UIScreen` outside PowerKit);
  the scanned-string→route logic is pure over `SharedLinkURL`; the iCloud path reuses the injected
  900 gateway seam. No hidden singletons.
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)**: PASS — no new secrets; the API key and any
  shared-link password stay in the keychain / `SharedLinkSecretStore`; a scanned URL carries no
  secret (a required password is still prompted, never embedded); the camera decodes to a URL, and
  nothing new is logged.
- **IV. Transport-Layer Security**: PASS — no app-managed transport is added (the camera is local);
  `SharedLinkURL.parse` rejects non-HTTPS before any request; the Immich TLS posture is untouched.
- **V. Respect Platform Boundaries**: PASS — camera permission denied/restricted and no-camera are
  first-class calm states with manual entry always available (never a dead end); Photos permission
  reuses 900's honest full/limited/denied surfaces; "camera can't run in the simulator" is accepted
  as a device gate, not worked around.
- **VI. Verifiable Acceptance Criteria**: PASS — SC-220-01…07 map to host tests (path routing,
  scanned-code validation, no-persist-on-invalid, startup parity), UI tests (three ordered options
  + helper text + Scan-QR affordance), and one scheduled real-device gate (camera end-to-end +
  denied fallback).
- **VII. Plain and Light by Default**: PASS — light decoration and calm welcoming copy only; no new
  imposed visual defaults; the paths flow into the existing calm picker/engine.

**Result**: PASS — no violations; Complexity Tracking intentionally empty. No new package (the
feature fits existing modules); the one new abstraction (`CodeScanning`) is required by II to keep
`AVFoundation` out of the host-tested logic.

## Project Structure

### Documentation (this feature)

```text
specs/220-onboarding-welcome/
├── plan.md              # This file
├── research.md          # Phase 0 — QR tech, the CodeScanning seam, iCloud step, startup parity,
│                        #   camera permission, scanned-link dedupe, Scan-QR placement
├── data-model.md        # Phase 1 — path choice + step additions, ScannedShareLink, transitions
├── quickstart.md        # Phase 1 — host / simulator / device validation gates mapped to FR/SC
├── contracts/
│   └── onboarding-welcome-surface.md   # Phase 1 — OnboardingKit deltas, CodeScanning seam,
│                                       #   welcome-screen UI contract, plist key
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
Packages/OnboardingKit/Sources/OnboardingKit/
├── OnboardingViewModel.swift    # OnboardingPathChoice + .photoLibrary; choosePath routing;
│                                #   canGoBack/back handle .photoLibrarySetup; finish() already OK
├── OnboardingStep.swift         # + .photoLibrarySetup case (forces the exhaustive-switch red)
├── CodeScanning.swift           # NEW seam — protocol yielding a decoded String; NO AVFoundation
├── ScannedShareLink.swift       # NEW — pure validator: decoded String → parsed link | invalidCode
│                                #   (wraps SharedLinkURL.parse; host-tested, no camera)
└── StartupGate.swift            # UNCHANGED — already routes .photoLibrary-only → .done (900, R5)

Packages/OnboardingKit/Tests/OnboardingKitTests/   # new suites (path/step/validator)

OwnFrame/Onboarding/
├── OnboardingChoiceView.swift   # REWORK — three friction-ordered options + welcoming copy +
│                                #   light decoration; iCloud row → choosePath(.photoLibrary)
├── OnboardingFlowView.swift     # + .photoLibrarySetup → PhotoAlbumPickerView (finish → .done)
├── SharedLinkSetupView.swift    # + "Scan QR" affordance presenting QRScannerView
├── QRScannerView.swift          # NEW — the ONLY AVFoundation code; conforms CodeScanning,
│                                #   handles camera auth denied / no-camera → calm + manual entry
└── PhotoAlbumPickerView.swift   # REUSED unchanged (900)

OwnFrame.xcodeproj/project.pbxproj   # + INFOPLIST_KEY_NSCameraUsageDescription
```

**Structure Decision**: No new package. The host-testable logic (third path, new step, scanned-code
validator, the `CodeScanning` protocol) lands in the existing `OnboardingKit`; the single camera
implementation (`QRScannerView`) lives in the app target, exactly like PhotoKit stays behind
`PHKitGateway` and `UIScreen` stays out of PowerKit. The iCloud path reuses 900's
`PhotoAlbumPickerView` + `SourceLibraryViewModel.addPhotoLibrarySource`; the shared-link path reuses
110/120/210's resolve + secret store + dedupe.

## Complexity Tracking

> No constitution violations — table intentionally empty.
