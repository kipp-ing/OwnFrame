# Tasks: Apple TV (tvOS Target) — 1000

**Input**: `specs/1000-apple-tv/` — plan.md, research.md, data-model.md, contracts/config-sync.md,
quickstart.md. Binds FR-1000-01…12, SC-1000-01…08, US1–US4.

**Method**: TDD (red host test named before each impl). **[inline]** = Claude owns (cross-cutting:
target/pbxproj, app entry, SwiftUI wiring, simulator gate). **[delegate]** = coding subagent
implements against a briefing (host-unit-testable, `swift test` green) → testing subagent verifies.
Commit after each green task/group. Full scope incl. iPad companion; real-hardware items are device
gates (quickstart.md), not blockers.

## Status (2026-07-18)

**Done + verified on the Apple TV 4K simulator:** T001–T022 (all user stories). US1 frame plays
(auto-cycle + real demo-link end-to-end); US2 onboarding (choice/shared-link/server) + real-source
routing + iCloud-KVS prefill/restore + secret hydration seam; US3 purge-tolerance; US4 HA parity
(TVRemoteControlAdapter Playback/Settings/PhotoReporting + coordinator with distinct identity +
broker onboarding + software-dim brightness + lifecycle). T012 FR-1000-07 bypass removed. iPad
companion (T021) publishes the full non-secret + secret payload to KVS/CloudKit on launch +
foreground; tvOS consumer restores it. `ThemeSettings` is Codable. All host suites green
(ThemeKit 31, ConfigSyncKit 21, SlideshowKit 182, PowerKit 19, HAControlKit 92, …); iOS + tvOS
sim builds green; full iOS XCUITest 120/0/2.

**Ken Burns smoothness redesign (2026-07-18, after the test-review fixes):** the micro-judder
report led to replacing per-frame TimelineView sampling with ONE scoped linear animation per
photo — shared `KenBurnsMotionModifier` in SlideshowKit (pan 16 iOS / 24 tvOS; deletes
`TVKenBurns` + the iOS `KenBurnsModifier`, resolving the byte-copy cleanup item) driven by the
pure `KenBurnsAnimator` step machine, plus a `DisplayImagePreparing`/`DecodedImageStore`
decode-ahead seam (all prefetch tiers + show path) that eliminated the measured 27–35 ms
swap-boundary decode stall. Motion contract is unchanged and theorem-tested
(settle-exactly-at-swap); sim-verified sawtooth/fades/no-black-dip; perceived-smoothness ground
truth joins the existing device-day gates.

**Remaining (device-gated / follow-up, NO physical testing this session):** real MQTT connection
(needs a broker), real CloudKit secret sync (needs iCloud entitlements + account), tvOS clock
overlay + FR-1000-10 pixel-shift (not started — clock is off by default so US1 is unaffected),
current-photo capture-date on tvOS HA (would add PhotoSourceKit to the target), and the
real-hardware gates (SC-1000-02/05/06/08 + CloudKit-decrypt-on-tvOS proof + 24h soak).

## Phase 1: Setup

- [x] T001 [inline] Baseline green on `1000-apple-tv`: iOS app builds + full XCUITest/host suites
      pass (iOS 26.x iPad sim); `swift test` green for all packages on host. Confirm tvOS 26.5 sim
      `C3A8C51D…` boots. No code changes. **Gate before any port work.**

## Phase 2: Foundational (blocks all stories)

- [x] T002 [inline] Add `.tvOS(.v17)` to Package.swift for PhotoSourceKit, ThemeKit, PowerKit,
      ImmichClient, OnboardingKit, HAControlKit, BrokerSetupKit, SlideshowKit. `swift build` each
      still green on host.
- [x] T003 [delegate] PhotoLibraryKit: `#if os(iOS)`-guard the picker + `UIApplication` scene use
      (`PHKitGateway.swift:232`) so it compiles as a no-op on tvOS; add `.tvOS(.v17)`. Red test:
      tvOS-guard path returns `.unavailable` without touching UIKit. `swift build`/`swift test`
      green on host; ManifestKit builds for tvOS dest (checked in T022).
- [x] T004 [delegate] Create `Packages/ConfigSyncKit` (Package.swift iOS17/tvOS17/macOS14; target +
      testTarget; empty stub type + one passing test). `swift test` green. Home for Phase 6.
- [x] T005 [inline] Add the **tvOS app target** `OwnFrameTV` to the xcodeproj via the
      `xcodeproj` gem: shared bundle-id family (`ing.kipp.Immich-Slideshow`), `TVOS_DEPLOYMENT_TARGET
      = 17.0`, `SUPPORTED_PLATFORMS = appletvos appletvsimulator`, `TARGETED_DEVICE_FAMILY = 3`; link
      the tvOS package set (ImmichClient, OnboardingKit, SlideshowKit, PowerKit, HAControlKit,
      HAControlMQTT, BrokerSetupKit, ThemeKit, PhotoSourceKit, ConfigSyncKit — **not** PhotoLibraryKit
      /AppIntentsKit); new synchronized group `OwnFrameTV/`; share `OwnFrame/` with a
      build-file **exception set** excluding `Onboarding/QRScannerView.swift`, `Onboarding/
      PhotoAlbumPickerView.swift`, `Slideshow/UIScreenController.swift`; **no** Share-Extension embed/
      dependency (FR-1000-09); entitlements (iCloud KVS + CloudKit private DB); shared scheme.
      Minimal `ImmichSlideshowTVApp` stub. **Verify: `build_sim` for the tvOS scheme succeeds**
      (resolve `swift-nio-ssl`/`mqtt-nio` tvOS compile here — the T004 spike-verify risk).

**Checkpoint**: tvOS target builds an empty app on the sim; packages tvOS-ready.

## Phase 3: US1 — the frame plays on the TV (P1) 🎯 MVP

- [x] T006 [delegate] Red+green `SoftwareDimModel` (pure) in `OwnFrameTV/` (host-testable via
      a tiny test target or ConfigSyncKit-adjacent): `brightness→overlayOpacity = 1−clamp(b)`;
      monotonic; clamps. Tests first.
- [x] T007 [inline] `SoftwareDimScreenController: ScreenControlling` (tvOS): `brightness` drives an
      `@Observable` dim value (uses T006); `isIdleTimerDisabled → UIApplication.isIdleTimerDisabled`.
      Injected into `PowerManager` at the tvOS app entry.
- [x] T008 [inline] Conditionalize shared slideshow UI for tvOS: guard `.statusBarHidden`/
      `.persistentSystemOverlays`; composite the black software-dim overlay (opacity from T007) above
      the photo, below chrome; `ClockIdiom`/sizing gets a `.tv` case; guard `UIImage` scaling +
      `openSettingsURLString` with `#if os(iOS)` (tvOS variant/no-op).
- [x] T009 [delegate] Red+green `TVChromeModel` (pure state machine per data-model.md): activity→
      visible+auto-hide(4.5s); auto-hide→hidden; menu consumed only when visible; play/pause toggles
      independent; directional→next/prev without reveal. Host tests for every transition.
- [x] T010 [inline] Wire tvOS remote input in the shared `SlideshowView` behind `#if os(tvOS)`:
      `.focusable`/`onMoveCommand`/`onExitCommand`/`onPlayPauseCommand` → `TVChromeModel` +
      `viewModel.showNext/Previous/togglePause`; Menu at naked slideshow falls through to Home.
- [x] T011 [inline] tvOS `@main ImmichSlideshowTVApp` composition root: build the engine (stub API
      seam for sim + real ImmichClient), `SoftwareDimScreenController`, `PowerManager`, distinct HA
      identity (T017), StartupGate routing (onboarding vs slideshow). **Verify on sim: cold-launch →
      slideshow plays, transitions/Ken Burns render, idle timer disabled (screenshot + short video).**
- [x] T012 [inline] Eliminate FR-1000-07 bypass: `SlideshowSettingsView.currentScreenBrightness()`
      removed; initial brightness read through `ScreenControlling`/PowerManager on both platforms; iOS
      suite stays green.

**Checkpoint**: US1 met on the sim — living-room slideshow, remote-operable, software dim.

## Phase 4: US3 — survives tvOS storage reality (P2)

- [x] T013 [delegate] Red+green: purge-tolerance as the normal case — with the disk-cache root at a
      temp dir, delete it, relaunch engine deps, assert playback reaches the first photo with no user
      input and the cache refills (exercise existing 320 paths from a tvOS-context test); assert no
      persistent state assumes a Documents dir (SC-1000-03/FR-1000-04).

## Phase 5: US4 — Home Assistant parity in the living room (P2)

- [x] T014 [delegate] Red+green `FrameIdentity` provider: distinct tvOS `deviceID`+`deviceName`
      ("OwnFrame (Apple TV)") vs iOS; assert distinct MQTT base topic / discovery identifiers /
      unique_id via `HATopics`/`HADiscovery` (host tests, no kit change).
- [x] T015 [inline] Wire HA on the tvOS app entry: BrokerSetup + `HAControlCoordinator` with the tvOS
      `FrameIdentity`; brightness command → `SoftwareDimScreenController` dim; confirm HAControlKit
      fake-transport round-trip suite builds/passes for tvOS.

## Phase 6: US2 — setup without typing a novel (P1, largest)

- [x] T016 [delegate] Red+green `SyncedConfig` (data-model.md) in ConfigSyncKit: Codable/Sendable,
      versioned, maps the six non-secret stores; round-trips; **contains no secret** (assert).
- [x] T017 [delegate] Red+green `ConfigSyncStore` + `InMemoryConfigSyncStore` +
      `UbiquitousKVSConfigSyncStore` (thin, compiles): fake round-trip; `externalChanges` emits;
      SC-1000-08 no-secret-in-KVS invariant asserted (contracts/config-sync.md).
- [x] T018 [delegate] Red+green `SyncedSecret` + `SecretSyncStore` + `InMemorySecretSyncStore` +
      `CloudKitSecretSyncStore` (thin `encryptedValues`, compiles, no custom crypto): fake publish/
      fetch; `iCloudUnavailable` → nil; no-secret-in-plaintext assert.
- [x] T019 [delegate] Red+green `ConfigPublisher` (iPad): gather stores → `SyncedConfig`/`SyncedSecret`
      → save/publish; idempotent; secrets only via `SecretSyncStore`. Host tests with fakes.
- [x] T020 [delegate] Red+green `ConfigConsumer` (tvOS): `prefill()` from KVS; `hydrateSecrets` writes
      fetched secrets into the (fake) keychain then reads local; returns `.hydrated`/`.manualRequired`;
      never throws to UI. All four US2 acceptance scenarios (contracts/config-sync.md) green.
- [x] T021 [inline] Wire the iPad companion publisher into the iOS app (write-through on config
      change: onboarding save, source-library edits, theme/broker/cache changes). iOS suite green.
- [x] T022 [inline] tvOS onboarding: consume `prefill` (prefilled choices) + `hydrateSecrets` (zero-typing
      when synced) + manual fallback (system keyboard / "Type with iPhone"; shared-link one-URL fast
      path — topic 210 semantics). Reuse shared onboarding views (excl. QR/Photos). **Verify on sim:
      prefilled path and manual path both complete → slideshow.**

**Checkpoint**: US2 met against fakes + on the sim; real-container proof = device gate.

## Phase 7: Polish & verification

- [ ] T023 [inline] Footprint + purge audit: image data/snapshots in Caches only; measure
      UserDefaults < 100 KB with a realistic library (SC-1000-07); no Documents assumption.
- [ ] T024 [inline] **Full verification gate** (owned by Claude): (a) iOS app build + full suite green
      on iOS sim (no regression); (b) tvOS app `build_run_sim` — US1 slideshow, remote walkthrough,
      onboarding both paths, HA dim — screenshots + video; (c) `swift test` all packages host-green;
      (d) build all linked packages for the tvOS destination (SC-1000-04).
- [ ] T025 [inline] Docs + traceability: update `docs/spec-overview.md` (1000 status), `CLAUDE.md`
      active-feature note, and register the device gates (SC-1000-02/05/06/08 + CloudKit-on-hardware)
      in quickstart.md. Requirement→task traceability table.

## Dependencies

- T001 → T002 → {T003, T004} → T005 (target needs packages tvOS-ready).
- US1 (T006–T012) after T005. T006→T007→T008; T009→T010; T011 needs T007+T010+T017.
- US3 (T013), US4 (T014→T015) after T005 (independent of US1 detail).
- US2 (T016→…→T020 in ConfigSyncKit) after T004; T021 (iPad) + T022 (tvOS) after T019/T020 + T011.
- Polish (T023–T025) last.

## Delegation batches (coding subagent, parallel-safe = different files)

- Batch A (after T005): T006, T009 (pure models), T016 (SyncedConfig).
- Batch B: T017, T018 (sync stores) ∥ T003 (PhotoLibraryKit guard) ∥ T014 (identity).
- Batch C: T019, T020 (publisher/consumer) after T016–T018; T013 (purge) independent.
