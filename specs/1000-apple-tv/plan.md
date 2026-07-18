# Implementation Plan: Apple TV (tvOS Target)

**Branch**: `1000-apple-tv` | **Date**: 2026-07-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification `specs/1000-apple-tv/spec.md` (FR-1000-01…12, SC-1000-01…08,
US1–US4). Companion amendments to 120/200/600 (iPad-side KVS/CloudKit writers) land here as
noted in the spec's Assumptions.

## Summary

Second app target (`Immich SlideshowTV`) in the same app record (universal purchase, shared
bundle id family) that plays the same slideshow on tvOS 17+, reusing every SPM package. The
port is app-target wiring behind existing seams: a **software-dim** `ScreenControlling` (black
compositing, no panel API), **Siri-Remote-first** chrome (focus/`onMoveCommand`/
`onExitCommand`/`onPlayPauseCommand` replacing touch), **purgeable-storage discipline**
(Caches only, no Documents), a **distinct HA device identity**, and a new **config-sync**
channel — non-secrets over iCloud key-value storage, secrets over CloudKit encrypted fields
(constitution III v1.1.0) — with the iPad app as the companion writer. Real-hardware CloudKit
decryption proof (SC-1000-08 spot-check), the 24h soak (SC-1000-05), and the remote-only
walkthrough on real hardware (SC-1000-02) are explicit **device gates**, unit-verified behind
fakes this session.

## Technical Context

**Language/Version**: Swift 6, SwiftUI, `@Observable` MVVM.

**Primary Dependencies**: existing local SPM packages (ImmichClient, OnboardingKit,
SlideshowKit, PowerKit, HAControlKit+HAControlMQTT, BrokerSetupKit, ThemeKit, PhotoSourceKit);
**new** `ConfigSyncKit` (KVS + CloudKit sync stores, fakes, publisher/consumer). PhotoLibraryKit
stays iOS-only (Photos source out of scope on tvOS — spec) and gains `#if os(iOS)` guards so it
still *compiles* for tvOS. AppIntentsKit not linked on tvOS this round (Shortcuts = roadmap).

**Storage**: non-secret config in UserDefaults (existing six stores, all inject `UserDefaults`);
secrets in the local tvOS keychain (three existing seams). Sync: `NSUbiquitousKeyValueStore`
(non-secret) + CloudKit private DB `CKRecord.encryptedValues` (secret). Image data + snapshots
in Caches only.

**Testing**: Swift Testing on host for every new seam (sync stores, dim model, remote-chrome
model, identity, publisher/consumer) with fakes; XcodeBuildMCP builds/tests the tvOS app on the
**Apple TV 4K (3rd generation)** sim (tvOS 26.5 runtime, floor tvOS 17); iOS app suite stays
green on an iOS 26.x iPad sim.

**Target Platform**: tvOS 17 floor (Apple TV HD 2015+), built against tvOS 26.5 SDK; Liquid
Glass availability-gated exactly as on iOS via `View+Compat.swift` (its `#available(iOS…)`
checks are simply false on tvOS → material/bordered fallbacks).

**Project Type**: existing SwiftUI app + local SPM packages; **new** second app target + one new
package.

**Constraints**: no panel/brightness API (software dim only); foreground-only idle-timer;
UserDefaults < 100 KB (SC-1000-07), 500 KB platform ceiling; Menu never traps (FR-1000-03);
secret/non-secret channel split is a hard boundary (FR-1000-05, SC-1000-08); no App-Group /
`onOpenURL` / Share-Extension dependency on tvOS (FR-1000-09).

## Architecture decisions (grounded in recon)

1. **One shared app-source tree, conditional compilation.** The slideshow/chrome/onboarding
   SwiftUI lives in the app target (`Immich Slideshow/`), not in a package. The tvOS target
   **shares** that source via the file-system-synchronized group, **excludes** the three
   genuinely iOS-only files (`Onboarding/QRScannerView.swift` [camera], `Onboarding/
   PhotoAlbumPickerView.swift` [Photos source], `Slideshow/UIScreenController.swift` [iOS
   screen]) through a synchronized-group build-file exception set, and adds `#if os(tvOS)`
   branches inside the rest for the handful of iOS-only touchpoints (`.statusBarHidden`,
   `DragGesture`, `UIApplication.openSettingsURLString`, `UIImage` scaling, `UIDevice`
   identity). tvOS-specific files (App entry, `SoftwareDimScreenController`, remote-chrome
   wiring, tvOS onboarding shell) live in a new `Immich SlideshowTV/` synchronized group.
   Rationale: honors constitution II (no per-platform package fork; differences in the app
   target behind seams) without a risky UI-layer extraction refactor.

2. **`ConfigSyncKit` (new package)** holds the sync seam so both app targets + host tests use
   it: `SyncedConfig` (non-secret snapshot), `ConfigSyncStore` (+ `UbiquitousKVSConfigSyncStore`
   + `InMemoryConfigSyncStore`), `SecretSyncStore` (+ `CloudKitSecretSyncStore` +
   `InMemorySecretSyncStore`), and the companion `ConfigPublisher` (iPad) / `ConfigConsumer`
   (tvOS). All logic host-testable behind protocols; the KVS/CloudKit adapters stay thin and
   only need to *compile* for the unit tier (FR-1000-11/12).

3. **`ScreenControlling` (2-prop seam, PowerKit is UIKit-free)** gets a tvOS
   `SoftwareDimScreenController`: `brightness` drives an `@Observable` dim value (0…1) that the
   slideshow composites as a black overlay at opacity `1 − brightness`; `isIdleTimerDisabled`
   maps to tvOS `UIApplication.isIdleTimerDisabled` (which exists on tvOS). PowerKit/PowerManager
   unchanged. FR-1000-07 bypass (`SlideshowSettingsView.currentScreenBrightness()` reading
   `UIScreen`) is eliminated — brightness is read through the seam on both platforms.

4. **HA distinct identity** is injected at the app entry (kits are identity-neutral): tvOS
   supplies a distinct `deviceID` (own MQTT topics/identifiers/unique_id) and `deviceName`
   (e.g. "Photo Frame (Apple TV)"). No kit changes (FR-1000-08).

5. **Packages gaining `.tvOS(.v17)`**: PhotoSourceKit, ThemeKit, PowerKit, ImmichClient,
   OnboardingKit, HAControlKit, BrokerSetupKit, SlideshowKit, PhotoLibraryKit(+iOS guards),
   ConfigSyncKit. `swift-nio-ssl`/`mqtt-nio` tvOS compilation is a spike-verify item (T004).

## Constitution Check

*GATE: evaluated 2026-07-18 pre-Phase-0 — PASS.*

- **I. Test-First**: every new seam starts red (host Swift Testing) before impl; tasks name the
  red test. tvOS UI verified on the sim via XcodeBuildMCP.
- **II. Modular, no per-platform package fork**: packages stay single-source; platform
  differences live in the app targets behind the `ScreenControlling`/transport/store seams and
  `#if os` inside app-target files. New logic goes in `ConfigSyncKit` behind protocols.
- **III. No Secrets in Plaintext (v1.1.0)**: secrets only in the local keychain at rest and, in
  flight, only in CloudKit `encryptedValues`; never in KVS/UserDefaults/plaintext CK fields.
  App implements no cryptography (system-managed keys). SC-1000-08 asserted against fakes;
  real-container spot-check is a device gate.
- **IV. TLS**: MQTT stays TLS via Network.framework (mqtt-nio 2.13); no TLS disablement.

## Project Structure

```
Packages/ConfigSyncKit/                      # NEW
  Sources/ConfigSyncKit/{SyncedConfig,ConfigSyncStore,UbiquitousKVSConfigSyncStore,
    SecretSyncStore,CloudKitSecretSyncStore,ConfigPublisher,ConfigConsumer,InMemory*}.swift
  Tests/ConfigSyncKitTests/*.swift
Immich SlideshowTV/                           # NEW synchronized group (tvOS-only files)
  ImmichSlideshowTVApp.swift  SoftwareDimScreenController.swift  TVRemoteChrome.swift
  TVOnboarding*.swift  ...
Immich Slideshow/                             # shared source (conditionalized) + iOS-only excl.
Immich Slideshow.xcodeproj                    # + tvOS target, scheme, entitlements (via xcodeproj gem)
```

## Phase → Story mapping

- **Setup / Foundational** (blocks all): package platforms, `ConfigSyncKit`, tvOS target creation.
- **US1 (P1) MVP**: software-dim screen, remote-first chrome, tvOS app plays the slideshow.
- **US3 (P2)**: purge tolerance as the normal case (largely existing 320).
- **US4 (P2)**: distinct HA identity + tvOS HA wiring.
- **US2 (P1, largest)**: sync stores + companion publisher (iPad) + tvOS consumer + onboarding.
- **Polish**: footprint audit, full verification gate, docs, device-gate register.

## Session scope & device gates

Full spec incl. companion writers, unit-verified behind fakes and on the tvOS **simulator**.
Deferred as **real-hardware device gates** (cannot be proven without an Apple TV + real iCloud
container): SC-1000-08 real-container secret-field spot-check, SC-1000-05 24h burn-in soak,
SC-1000-02 remote-only walkthrough on hardware, and CloudKit decryption-on-tvOS proof
(spec Assumptions). Registered in quickstart.md.
