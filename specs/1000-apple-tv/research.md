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

## iCloud KVS facts (verified online 2026-07-28, prompted by issue #51)

Researched while diagnosing why FR-1000-06 never worked on hardware. These are the facts T026
depends on — recorded here so the entitlement change does not have to re-derive them.

- **The entitlement is `com.apple.developer.ubiquity-kvstore-identifier`**, default value
  `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`. It is *not* the same key as
  `com.apple.developer.ubiquity-container-identifiers` (that one is iCloud **document**
  storage, which tvOS does not have — see spec.md's platform constraints). The authoritative
  name is also stated verbatim by the runtime error the app logs on every device launch:
  *"Please specify your store identifier in the `com.apple.developer.ubiquity-kvstore-identifier`
  entitlement."*
- **Without the entitlement `NSUbiquitousKeyValueStore` degrades to a silent local no-op** — it
  does not throw, does not crash, and returns values you just wrote. This is precisely why the
  gap survived: every test injects `InMemoryConfigSyncStore`, and the real store *looks* like it
  works when read back on the same device.
- **The provisioning profile's entitlement value must match the entitlements file exactly**, or
  code signing fails. So T026 is a portal change plus a project change, not a plist edit alone.
- **Same bundle ID ⇒ one shared store across iOS and tvOS.** Both app targets are already
  `ing.kipp.Immich-Slideshow` (pbxproj `PRODUCT_BUNDLE_IDENTIFIER` at :695 and :944), so the
  default identifier resolves to the same store on both platforms with no explicit value. This
  is the mechanism behind the spec's "same bundle-ID family also unlocks iCloud KVS sharing"
  assumption.
- **Limits: 1 MB total per user, 1 MB per value, 1024 keys max, key names ≤ 64 bytes UTF-8.**
  Ample for `SyncedConfig` — FR-1000-04 already caps the whole UserDefaults footprint at 100 KB
  (SC-1000-07), and the source-library JSON is the only field that grows. No redesign needed;
  note the *key-name* limit if fields are ever added dynamically.
- `synchronize()` is best-effort/optional on modern OSes (changes propagate on their own); the
  existing `UbiquitousKVSConfigSyncStore` call is harmless.

Sources:

- [Enabling iCloud Storage — Entitlement Key Reference (Apple)](https://developer.apple.com/library/content/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingiCloud.html)
- [Designing for Key-Value Data in iCloud (Apple)](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForKey-ValueDataIniCloud.html)
- [NSUbiquitousKeyValueStore (Apple docs)](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore)
- [Sharing NSUbiquitousKeyValueStore across platforms — Apple Developer Forums](https://developer.apple.com/forums/thread/714826)
- [Missing kvstore entitlement, observed symptom — UICKeyChainStore #62](https://github.com/kishikawakatsumi/UICKeyChainStore/issues/62)
