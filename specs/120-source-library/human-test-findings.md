# Human-test findings — Source Library (120)

Bugs/observations from the real-iPad test pass (iPad jk, iPad16,3). To be batch-fixed after testing.

## Bug 1 — Onboarding: first "Continue" shows "server not available", unchanged retry works
- **Status: FIXED (2026-06-25).** Declared `INFOPLIST_KEY_NSLocalNetworkUsageDescription`
  (build setting; verified present in the built `Info.plist`) and added a bounded auto-retry on
  `ImmichError.unreachable` in `OnboardingViewModel.submitConnection` (default 4 retries ~1.2 s
  apart, injected sleep; deterministic errors — auth/invalid — are not retried). Host tests cover
  retry-then-succeed, exhaust-then-error, and no-retry-on-auth. On-device re-test of the
  fresh-install prompt path still pending.
- **Repro:** Fresh install → Connection step → enter real server URL + API key → Continue → red
  "server not available" (`ImmichError.unreachable`). Tap Continue again, no field change → green, proceeds.
- **Root cause (confirmed):** iOS **Local Network privacy** prompt. The self-hosted Immich hostname
  resolves to a LAN IP, so the first connection triggers the system "allow local network" alert and the
  in-flight request fails; after granting, the retry succeeds. Confirmed on device: Settings → Immich
  Slideshow shows a **Local Network** toggle, **ON**.
- **Scope:** Pre-existing (network layer, not the US2 onboarding redesign — `submitConnection`'s
  `albums()` call is unchanged). First-run only (once per install). Invisible in the simulator → not
  caught by XCUITest.
- **Planned fix (approved approach: declare + retry):**
  1. Add `NSLocalNetworkUsageDescription` (via `INFOPLIST_KEY_NSLocalNetworkUsageDescription` build
     setting — `GENERATE_INFOPLIST_FILE = YES`, no standalone Info.plist) for a clear prompt + iOS 18
     compliance. *(pbxproj build-setting edit.)*
  2. Bounded auto-retry of the connection validation on `.unreachable` (e.g. a few attempts with a
     short delay) so it completes once the user allows access, instead of surfacing a hard error.
     Consider the same gentle retry for the slideshow's first asset load on first run.
  - Files: `Packages/OnboardingKit/Sources/OnboardingKit/OnboardingViewModel.swift` (`submitConnection`),
    project build settings; optionally `Packages/ImmichClient` if a transport-level retry is preferred.
  - Tests: host test for the retry-then-succeed path (stub transport fails once then returns albums).

## Bug 2 — Slideshow chrome shifts position when Ken Burns is on
- **Status: FIXED (2026-06-25).** The chrome now lays out against a stable full-screen,
  safe-area-respecting frame with the image rendered as its `.background` (a background is sized
  to the host and never feeds size back up), so switching the image between fit and fill framing
  no longer drags the chrome's inset. Verified: chrome insets pixel-stable KB on vs off (sim
  screenshots), `SlideshowChromeUITests` + full UI suite green. `--uitest-kenburns` retained as
  the regression seam.
- **Repro:** Running slideshow, reveal chrome. Toggle Ken Burns ON → the chrome buttons (top X,
  top-right info/albums/settings cluster) slide outward toward the screen edges (~10pt/side in
  portrait sim; more pronounced on the device/landscape). Toggle OFF → back to the correct inset.
- **Root cause (confirmed in sim):** Ken Burns forces **fill** framing (`fillsScreen = fit==.fill ||
  kenBurns`). The image layer `phaseContent.ignoresSafeArea()` is a **ZStack sibling** of the chrome;
  switching the image between `scaledToFit` and `scaledToFill` changes the ZStack's proposed size, so
  the chrome's safe-area inset rides along. The Ken Burns scale/offset transform itself is correctly
  scoped to the image and is **not** the cause. Reproduced via a temporary `--uitest-kenburns` seam
  (`makeThemeStore`, currently uncommitted in the working tree) + `--uitest-slideshow --uitest-chrome`.
- **Scope:** Pre-existing layout coupling (not US2). Repros in the simulator → can be fixed +
  regression-tested off-device.
- **Planned fix:** lay out the chrome against a **stable** full-screen/safe-area frame independent of
  the image — e.g. move `.ignoresSafeArea()` to the whole ZStack and inset the chrome with
  `.safeAreaPadding()`, or render the image as a `.background` of the chrome container. Verify by
  re-screenshotting KB on/off (chrome inset identical) and re-running `SlideshowChromeUITests`
  (tap-toggle + swipe must still work). Consider keeping `--uitest-kenburns` to back a regression
  screenshot check.
  - Files: `OwnFrame/Slideshow/SlideshowView.swift` (body ZStack / `chromeOverlay`).

## Finding 3 (feature gap) — MQTT broker setup gives zero connection feedback
- **Observed:** After entering broker host/user/password and saving, nothing tells the user whether
  the connection actually works. A misconfig (wrong user/host/password) or unreachable/timeout is
  silent.
- **Current behaviour:** `BrokerSettingsSection` only does **local field validation** (empty host,
  port range, empty username/password). `Speichern` saves to the Keychain — it does **not** attempt a
  connection. The real MQTT connect happens later in the running slideshow via
  `HAControlCoordinator.start()`; on failure `SlideshowView.startCoordinator` silently releases the
  coordinator, and its `connection` state is never surfaced to any UI.
- **Feasibility:** `HAControlCoordinator` already exposes `ConnectionState` (`.connecting/.connected/
  .disconnected`) and `MQTTTransport.connect(will:)` **throws** on failure (currently only logged). So
  we can surface connection **state** + a basic error reason now; rich classification (auth vs.
  unreachable vs. timeout) needs mapping the NIO MQTT library's error types.
- **Proposed (feature — needs a 600/700 spec+plan+tasks per SDD before coding):**
  1. A **"Test connection"** action in the MQTT section: attempt an MQTT connect with the entered
     settings and report **Connected ✓** / **Failed: <reason>** inline (mirrors the onboarding
     connection-validation UX).
  2. Optionally a live **status row** reflecting the running coordinator (connected/connecting/last
     error) so HA control state is visible while the show runs.
  - Files (when specced): `Packages/HAControlKit` (classify/expose connect errors), `BrokerSetupKit`/
    `BrokerSetupViewModel` (test action), `OwnFrame/Slideshow/BrokerSetupView.swift` (UI).
  - Belongs to specs `600-broker-setup` / `700-ha-control`, not 120.

## Finding 4 (perf/power investigation) — slideshow feels power-hungry
- **Observed:** Power draw "feels like a lot" on the iPad. Question raised: is Ken Burns using Metal?
- **Analysis (grounded in code):**
  - Ken Burns + transitions are **already GPU/Metal-composited** — `.scaleEffect`/`.offset`/`.opacity`
    are Core Animation layer properties animated by the render server on the GPU. No CPU pixel work to
    move to Metal; an explicit Metal rewrite would **not** reduce power.
  - Dominant cost is the **always-on display at brightness** (inherent to a photo frame). Biggest lever
    is brightness (`PowerManager`/`UIScreen.brightness`).
  - **Ken Burns is higher-power because it's continuous** — keeps the GPU compositor busy and holds the
    display refresh up for the whole photo duration (likely pins ProMotion ~120 Hz vs idling a static
    photo to ~10–24 Hz). Off by default (calm default) = the low-power mode.
  - **Per-swap decode:** `ImageCache` stores raw bytes; the view does `UIImage(data:)` →
    `Image(uiImage:)`, decoding on the **main thread at display time, no downsampling** to screen size.
    CPU/thermal spike per photo + main-thread hitches.
- **Levers (measure first — needs Instruments Energy/Core-Animation FPS on the device; not profilable
  via the MCP):**
  1. Brightness/display tuning (dominant).
  2. Image **downsample to display size + async pre-decode** (`byPreparingForDisplay()` / `CGImageSource`
     thumbnail), optionally cache decoded bitmaps — also fixes per-swap hitches. (`SlideshowKit`/`SlideshowView`.)
     *(Pre-decode half DONE 2026-07-18: `DecodedImageStore` + `DisplayImagePreparing` seam, measured
     swap-hitch elimination. Downsampling deliberately skipped — preview tier ≈ panel resolution;
     re-open only if device profiling shows GPU-bound hitches.)*
  3. If Ken Burns must be cheaper on ProMotion: redo it via `TimelineView`/`CADisplayLink` with a
     capped `preferredFramesPerSecond` (~30) instead of implicit `withAnimation` — a rewrite, modest win.
     *(Superseded 2026-07-18: Ken Burns is now ONE scoped linear animation per photo
     (`KenBurnsMotionModifier`) — near-zero per-frame cost, cheaper than any capped-tick sampler.)*
- **Scope:** perf area (300-slideshow / 400-power-manager). Not a discrete bug; gate any work on a
  measurement.
