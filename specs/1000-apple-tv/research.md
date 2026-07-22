# Research: Apple TV (1000)

## Environment (verified 2026-07-18)

- tvOS **26.5** build SDK present; tvOS 26.5 **simulator runtime** downloaded; sim device
  **Apple TV 4K (3rd generation)** `C3A8C51D-0CA6-45B2-BE17-1B11E1BF7AC8`. Floor stays tvOS 17.
- `xcodeproj` gem 1.28.1 installed (user-install, Ruby 2.6) → tvOS target added programmatically.

## Seam facts (from recon)

- **PowerKit** is 100% UIKit-free; `ScreenControlling` = `{ brightness: Double; isIdleTimerDisabled:
  Bool }`. Concrete `UIScreenController` lives in the **app target** — replaced on tvOS, not
  patched. `UIApplication.isIdleTimerDisabled` exists on tvOS; `UIScreen.brightness` /
  `wantsSoftwareDimming` do not.
- **Slideshow UI is in the app target** (`OwnFrame/Slideshow/…`), not SlideshowKit
  (which holds the ViewModel + KenBurnsDrift). Chrome state = `SlideshowView.chromeVisible`;
  auto-hide 4.5s; input = one `TapGesture` (toggle) + `DragGesture(40)` (next/prev). Ken Burns
  is TimelineView-driven (tvOS-safe) *(superseded 2026-07-18: now a shared scoped-animation
  `KenBurnsMotionModifier` in SlideshowKit)*. tvOS blockers: `.statusBarHidden`, `DragGesture`,
  `UIDevice.userInterfaceIdiom` (needs a `.tv`/idiom case for clock sizing).
- **HAControlKit/BrokerSetupKit** are Foundation/NIO-only; identity (`deviceID`/`deviceName`)
  injected from the app entry (`OwnFrameApp.swift:239/:424`). mqtt-nio pinned 2.13.0;
  HAControlMQTT also links `swift-nio-ssl` (tvOS build to be confirmed in T004).
- **Persistence**: six non-secret UserDefaults stores (all inject `UserDefaults`), three keychain
  seams for secrets. No `NSUbiquitousKeyValueStore`/CloudKit today — sync is greenfield.
  `SourceLibrary` blob is entirely non-secret.
- **Project**: file-system-synchronized groups (four root groups); app Info.plist synthesized via
  `INFOPLIST_KEY_*`; 10 local packages linked; Share Extension is a separate iOS-only target
  (embedded), excluded from tvOS.

## Decisions

- Share app source across targets with a 3-file exclusion set + `#if os(tvOS)` (vs. extracting a
  UI package — rejected as too large/risky for one session).
- New `ConfigSyncKit` package for the sync seam (host-testable, adapters thin).
- Keep PhotoLibraryKit iOS-only in behavior but `#if os(iOS)`-guarded so it compiles for tvOS
  (satisfies SC-1000-04 without forking package code).

## Open risks (spike-verify / device gates)

- `swift-nio-ssl` tvOS compile (T004). CloudKit `encryptedValues` decrypt on real tvOS hardware
  (device gate). 24h soak + remote-only walkthrough need hardware.
