# Implementation Plan: Source Library (multiple switchable slideshow sources)

**Branch**: `120-source-library` (working branch `spec/120-source-library`) | **Date**: 2026-06-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/120-source-library/spec.md`

## Summary

Generalize today's single `AppConfiguration.selectedAlbumID` into a persisted, ordered **Source
Library** with exactly one active source. A `Source` is an Immich album (API-key header auth, current
behavior) or an Immich shared/public album link (`?key=` query auth, verified in `110`). The active
source is resolved to a `ServerConfig` + album id and handed to the **unchanged** slideshow engine
(albums → assets → preview). The library is switchable from onboarding, Settings, and the existing
Home Assistant select entity; existing installs migrate transparently to a one-entry library.

Technical approach: add an auth-mode to `ServerConfig` so one `ImmichClient` serves both header and
query auth; add a shared-link resolver (`me?slug=[&password=]` → key + album id); add a
`SourceLibrary` value type + `SourceLibraryStore` (UserDefaults, non-secret) with migration; store
shared-link passwords in a per-source Keychain store; back the HA select and the onboarding/Settings
UI with the library.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: SwiftUI, Foundation/URLSession, Swift Testing; existing packages
ImmichClient, OnboardingKit, SlideshowKit, HAControlKit, ThemeKit, PowerKit

**Storage**: UserDefaults for non-secret library metadata (labels, kinds, album ids, base URLs,
slugs, active id); Keychain for the API key (existing) and per-source shared-link passwords

**Testing**: Swift Testing (`@Test`) for logic (host `swift test`); XcodeBuildMCP app target +
XCUITest for the SwiftUI surfaces

**Target Platform**: iPadOS 18+ (iPhone optional)

**Project Type**: Mobile app (SwiftUI, MVVM with `@Observable`), Swift Package Manager modules

**Performance Goals**: switching the active source restarts playback within one slideshow tick; no
extra per-photo round trips beyond the existing preview fetch; shared-link resolve is one call per
activation

**Constraints**: TLS validation always on (no exceptions); foreground-only power effects unchanged;
no secrets in UserDefaults/logs; calm default preserved (switching is explicit, no new overlay)

**Scale/Scope**: a handful of saved sources per device; album sizes up to a few hundred assets (the
verified shared links carry 59 and 83 assets)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Test-First (NON-NEGOTIABLE)**: PASS — every slice lands red-first. Logic (model, migration,
  resolver, auth-mode, HA adapter) is host-unit-tested; UI is driven by XCUITest. No code before a
  red test.
- **II. Modular Isolation**: PASS — `SourceLibraryStore` and `SharedLinkSecretStore` are protocols
  with in-memory fakes; shared-link resolution goes through the injected `ImmichAPI`; no new
  singletons.
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)**: PASS — shared-link passwords only in Keychain
  (per-source); the resolved bearer key is never persisted and never logged; the `me` response (which
  echoes the password) is never logged.
- **IV. Transport-Layer Security**: PASS — shared-link access reuses the standard TLS-validated
  `URLSession`; `?key=` is a query param over HTTPS, no TLS change.
- **V. Respect Platform Boundaries**: PASS — no new background behavior; power/foreground rules
  untouched.
- **VI. Verifiable Acceptance Criteria**: PASS — every FR-120 maps to a Swift Testing or XCUITest
  assertion (see quickstart.md).
- **VII. Plain and Light by Default**: PASS — switching is explicit; no new always-on overlay; the
  calm default and single-active-source behavior are preserved.

**Result**: PASS — no violations; Complexity Tracking left empty.

## Project Structure

### Documentation (this feature)

```text
specs/120-source-library/
├── plan.md          # This file
├── research.md      # Phase 0 — decisions (auth-mode, persistence, migration, HA, resolver)
├── data-model.md    # Phase 1 — Source / SourceLibrary / stores / errors
├── quickstart.md    # Phase 1 — end-to-end validation scenarios mapped to FR/SC
└── contracts/
    └── source-library.md   # Phase 1 — protocol/interface contracts
```

### Source Code (repository root)

```text
Packages/ImmichClient/Sources/ImmichClient/
├── ServerConfig.swift        # add auth mode: .apiKey(header) | .shareKey(query)
├── ImmichClient.swift        # apply header vs ?key= per auth mode on every request
├── ImmichAPI.swift           # add shared-link resolve to the protocol (or a sibling resolver)
├── SharedLinkResolver.swift  # NEW: me?slug=[&password=] -> (key, albumID, expiresAt)
└── ImmichError.swift         # add invalidShareLink / shareLinkExpired / wrongPassword

Packages/OnboardingKit/Sources/OnboardingKit/
├── Source.swift              # NEW: Source (album | sharedLink), value type
├── SourceLibrary.swift       # NEW: ordered [Source] + activeID, with operations
├── SourceLibraryStore.swift  # NEW: protocol + UserDefaults impl + migration from selectedAlbumID
├── SharedLinkSecretStore.swift # NEW: protocol + Keychain impl (per-source password)
└── AppConfiguration.swift    # keep baseURL + apiKey; selectedAlbumID superseded by the library

OwnFrame/
├── OwnFrameApp.swift # build ImmichAPI + albumID from the ACTIVE source; wire HA/library
├── Onboarding/SourceStepView.swift (NEW)                  # add a source (album or shared link)
├── Slideshow/SourceLibraryView.swift (NEW)                # manage list in Settings
└── Slideshow/SlideshowSettingsView.swift                  # surface the source manager

Packages/HAControlKit/Sources/HAControlKit/
└── (RemoteControlling / HAControlCoordinator)             # select options/state from the library
   OwnFrame/Slideshow/SlideshowRemoteControlAdapter.swift  # back select with the library
```

**Structure Decision**: Reuse the existing per-module packages. The `Source`/`SourceLibrary` config
types live in **OnboardingKit** (alongside `AppConfiguration`/`ConfigStore`, the config domain). The
shared-link **fetch/auth** lives in **ImmichClient**. The app composes them: the active `Source` →
`ServerConfig` (auth) + album id → existing `ImmichClient` + `SlideshowViewModel` (no engine change).
HA select and the onboarding/Settings UI are backed by the library.

## Complexity Tracking

> No constitution violations — section intentionally empty.
