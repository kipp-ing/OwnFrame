# 1000-apple-tv — Testing Review (2026-07-18)

> **Fix status (same day, follow-up commits on this branch):** B1–B11 plus the
> tvOS active-source persistence bug (B12, found while fixing) are **fixed**;
> re-verified via host suites (685 green), the full iOS simulator suite, a fresh
> luminance run (no black frames at swaps), and sim screenshots (portrait photos
> now letterbox per `fit = .fit`). Also fixed from the cleanup tail: shared
> entitlement-gated `SecretSyncStoreFactory` (dedup + crash gate), KVS-observer
> leak, `FrameIdentity` wired (double-suffix fallback id gone), dead
> `TVStubPhotoSource` deleted. Still open: the tvOS test-target/XCUIRemote
> harness (gap #1–3), the remaining duplication tail (adapter/KenBurns/coordinator
> lifecycle/error mapper/credentials codec), and the device-gated verifications
> (B8/B9 orderings on a real broker; B2's flag flip when entitlements land).

Second verification pass over the branch (8 commits, `c82f2ed..d1a163d`, vs `main`).
Method: full host-test sweep, full iOS simulator suite, tvOS simulator exploration
(demo shared link, persistence, fresh install, purge smoke), frame-by-frame video
luminance analysis of the tvOS transition, plus a high-effort multi-agent code review
of the branch diff (4 finder angles, 26 independent verifiers; 27 candidates verified,
0 refuted).

## Gate results

| Gate | Result |
|------|--------|
| Host unit tests, all 11 packages | ✅ 678/678 (ConfigSyncKit 21, HAControlKit 92, SlideshowKit 161, OnboardingKit 154, …) |
| Full iOS simulator suite (`Immich Slideshow` scheme, iPad Pro 13" M5) | ✅ 120 passed / 0 failed / 2 skipped (matches pre-branch baseline; ~35 min) |
| tvOS build (`Immich SlideshowTV`, Apple TV 4K 3rd gen sim) | ✅ builds + launches |
| US1 e2e (demo shared link → real photos render + auto-advance) | ✅ verified |
| US2 fresh install → Welcome choice screen | ✅ verified |
| US3 purge smoke (wipe data container, relaunch) | ✅ clean return to onboarding, no crash |
| Relaunch persistence (no seam → straight to slideshow) | ✅ verified |
| Runtime + os_log during tvOS runs | ✅ zero app-level errors/faults |
| tvOS transition quality (video luminance) | ❌ **B1 — hard cut to black every swap** |

## Findings (ranked)

### B1 — tvOS photo swap is a hard cut to black + fade-in (CONFIRMED, empirical)
`Immich SlideshowTV/TVSlideshowView.swift:58`

The pre-release iOS transition bug (fixed in `05afa82`) is re-introduced on tvOS.
The photo uses plain symmetric `.transition(.opacity)` with **no `.zIndex(1)`**, so
during the `.id` swap SwiftUI drops the outgoing photo behind the opaque
`Color.black` backdrop: a one-frame cut to black, then a 0.7 s fade-in from black —
every 15 s with default settings.

Evidence (simctl recording + `ffprobe signalstats`, YAVG per frame): static photo
plateau, then first changed frame already at YAVG **16.0** (pure black) at t=7.1 s,
22.3 s, 37.5 s — 15 s cadence — each followed by a monotonic ramp 16 → photo level
over ~0.7 s. Zero fade-down frames captured before the black frame (variable-rate
recording ⇒ the cut happened in ≤1 frame). Recording:
`tv-demo-run.mp4` (session scratchpad), stats reproducible via
`docs/automation-recipes.md` luminance recipe.

Fix shape (port of `05afa82`): `.zIndex(1)` on the photo + sequenced asymmetric
insertion/removal fades.

### B2 — `CKContainer.default()` will crash real devices signed into iCloud (entitlements verified absent)
`Immich Slideshow/CompanionSync.swift:55` and `Immich SlideshowTV/TVRootView.swift:143`

`makeSecretStore()` gates only on `FileManager.default.ubiquityIdentityToken != nil`
— an **account** signal, not an entitlement check. Verified this session:
`Immich Slideshow.entitlements` contains only the app group (no iCloud container,
no CloudKit, no KVS identifier) and the TV target has no entitlements file.
`CKContainer.default()` without a container entitlement raises
`NSInternalInconsistencyException` ("containerIdentifier can not be nil"), so on any
physical device with an iCloud account the iPad app crashes on launch/foreground and
the TV app on launch. Sim-safe today only because the simulator has no account.
Also: without the KVS entitlement, `NSUbiquitousKeyValueStore` silently no-ops even
on hardware — FR-1000-06 cannot work until the entitlements land.

Merge-blocker for any device build; must be resolved before the device-gate day.

### B3 — Post-onboarding resolve failure = permanent black screen (CONFIRMED)
`Immich SlideshowTV/TVRootView.swift:171-180,190`

`buildSlideshow()` swallows resolve errors (`try?`); on failure `route = .onboarding`
with `onboarding.step == .done`, and `TVOnboardingView` renders `EmptyView` for
`.done` — a dead-end black screen, no error, no retry. Hits when the network blips at
"Start slideshow", and on every cold boot of a configured shared-link TV before Wi-Fi
is up (bypassing the engine's own retry/offline tolerance, which only engages once a
`SlideshowViewModel` exists).

### B4 — Secret hydration clobbers TV-local keychain on every launch; `start()` blocks on CloudKit (CONFIRMED)
`Immich SlideshowTV/TVRootView.swift:152-155`

`restoreSyncedConfigIfFresh()` is guarded (fresh installs only), but
`hydrateSecrets` runs **unconditionally** every launch and `TVSecretWriter`
overwrites the TV keychain with whatever the iPad last synced — a key rotated and
re-entered on the TV is silently reverted to the stale synced one on next launch.
`start()` also `await`s the CloudKit fetch before routing, so a flaky-connection
device sits on the loading spinner until CloudKit times out, every boot.

### B5 — Opening/closing broker settings resets playback (CONFIRMED)
`Immich SlideshowTV/TVRootView.swift:57-59` + `TVSlideshowView.swift:115-125`

The settings `fullScreenCover` removes `TVSlideshowView` from the hierarchy:
`onDisappear` fires on present (keep-awake released, HA coordinator stopped), and
`.task` re-fires on dismiss, re-running `viewModel.start()` — un-pausing, reshuffling
the order, and jumping to a different photo. A paused favorite photo is lost every
time settings is opened.

### B6 — tvOS renderer ignores `fit` and `transition` settings (CONFIRMED)
`Immich SlideshowTV/TVSlideshowView.swift:53,58`

Hardcoded `.scaledToFill()` + fixed opacity fade. The default `fit = .fit` (and the
value synced from the iPad or set via HA) is discarded — portrait photos are always
hard-cropped to fill the 16:9 TV; HA `transition` select (slide/dissolve/none) does
nothing on tvOS while the adapter dutifully mirrors it. US4 "parity" accepts these
settings but the renderer discards them.

### B7 — HA album select can tear a playing frame down into onboarding (CONFIRMED)
`Immich SlideshowTV/TVRootView.swift:253-256` + `TVRemoteControlAdapter.swift:45`

`albumOptions` exposes every synced source, including `.album` sources restored from
the iPad. If secret hydration degraded to manual (no API key on the TV), selecting
such an album from HA runs `evaluateGate` → `StartupGate` → `.connection`, dropping
the frame out of the slideshow onto a setup form until someone picks up the remote.
A remote-triggered action should never route an unattended frame into onboarding.

### B8 — Shared `PowerManager` across `.id`-swapped views: activate/deactivate race + dim snap-back (PLAUSIBLE)
`Immich SlideshowTV/TVSlideshowView.swift:116-125` + `TVRootView.swift:51,56`

On an HA source switch the new view's `.task` (`activate`) and old view's
`onDisappear` (`deactivate`) run in SwiftUI-defined order against the **same**
`PowerManager` (iOS builds a fresh one per generation). If deactivate lands last:
keep-awake off mid-slideshow and subsequent HA `setBrightness` silently no-ops;
additionally any HA-set software dim snaps back to full brightness on every switch.

### B9 — HA availability can end "offline" after a source switch (PLAUSIBLE)
`Immich SlideshowTV/TVSlideshowView.swift:124,148-165`

Old-coordinator `stop()` (retained "offline") and new-coordinator `start()`
(retained "online") run as unordered concurrent tasks against the same topics, and
both transports share one MQTT client id — broker client-takeover can fire the old
connection's LWT after the new connect. HA then greys the frame out although it is
connected and playing. Needs the real-broker session to confirm (device gate).

### B10 — iOS regression risk: brightness slider can seed at 0 (PLAUSIBLE)
`Immich Slideshow/Slideshow/SlideshowSettingsView.swift:96`

This branch replaces the old `?? 1.0` bright fallback with
`powerManager.currentBrightness`, whose `UIScreenController` getter falls back to
**0** when no window scene resolves — inverting the no-screen default from
full-bright to black. Timing-dependent (sheet built during scene activation / Stage
Manager transitions).

### B11 — Duplicate album label: silent failure + dead-end confirm loop (CONFIRMED)
`Immich SlideshowTV/TVRootView.swift:218-224`

`selectAlbum` ignores `addAlbumSource`'s duplicate-label rejection; the
`last(where:)` lookup then activates an unrelated same-album source — or nothing —
while the onboarding UI advances to "Ready to play". Start bounces back to
onboarding with no message.

## Testability gaps (this session's focus)

1. **The tvOS target has zero automated tests.** The shared `Immich SlideshowTV`
   scheme's `<Testables>` block is empty — no app-hosted tests, no XCUITests. ~1,600
   lines of tvOS app-layer Swift (`TVRootView` 290, `TVOnboardingView` 380,
   `TVRemoteControlAdapter` 267, `TVSlideshowView` 219, …) are covered only by
   host-package tests of the pieces behind them. Findings B3/B5/B7/B11 live exactly
   in that untested layer.
2. **One seam vs. the iOS family.** tvOS recognizes only `--tv-demo-sharedlink`;
   there is no `--uitest` stub-API/in-memory-store seam, so nothing hermetic can be
   driven on tvOS. Every tvOS check in this session ran against the live demo server.
3. **No headless remote-input path.** XcodeBuildMCP is observe-only here (no
   axe/idb), and simctl cannot send Siri-Remote events — chrome reveal, Menu
   behavior (FR-1000-03), transport controls, onboarding forms, and broker setup are
   unreachable by automation. The first-party answer is a tvOS XCUITest target using
   `XCUIRemote` (the tvOS equivalent of the committed iOS XCUITest harness); that
   plus a `--uitest` seam would convert B3/B5/B11 into red tests.
4. **Contract drift.** `contracts/config-sync.md` says publish is "called on config
   change"; the implementation publishes on launch + foreground only
   (`Immich_SlideshowApp.swift:541`), so mid-session changes don't sync until the
   next foreground. Either the contract or the wiring should change (and today it
   double-publishes on cold launch: `.task` + the initial scenePhase `.active`).

## Cleanup tail (verified, below severity cap)

- `TVRemoteControlAdapter` duplicates ~200 lines of the iOS
  `SlideshowRemoteControlAdapter` verbatim (observation re-arm blocks, mapPhase, the
  full 11-field snapshot mapping) — belongs in a shared package.
- `TVKenBurns` is a byte-for-byte copy of the iOS `KenBurnsModifier` (pan 24 vs 16) —
  parameterize one shared modifier.
- `startCoordinator`/`stopCoordinator` lifecycle duplicated verbatim from iOS
  `SlideshowView` — extract a shared helper.
- `makeSecretStore()` duplicated verbatim (CompanionSync + TVRootView) — belongs in
  ConfigSyncKit next to the stores.
- `TVBrokerSetupView.message(for:)` duplicates the iOS `BrokerSetupView` error
  mapper — belongs in BrokerSetupKit.
- `MQTTCredentialsPayload` re-declares `KeychainBrokerSettingsStore`'s private wire
  shape, kept compatible only by a comment — expose the codec once from
  BrokerSetupKit.
- `CompanionSync.publish()` builds a fresh `UbiquitousKVSConfigSyncStore` per call —
  each registers a NotificationCenter observer + AsyncStream nobody consumes (leak
  per foreground).
- `FrameIdentity` (new public type + tests) has **zero production callers** —
  TVAppModel concatenates the device id inline instead; wire it or drop it.
- Inline deviceID fallback double-appends the suffix:
  `"immich-slideshow-appletv" + "-appletv"`.
- `TVStubPhotoSource` is dead code (its T011 replacement landed).
- `durationSeconds` re-implements the Duration→seconds conversion (and diverges from
  iOS which drops attoseconds).
- `submitSharedLink`/`confirmSharedLinkPassword` duplicate the resolved-state block —
  one `activateIfResolved()` helper.

## Suggested fix order

1. **B2** (entitlement-guard or entitlements) — crash class, blocks all device work.
2. **B1** (port `05afa82`: zIndex + sequenced fades) — most visible defect, every 15 s.
3. **B3 + B6** (error/route surface + honor fit/transition) — frame-worthiness.
4. **B4, B5, B7** (hydration guard, cover lifecycle, HA select gating).
5. Testability: tvOS XCUITest target with `XCUIRemote` + `--uitest` seam; then B8/B9
   verification rides the real-broker device day.
6. Cleanup tail as a follow-up dedup commit series.

## Session evidence

- Host sweep: `for pkg in Packages/*: swift test` — 678 pass, 0 fail.
- tvOS run: `build_run_sim` scheme `Immich SlideshowTV`, sim `Apple TV 4K (3rd
  generation)` (C3A8C51D), launch arg `--tv-demo-sharedlink`; real photos from
  `https://bilder.kippings.de/s/Iceland2021` rendered and auto-advanced.
- Luminance: 40 s simctl recording, 129 variable-rate frames, black frames (YAVG
  16.0) at 7.1/22.3/37.5 s each followed by a 0.7 s monotonic ramp up; no fade-down
  frames precede them.
- Purge smoke: terminate → `rm -rf` data-container Preferences/Caches/Documents/App
  Support → relaunch → Welcome screen, no crash.
- Persisted source library after the seam run: exactly one `sharedLink` source
  (`bilder.kippings.de` / `Iceland2021`), correct `activeID`, no duplicates.
- Multi-agent review: 32 agents, 27/27 candidates verified (0 refuted), findings
  journaled under the session workflow dir (`wf_91de2d14-ae2`).
