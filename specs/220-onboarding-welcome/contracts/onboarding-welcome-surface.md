# Contract: Onboarding Welcome Surface (220)

The internal API + UI contract this feature adds or changes. Everything not listed is reused
unchanged. Package symbols are the tested contract; the app-target UI contract is what the XCUITests
and the manual device gate assert.

## OnboardingKit (host-tested)

### `OnboardingPathChoice`

- Gains `.photoLibrary`. Existing `.sharedLink` / `.server` unchanged.

### `OnboardingViewModel`

- `choosePath(.photoLibrary)` → sets `step = .photoLibrarySetup` (clears `errorMessage`).
- `choosePath(.sharedLink)` / `choosePath(.server)` → unchanged.
- `canGoBack` → `true` for `.photoLibrarySetup`.
- `back()` from `.photoLibrarySetup` → `.choice`.
- `finish()` → unchanged; for a `.photoLibrary` active source it sets `step = .done` without writing
  album config (the `if case .album` guard is skipped). Pinned by a test.

### `OnboardingStep`

- Gains `.photoLibrarySetup`. All switches over `OnboardingStep` must handle it (compile-red until
  they do).

### `ScannedShareLink` (new)

- `static func validate(_ decoded: String) -> Result<ParsedSharedLink, InvalidCodeReason>`
  - Valid Immich share link (HTTPS, `/s/<slug>` or last-segment fallback) → `.success((baseURL, slug))`
    — byte-identical to `SharedLinkURL.parse`.
  - Not a URL → `.failure(.notAURL)`; non-HTTPS → `.failure(.notHTTPS)`; URL but no share shape →
    `.failure(.notAShareLink)`.
  - Pure: no network, no persistence, no camera.

### `CodeScanning` (new seam)

- Protocol abstracting "decode a string from the camera". Real impl = app-target `QRScannerView`;
  host tests inject a fake yielding scripted strings. No AVFoundation import in OnboardingKit.

## App target

### Welcome screen (`OnboardingChoiceView`) — UI contract

- Presents **exactly three** options, top → bottom, in friction order:
  1. **iCloud album** — recommended/easiest; helper text names playing from an album on this iPad /
     in iCloud, no server needed. Tap → `choosePath(.photoLibrary)`.
  2. **Shared album link** — helper text: paste or scan an Immich share link, no account needed.
     Tap → `choosePath(.sharedLink)`.
  3. **Server + API key** — advanced; helper text: sign in with server address + API key. Tap →
     `choosePath(.server)`.
- Each option exposes concise, non-technical helper text (extends the 210
  `OnboardingDescriptionsUITests` contract to three rows).
- No Back affordance on this screen (unchanged 210 contract).
- Light decoration only; calm/light default (constitution VII).

### iCloud step (`OnboardingFlowView` + `.photoLibrarySetup`)

- Renders the reused `PhotoAlbumPickerView` (900 full-access gate, limited "Selected Photos"
  fallback, denied calm message). On album add → `finish()` → slideshow. Back → `.choice`.

### Scan QR (`SharedLinkSetupView` + `QRScannerView`)

- The shared-link entry offers manual entry **and** a "Scan QR" affordance.
- Scan QR presents `QRScannerView`; a decoded string flows through `ScannedShareLink.validate` and,
  when valid, the existing resolve path (password only if required). Invalid → calm message, nothing
  persisted, manual entry still available.
- Camera authorization denied/restricted or no camera → calm one-liner; manual entry remains.

### Platform / plist

- New `INFOPLIST_KEY_NSCameraUsageDescription` (English): the camera is used only to read a shared-
  album QR code; no photo is captured or stored. Sits beside the existing
  `NSPhotoLibraryUsageDescription`.

## Invariants preserved (regression contract)

- Shared-link-only path still reaches the slideshow with **no API key** (210/US1).
- Server path and all downstream steps (`connection` → `source` → `confirm`) unchanged (FR-220-07).
- Sources from every path land in the one `SourceLibraryStore`; HA source-select and App-Intent
  source options see them like any other source (FR-220-10).
- iOS Share-Sheet acceptance unaffected (FR-220-09).
- No secret in code / UserDefaults / logs; scanned URLs carry none (FR-220-11).
