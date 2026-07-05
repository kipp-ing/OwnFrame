# Implementation Plan: Home Assistant Full Control (MQTT)

**Branch**: `710-ha-full-control` (working branch `feat/710-ha-full-control`) | **Date**: 2026-07-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/710-ha-full-control/spec.md`

## Summary

Grow `HAControlKit`'s entity set from today's 3 (`playback`, `brightness`, `album`) to the full
19: every `ThemeSettings` field (9), `next`/`previous` buttons (2), the current photo as an image
+ metadata sensor (2), and 3 diagnostic sensors. `RemoteControlling` splits into three focused
protocols so the coordinator stays free of `ThemeKit`/`ImmichClient`/`SlideshowKit` types; the
existing `SlideshowRemoteControlAdapter` (the one place already allowed to import all of them)
implements all three. `HAControlCoordinator` gains a generic validation-matrix apply/echo path
for select/number/switch entities, a loop-safe suppress-flag for remote-triggered echoes, and a
bounded LRU metadata cache mirroring `SlideshowKit.ImageCache`'s existing pattern. The
`ThemeSettingsStore`, `SlideshowViewModel` (`showNext`/`showPrevious`/`currentAssetID`/`phase`)
and `ImmichAPI` (`assetInfo`/`thumbnail`) surfaces this needs already exist unchanged — this
feature only adds the HA-facing wiring around them, plus one small new non-secret preference
(image publishing enabled + byte cap) surfaced in the existing broker-setup Settings screen.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: SwiftUI, Foundation, Swift Testing; existing packages ImmichClient,
ThemeKit, SlideshowKit, PowerKit, HAControlKit, BrokerSetupKit

**Storage**: No new secret storage. One new non-secret preference (`HAPublishOptions`:
image-publishing enabled flag, image source, byte cap) via a UserDefaults-backed store in
`HAControlKit`, mirroring `ThemeKit`'s `ThemeSettingsStore`/`UserDefaultsThemeStore` pattern.
Everything else persists exactly where it already does (`ThemeSettingsStore` for settings,
Keychain-backed `BrokerConfigStore` for broker credentials, unchanged).

**Testing**: Swift Testing (`@Test`) for all `HAControlKit` and adapter logic (host `swift test`),
against a fake `MQTTTransport`, fake `ImmichAPI`, and fake `RemoteControlling`-family protocols —
same harness as the existing `HAControlCoordinatorTests`/`HADiscoveryTests`; XcodeBuildMCP (app
target + simulator) to verify the `SlideshowRemoteControlAdapter` wiring and the new broker-setup
toggle render correctly.

**Target Platform**: iPadOS 18+ (iPhone optional)

**Project Type**: Mobile app (SwiftUI, MVVM with `@Observable`), Swift Package Manager modules

**Performance Goals**: a settings round-trip (command → apply → echo) is exactly one state
publish (SC-710-02); photo-change image/metadata publish is a detached side effect that adds zero
delay to the visible slide transition (SC-710-04).

**Constraints**: TLS unchanged; no secrets in logs/UserDefaults; image payloads capped (default
512 KB, thumbnail source), downscale-then-skip-with-log if still over cap; every state topic
retained except the image topic and the `current_photo` sensor's state topic (both republished on
announce instead, per the Clarifications in spec.md); enum raw values are a stable, unlocalized
external API from here on.

**Scale/Scope**: 19 HA entities per device (3 existing + 9 settings + 2 buttons + 1 image + 1
sensor + 3 diagnostics); metadata cache bounded to a small LRU (same order of magnitude as
`ImageCache`'s existing bound, e.g. a few dozen entries — a typical album is a few hundred to a
few thousand photos, so this trades a handful of re-fetches on a long shuffle cycle for flat
memory use over a multi-day/week session, per the Clarifications).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Test-First (NON-NEGOTIABLE)**: PASS — every new entity/command/echo path lands red-first
  against the fake transport/API, extending the existing `HAControlCoordinatorTests` /
  `HADiscoveryTests` suites; no implementation before a failing test.
- **II. Modular Isolation**: PASS — the `RemoteControlling` split keeps `HAControlKit` ignorant of
  `ThemeKit`/`ImmichClient`/`SlideshowKit` types; `SlideshowRemoteControlAdapter` remains the only
  bridge. All new stores (`HAPublishOptionsStore`, metadata cache) are protocols with in-memory
  fakes; no hidden singletons.
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)**: PASS — no new secrets. Photo metadata
  (location names) is intentionally published by design (documented privacy note in README), not
  a credential; broker host/username/password paths are untouched.
- **IV. Transport-Layer Security**: PASS — reuses the existing TLS-validated MQTT connection; no
  new connection or exception.
- **V. Respect Platform Boundaries**: PASS — image/metadata publishing is driven by the same
  foreground-only slideshow ticker as today; no new background behavior; brightness/idle rules
  (topic 400) untouched.
- **VI. Verifiable Acceptance Criteria**: PASS — every FR-710 maps to a Swift Testing assertion
  (see quickstart.md); UI-observable pieces (broker-setup toggle) get an XcodeBuildMCP/XCUITest
  pass per this repo's "run full XCUITest before merge" practice.
- **VII. Plain and Light by Default**: PASS — every new entity is additive and either mirrors an
  existing in-app control (settings, next/previous) or is diagnostic/opt-in (image entity off by
  default); no change to the app's own visual defaults.

**Result**: PASS — no violations; Complexity Tracking left empty.

## Project Structure

### Documentation (this feature)

```text
specs/710-ha-full-control/
├── plan.md                     # This file
├── research.md                 # Phase 0 — resolves the 3 remaining Open Questions from spec.md
├── data-model.md               # Phase 1 — entities: HAEntity set, PhotoReport, HAPublishOptions
├── quickstart.md               # Phase 1 — end-to-end validation scenarios mapped to FR/SC
└── contracts/
    └── ha-mqtt-entities.md     # Phase 1 — topic scheme, entity map, command validation matrix
```

### Source Code (repository root)

```text
Packages/HAControlKit/Sources/HAControlKit/
├── HAEntityState.swift         # HAEntity: + order, duration, transition, kenBurns, fit, quality,
│                                #   clock, clockCorner, clockDate, next, previous, currentPhoto,
│                                #   currentPhotoImage, phase, photoCount, version
├── HATopics.swift               # component(for:) grows one case per new entity; image topic path
├── HADiscovery.swift             # discovery payloads: select/number/switch/button/image/sensor,
│                                #   entity_category: diagnostic for phase/photoCount/version
├── RemoteControlling.swift      # split into PlaybackControlling (today's pause/resume/brightness/
│                                #   album, unchanged), SettingsControlling (get/set ThemeSettings),
│                                #   PhotoReporting (current photo + metadata + phase + photoCount +
│                                #   version)
├── PhotoReport.swift             # NEW: value type for a photo-change event (assetID, imageData?,
│                                #   metadata, phase, photoCount)
├── HAPublishOptions.swift        # NEW: value type (imageEnabled, imageSource, byteCap) +
│                                #   HAPublishOptionsStore protocol + UserDefaults impl (mirrors
│                                #   ThemeKit's ThemeSettingsStore/UserDefaultsThemeStore pattern)
├── MetadataCache.swift            # NEW: bounded LRU cache, same shape as SlideshowKit.ImageCache
└── HAControlCoordinator.swift     # generic validation-matrix apply/echo for select/number/switch;
                                   #   suppress-flag / origin token for loop-safe echo; skips the
                                   #   image publish + logs when PhotoReport.imageData is nil (the
                                   #   downscale attempt itself is adapter-side, see below);
                                   #   announce() republishes photo + all state

Packages/ThemeKit/          — no changes (ThemeSettings/ThemeSettingsStore already sufficient)
Packages/ImmichClient/      — no changes (assetInfo/thumbnail already exist and are used by
                               PhotoInfoView.swift today for the same data shape)

Packages/HAControlKit/Tests/HAControlKitTests/
├── Fakes.swift                  # extend fake RemoteControlling-family + fake HAPublishOptionsStore
├── HAControlCoordinatorTests.swift  # + settings validation matrix, echo-loop-safety, photo report,
│                                #   reconnect-republish tests
└── HADiscoveryTests.swift        # + discovery payload snapshot per new entity

Immich Slideshow/Slideshow/
├── SlideshowRemoteControlAdapter.swift  # implement SettingsControlling (bridge onto
│                                #   ThemeSettingsStore, origin-token suppression so its own writes
│                                #   don't re-trigger onLocalChange) + PhotoReporting (observe
│                                #   SlideshowViewModel.currentAssetID, fetch assetInfo through the
│                                #   metadata cache; OWNS the downscale attempt on thumbnail() bytes,
│                                #   producing PhotoReport.imageData == nil when still over cap after
│                                #   downscaling — the coordinator never re-attempts downscaling)
└── BrokerSetupView.swift         # add the image-publishing toggle + byte-cap control (surfaces
                                   #   HAPublishOptionsStore), off by default
```

**Structure Decision**: All new protocol/topic/discovery/coordinator/cache logic stays inside
`HAControlKit` — the same boundary the package already has today (it knows `MQTTTransport` and its
own `RemoteControlling` family, nothing else). `SlideshowRemoteControlAdapter` remains the sole
class that imports `HAControlKit` alongside `ThemeKit`/`ImmichClient`/`SlideshowKit`/`PowerKit`,
now implementing three protocols instead of one. The new non-secret `HAPublishOptions` lives next
to `BrokerConfigStore` in `HAControlKit` (same "transport config" concern) rather than in
`ThemeKit` (display concern) or the Keychain-backed `BrokerSettings` (secrets concern), and its
toggle is surfaced in the existing `BrokerSetupView` Settings screen — resolves Open Question 5
from spec.md.

## Complexity Tracking

> No constitution violations — section intentionally empty.
