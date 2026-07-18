# Quickstart / Validation: Onboarding Welcome Overhaul (220)

Prerequisites: this branch is based on the `900-photo-library-source` tip (the photoLibrary source +
`PhotoAlbumPickerView` must be present). An iOS ≥17 simulator (pin `simulatorId`, clear
`simulatorName`). A physical iPad for the camera gate.

## Phase-1 gate — package logic (host-only)

`swift test` in `Packages/OnboardingKit`. Green means (SC-220-01/03/04, FR-220-01/04/06/12):

- **Path choice**: `choosePath(.photoLibrary)` → `step == .photoLibrarySetup`; existing
  `.sharedLink`/`.server` routing unchanged; `canGoBack` true and `back()` → `.choice` for
  `.photoLibrarySetup`.
- **Scanned-code validation** (`ScannedShareLink.validate` over a fake `CodeScanning`): a valid
  Immich share string → `.success((baseURL, slug))` identical to `SharedLinkURL.parse`; a non-URL /
  non-HTTPS / non-share string → the matching `InvalidCodeReason` with **nothing persisted and no
  network call**; a scanned valid link routes through the same resolver as a typed link.
- **Startup parity**: a `.photoLibrary`-only active source (no connection) → `StartupGate` returns
  `.done` (pins the reused 900 behaviour).
- **finish() parity**: with a `.photoLibrary` active source, `finish()` → `.done` and writes no album
  config.

## Phase-2 gate — app integration (simulator)

Via XcodeBuildMCP `test_sim`, whole classes (never a single `@Test`):

- **Welcome screen**: three options render in friction order (iCloud, shared link, server + key),
  each with concise helper text; no Back on the welcome screen (extends
  `OnboardingDescriptionsUITests` / `OnboardingBackUITests`).
- **iCloud path**: choosing iCloud reaches `PhotoAlbumPickerView`; picking an album reaches the
  slideshow with no connection/API key (extends the 900 `PhotoAlbumPickerUITests`, now via the
  welcome screen rather than the pre-connected `.source` step).
- **Shared-link path**: the Scan-QR affordance is present alongside manual entry; manual entry still
  reaches the slideshow with no API key; the camera view is not exercised here (no camera in sim).
- **Regression**: `SharedLinkOnboardingUITests`, `SourceOnboardingUITests`,
  `OnboardingBackUITests`, `ShareSheetIncomingUITests` stay green (FR-220-07/09, SC-220-06).
- Full XCUITest suite before merge (standing rule; broker-toggle flake: rerun `BrokerSetupUITests`
  isolated before suspecting the diff).

## Manual device checklist (real hardware — rides the 900/800 device day)

- [ ] **SC-220-02 / FR-220-04**: on the shared-link path, tap Scan QR, point at a real Immich
      shared-album QR → the link resolves and the slideshow starts; a password-protected album
      prompts once.
- [ ] **SC-220-04**: scan a non-Immich / arbitrary QR → calm "not an Immich share link" message,
      nothing persisted, manual entry still available.
- [ ] **SC-220-05 / FR-220-05**: decline the camera permission prompt → calm one-liner, manual link
      entry still works; re-enabling in Settings restores Scan QR.
- [ ] **SC-220-01**: fresh install → pick iCloud album on the welcome screen → grant Photos access →
      pick an album → slideshow plays; relaunch routes straight to the slideshow (no re-onboarding).
- [ ] **NSCameraUsageDescription** copy reads correctly in the system prompt (camera used only to
      read a shared-album QR).

## Rollback

The feature is additive and behind the welcome screen. Reverting the branch restores the two-option
choice screen; no persisted data migration is involved (source formats are unchanged).
