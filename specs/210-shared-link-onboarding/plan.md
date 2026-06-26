# Implementation Plan: Shared-Link Onboarding & iOS Share Sheet

**Branch**: `feat/210-shared-link-onboarding` | **Date**: 2026-06-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/210-shared-link-onboarding/spec.md`

## Summary

Make a **shared link a first-class, lowest-friction entry point**. First-run onboarding opens on a
**choice screen** ("Use a shared link" vs "Connect to server"); the shared-link path completes setup
with **only a link and no API key**, resolving it and asking for a password **only when the server
reports one is required**. The same resolve-first/ask-only-when-needed behavior replaces the always-on
optional-password field everywhere a link is added (onboarding + Settings → Sources). The app also
registers in the **iOS Share Sheet** via a thin **Share Extension**: sharing an Immich `/s/<slug>`
link hands the non-secret URL to the host app (through an **App Group**), which either pre-fills
shared-link setup (unconfigured) or adds the link as a source and makes it active (configured).
Finally, the album picker becomes **searchable** (name + date + photo count) and **independently
scrollable** with a **pinned primary action**, so 50+ albums stay usable.

Technical approach: reuse the existing `ServerConfig.shareKey` auth + `SharedLinkResolver` (already
distinguishes `passwordRequired` vs `wrongPassword`); add a `.choice` onboarding step and a
shared-link-only path; relax `StartupGate` so a shared-link active source is complete without an API
key; extend `Album` with `assetCount` + date for search; add a two-phase
"resolve → (prompt password) → save" flow to `SourceLibraryViewModel`; add a protocol-backed
App-Group "pending shared link" hand-off consumed by the host on launch/foreground; add a Share
Extension target whose only job is to capture the URL.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: SwiftUI, Foundation/URLSession, Swift Testing; existing packages
ImmichClient, OnboardingKit, SlideshowKit; new app extension target (Share Extension). No third-party
deps.

**Storage**: UserDefaults (non-secret) for the source library and the App-Group "pending shared link"
URL; Keychain for the API key (existing) and per-source shared-link passwords (existing 120 store).
App Group shared between host app and Share Extension.

**Testing**: Swift Testing (`@Test`) for logic on the host (`swift test`) — startup gate, two-phase
resolve flow, album search filter, incoming-link router, pending-link store, share-extension URL
extraction (factored into a pure function); XcodeBuildMCP app target + XCUITest for the SwiftUI
surfaces and the Share Sheet round trip.

**Target Platform**: iPadOS 18+ (iPhone optional)

**Project Type**: Mobile app (SwiftUI, MVVM with `@Observable`), Swift Package Manager modules + an
iOS app-extension target.

**Performance Goals**: a shared-in link reaches the slideshow (or the password prompt) within one
resolve round trip; album search filters a 50+ list interactively (no per-keystroke network); no
extra per-photo round trips.

**Constraints**: TLS always on (HTTPS-only links, no exception); no secrets in UserDefaults / the App
Group container / logs (only the non-secret URL crosses the process boundary; passwords are entered
in the host and go straight to the Keychain); foreground-only power behavior unchanged; calm/light
default preserved (the choice screen and search are quiet, no new always-on overlay).

**Scale/Scope**: 50+ albums in the picker; a handful of saved sources per device; one pending
shared-link hand-off at a time.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Test-First (NON-NEGOTIABLE)**: PASS — every slice lands red-first. Pure/host logic (gate
  routing, two-phase resolve state machine, album search predicate, incoming-link router, pending-link
  store, URL extraction) is Swift-Testing unit-tested; SwiftUI flows and the Share Sheet round trip
  are XCUITest-driven. No code before a red test.
- **II. Modular Isolation**: PASS — the pending-shared-link store and the resolver are protocols with
  in-memory fakes; the Share Extension's URL extraction is a pure function; album search is a pure
  predicate over `Album` values. No new singletons.
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)**: PASS — the Share Extension passes **only the
  non-secret share URL** via the App Group; shared-link passwords are entered in the host app and
  stored **only in the Keychain** (existing per-source store); neither the API key nor any password is
  written to the App Group container or logs; the resolved bearer key is never persisted.
- **IV. Transport-Layer Security**: PASS — shared-link resolution reuses the standard TLS-validated
  `URLSession`; links are HTTPS-only and normalized before any request; no TLS exception.
- **V. Respect Platform Boundaries**: PASS — Share Sheet acceptance uses a standard iOS Share
  Extension + App Group; the cold-start hand-off is a supported pattern (extension writes URL → host
  reads on launch/foreground); no new background behavior; power/foreground rules untouched.
- **VI. Verifiable Acceptance Criteria**: PASS — every FR-210 maps to a Swift-Testing or XCUITest
  assertion (see quickstart.md).
- **VII. Plain and Light by Default**: PASS — the choice screen, search field, and pinned action are
  calm and reduce friction; nothing is imposed and no new always-on overlay is added.

**Result**: PASS — no violations. The new Share Extension target is the minimal supported mechanism
for iOS Share Sheet membership (documented in Structure Decision), not a constitution deviation, so
Complexity Tracking is left empty.

## Project Structure

### Documentation (this feature)

```text
specs/210-shared-link-onboarding/
├── plan.md          # This file
├── research.md      # Phase 0 — decisions (flow shape, gate, album metadata, share extension, two-phase resolve)
├── data-model.md    # Phase 1 — entities, fields, state transitions
├── quickstart.md    # Phase 1 — end-to-end validation scenarios mapped to FR/SC
├── contracts/
│   └── shared-link-onboarding.md  # Phase 1 — protocol/interface contracts
└── checklists/
    └── requirements.md            # Spec quality checklist (/speckit-specify)
```

### Source Code (repository root)

```text
Packages/ImmichClient/Sources/ImmichClient/
├── Models.swift              # Album: add assetCount + date (startDate/endDate) for search; keep id/name back-compatible
└── SharedLinkResolver.swift  # resolve `/share/<key>` via key= and `/s/<slug>` via slug= (key-first, slug fallback); classify 401 by message so an unknown key/slug ≠ passwordRequired

Packages/OnboardingKit/Sources/OnboardingKit/
├── OnboardingStep.swift          # add `.choice` entry step (shared-link vs server)
├── StartupGate.swift             # shared-link active source ⇒ .done without an API key; empty ⇒ .choice
├── OnboardingViewModel.swift     # choice routing; shared-link-only path (resolve → pw-if-needed → save active → finish); back()/canGoBack step navigation
├── SourceLibraryViewModel.swift  # two-phase add: resolve(nil) → .needsPassword | .resolved | .error; confirm(password); dedup+activate
├── AlbumSearch.swift             # NEW: pure predicate filtering [Album] by name + date + count
├── IncomingSharedLink.swift      # NEW: route a pending share URL → onboarding pre-fill | add+activate | switch-to-existing
└── PendingSharedLinkStore.swift  # NEW: protocol + App-Group UserDefaults impl (non-secret URL hand-off)

Immich Slideshow/
├── Immich_SlideshowApp.swift           # onOpenURL / scenePhase: consume pending shared link; wire choice path
├── Onboarding/OnboardingChoiceView.swift (NEW)   # first screen: shared link vs server, with descriptions
├── Onboarding/SharedLinkSetupView.swift (NEW)    # shared-link-only entry: link → (pw sheet if needed) → start
├── Onboarding/ConnectionStepView.swift           # add concise description copy (US5)
├── Onboarding/OnboardingFlowView.swift           # NavigationStack: Back affordance for every step after .choice (canGoBack → back())
├── Onboarding/SourceStepView.swift               # resolve-first shared-link section; the reusable searchable+subscrollable album picker (search + internal scroll + pinned select-then-confirm)
└── Slideshow/SourceLibraryView.swift             # Settings → Sources: same resolve-first add-link flow AND the same reusable album picker (no separate unsearchable album-add screen)

Immich SlideshowShareExtension/ (NEW target)
├── ShareViewController.swift     # capture the shared URL, write to App Group, hand off to host
├── ShareLinkExtraction.swift     # NEW: pure URL-extraction helper (host-unit-tested)
└── Info.plist                    # NSExtension activation rule: accept public.url

Immich Slideshow.xcodeproj/project.pbxproj
└── new Share Extension target + App Group entitlement on host & extension; URL scheme for hand-off
```

**Structure Decision**: Reuse the existing per-module packages. Config/flow types (`OnboardingStep`,
`StartupGate`, `OnboardingViewModel`, `SourceLibraryViewModel`, the new `AlbumSearch`,
`IncomingSharedLink`, `PendingSharedLinkStore`) live in **OnboardingKit** (the config/onboarding
domain). Album metadata + shared-link fetch stay in **ImmichClient**. The **Share Extension** is a new
iOS app-extension target — the only supported way to appear in the iOS Share Sheet — kept deliberately
thin: it extracts the URL and hands it to the host via an **App Group**; all resolution, routing, and
Keychain work happens in the host app, so no secrets and no network cross into the extension. The host
consumes the pending link on launch/foreground (cold-start safe).

## Complexity Tracking

> No constitution violations — section intentionally empty. (The Share Extension target is the minimal
> supported mechanism for Share Sheet membership; see Structure Decision.)
