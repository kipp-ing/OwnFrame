# Testing Guide

How this project is tested, and how to run each layer. All commands go through
**XcodeBuildMCP** (or `swift` on the host) — see [CLAUDE.md](../CLAUDE.md) for the
constitution-level rules (TDD first; see also [tdd-workflow.md](../tdd-workflow.md)).

## The test pyramid

| Layer | Where | Runs on | Speed | What it covers |
|-------|-------|---------|-------|----------------|
| **Unit (host)** | `Packages/*/Tests` | macOS host (`swift test`) | sub-second | Pure module logic behind protocols (API decode, view-model state, config/keychain stores) |
| **App-hosted** | `OwnFrameTests` | iOS Simulator | seconds | Things that need the real device runtime: real Keychain round-trip, reset, integration decode |
| **UI (XCUITest)** | `OwnFrameUITests` | iOS Simulator | ~10–20 s/test | The user-facing flow, driven end to end and hermetically |

The host layer is the fast inner loop. The simulator layers are the gate.

## Layer 1 — Host unit tests

Each Swift package is independently testable on the host:

```bash
cd Packages/ImmichClient  && swift build && swift test
cd Packages/OnboardingKit && swift build && swift test
```

Network, Keychain, and time are behind protocols (`ImmichAPI`, `ConfigStore`,
`KeychainStore`), so these tests use in-memory fakes and never touch a real
server or the Keychain.

> **Why a separate app-hosted layer exists:** SwiftPM *test* targets cannot run on
> the simulator through the app `.xcodeproj` (only library products surface as
> schemes). So package logic is tested on the host; anything that needs the real
> simulator runtime lives in the app-hosted bundle. See
> [engineering-notes.md](engineering-notes.md#spm-test-targets-vs-the-simulator).

## Layer 2 — App-hosted tests (`OwnFrameTests`)

These link the packages into the app and run on the simulator — used where the
host can't help: the **real `KeychainAPIKeyStore`** round-trip, the reset flow
(real key removal), and `ImmichClient` integration decode against a stub transport.

Run the whole simulator suite:

```text
XcodeBuildMCP → test_sim   (scheme "OwnFrame", iPad Pro 11" on iOS 18.6, preferXcodebuild: true)
```

**Pick the runtime deliberately — not every ≥17 destination works.** The iOS **26.4**
simulator serves **0 StoreKit products**, which fails all 7 `StoreKitClientTests` (see
"`SKTestSession` serves 0 products" below). Run on iOS **18.6** or **26.5** (or a device);
avoid 26.4 — which is what an unpinned "iPad Pro 11" M5" currently boots to.

## Layer 3 — UI tests (hermetic XCUITest)

This is the first-party "Xcode way" to test the SwiftUI flow. It is **hermetic**:
no live server, no real Keychain, fully deterministic and CI-safe.

**How it works:**

1. The test launches with a flag:
   ```swift
   app.launchArguments = ["--uitest"]
   ```
2. That trips a **DEBUG-only** seam, `UITestSupport`, in
   `OwnFrame/OwnFrameApp.swift`. It injects a **stub `ImmichAPI`**
   (canned albums) plus **in-memory** `ConfigStore`/`KeychainStore`. The production
   launch path is untouched and the seam is never compiled into Release.
3. Views carry **accessibility identifiers** as stable anchors:

   | Identifier | Element |
   |------------|---------|
   | `onboarding.serverURL` | server URL text field |
   | `onboarding.apiKey` | API-key secure field |
   | `onboarding.connection.continue` | Continue — validates URL + key in one action |
   | `onboarding.album.<id>` | each album row |
   | `onboarding.source.continue` | Continue, once a source has been added |
   | `onboarding.confirm.start` | Start, on the confirmation step |
   | `slideshow.image` | the running slideshow's current image |

   Server URL and API key share **one** combined connection step — there is no separate
   per-field step or per-step button.

**The suite** — 25 files under `OwnFrameUITests/`, one per flow (album browser, clock overlay,
purchase gate, settings, shared links, slideshow chrome, …). The core onboarding pair lives in
`OwnFrameUITests/OwnFrameUITests.swift`:

- `testOnboardingHappyPathReachesSlideshow` — connection (URL + key on one screen) → source
  (album) → confirm → the running slideshow.
- `testFreshLaunchShowsConnectionStep` — a fresh launch starts at the combined connection step.

**Run just the flow** (skips the slow launch-perf suite):

```text
test_sim  extraArgs:
  -only-testing:OwnFrameUITests/OwnFrameUITests/testOnboardingHappyPathReachesSlideshow
```

**Extending it to a new flow** (e.g. SlideshowView): add accessibility identifiers
to the new views, extend `UITestSupport` with whatever stub data the flow needs,
and add an XCUITest that launches with `--uitest`. Do **not** reach for `axe` /
MCP write-side UI automation — XCUITest is the repeatable, committed path. (That
backend isn't installed here anyway; see the engineering notes.)

## Release gate — run before EVERY release

Every App Store submission (and every merge to `main` that will ship) runs this
sequence, in order. Nothing here is optional.

1. **Host suites** — every package green:

   ```bash
   for p in Packages/*/; do (cd "$p" && swift test) || break; done
   ```

   `SlideshowKit` carries the resilience engine suites (310): `RetryPolicyTests`,
   `RotationReconcilerTests`, `SlideshowResilienceTests` (TestClock-driven — real
   timers in tests are a spec violation, FR-310-12).

2. **Full simulator suite** — `test_sim` on the whole scheme (app-hosted +
   *all* XCUITests). This includes the 310 release tests in
   `SlideshowResilienceUITests`, which drive the failure seams
   (`--uitest-assets-fail=unreachable|unauthorized`,
   `--uitest-assets-recover-after=N`):
   - calm error state + **unattended auto-recovery with zero taps** (US1-2/SC-310-01),
   - the actionable auth variant + Edit connection opening the editor (FR-310-05),
   - manual retry against a dead server staying calm (FR-310-04).
   Never `-only-testing` a single Swift Testing `@Test` (false green — runs 0
   tests and reports SUCCEEDED); whole classes only.

3. **Error-state screenshots** — launch the app with each failure seam and
   screenshot both `SlideshowErrorView` variants (XCUITest can't judge layout;
   overlays are verified visually — see engineering notes).

4. **Manual resilience smoke on the real frame** (per
   `specs/310-slideshow-resilience/quickstart.md`, and once 320 ships also its
   quickstart): kill Wi-Fi ~2 min mid-show → playback self-recovers; add a photo
   server-side → appears within one refresh interval. With 320: Airplane Mode →
   full rotation continues; force-quit + relaunch offline → show returns.

5. **Full XCUITest suite green before the merge** — house rule; screenshots miss
   UI-test regressions.

## Layer 4 — real hardware

Some contracts cannot be proved in a simulator at all (real MQTT/TLS, real CloudKit,
panel smoothness, soak). Those run on the physical frame — see
[device-testing.md](device-testing.md) for the device rig, the CLI recipes, and an
honest list of what genuinely needs hardware versus what is merely missing a test
target.

## Requirement traceability — `.claude/scripts/coverage.py`

Prose status rots. `CLAUDE.md` recorded "153/0/9 green" and on 2026-07-21 that was simply
false; a skip-guard had also been hiding a real bug for a day. Anything asserting what is
proven must therefore be **derived from the tree on every run**, never written down by hand.

```bash
.claude/scripts/coverage.py              # report
.claude/scripts/coverage.py --uncovered  # ids only
.claude/scripts/coverage.py --json       # for CI
.claude/scripts/coverage.py --check      # exit 1 if any requirement is untraceable
```

It maps the requirement ids defined in `specs/*/spec.md` (the authoritative site — a bullet
`- **FR-1100-12**: …`; plan/tasks merely cite them) to the tests that claim them, bucketed by
layer: `host` → `app` → `ui` → `manual`.

**Read the output correctly.** It measures whether a requirement can be *traced* to a test,
not whether it is *tested*. At the time of writing 71% is untraceable, which is emphatically
not 71% untested: `ImmichClient` has 73 tests and cites no ids at all. The number says how
much of the suite is auditable, not how much risk we carry.

Two grades, because the tree is mid-migration:

- **`@covers FR-1100-12`** — an explicit annotation in a comment above the test. Machine-checkable.
- **mention** — today's informal `// … (FR-1100-12)` style. Counted so the baseline is honest
  on day one, but a mention proves someone thought about the requirement, not that the test
  asserts it. Treat as a backfill queue.

Two report sections earn their keep beyond the headline number:

- **Manual only** — requirements whose sole cited proof is a human remembering to check.
  This is the tier to empty. `StoreKitClientTests` sat here until 2026-07-21, when the
  "needs the Xcode IDE or a device" blocker turned out to be a bug in the test; it now runs
  headlessly at the `app` tier. Assume the rest are similarly reducible until proven otherwise.
- **Orphan citations** — an id cited by a test but defined in no `spec.md`. That means a
  requirement was renamed or retired while a test kept citing the old id, so the test now
  silently claims to prove something that no longer exists. Currently zero; keep it there.

Note the id grammar has three shorthand forms that a naive regex gets wrong — `FR-1000-01…12`
(a range covering 12 requirements), `FR-1000-05/06`, and `FR-1100-03a`. The feature segment is
**3 or 4 digits**: a `[0-9]{3}` pattern silently drops every 1000/1100-series id and reports
already-cited files as untested.

**Raising the number without lying about it** is a method in its own right — one agent tags, a
second independently tries to refute every tag. See [traceability.md](traceability.md) for the
workflow, the calibration data (what a healthy refutation rate looks like), and the limits of
what a tag actually proves. Most important of those limits: traceability is a **map, not an
alarm** — `coverage.py` is static and will happily report the same percentage after a
regression. Only a running test catches those.

## Known traps — false greens, flakes, and landmines

Each of these has burned at least one debugging cycle. Check here before concluding a
red test means a real regression, or that a green one means success.

### False greens (a pass that proves nothing)

- **Never `-only-testing` a single Swift Testing `@Test`.** The identifier doesn't match
  Swift Testing's selection, so **0 tests run and it reports SUCCEEDED**. Injecting
  `#expect(Bool(false))` still "passes". Target whole classes/targets only. Distrust any
  `passed: 0` + SUCCEEDED result.
- **`XCUIApplication().statusBars` is always empty for this app** — the simulator status
  bar belongs to the system, not the app's accessibility hierarchy. An assertion like
  `statusBars.count == 0` passes whether or not the bar is visible, so it cannot guard
  `.statusBarHidden(…)`. Verify status bar / system overlays **by screenshot**.
- **Screenshots confirm layout, not behaviour.** Assertions only fail when actually run —
  a red `SettingsUITests` sat undetected across two user stories because per-task
  validation was screenshots only. Run the full suite before merging any SwiftUI change.
- **A skip is not a pass, and a skip-guard can outlive its reason.** The seven
  `StoreKitClientTests` cases skip-guarded themselves for a day on the belief that headless
  `xcodebuild` couldn't serve StoreKit products. The belief was wrong (see below) and the
  guard hid it. If a guard says "this environment can't do X", re-test the claim before
  trusting it — otherwise it launders a bug into a documented limitation.

### `SKTestSession` serves 0 products (fixed 2026-07-21)

Two independent setup bugs, both of which *look* like an environment/runner limitation. They
cost a wrong diagnosis ("the StoreKit test daemon isn't active under headless `xcodebuild` —
it's the runner, not the runtime"), a skip-guard, and issue #16. Neither was true: the cases
run for real under plain `xcodebuild test`, on the simulator **and** on both devices.

- **`SKTestSession(configurationFileNamed:)` resolves against `Bundle.main`.** In an
  app-hosted unit test `Bundle.main` is the **host app** bundle, which does not carry
  `Configuration.storekit` — that file is a resource of the **test** bundle. The lookup fails
  **silently**: the initializer does not throw, it returns a session backed by no
  configuration. Symptom: "loads fine, serves 0 products". Worse, with no test configuration
  active, StoreKit falls through to the **real** store, which on an account-less device
  reports `ASDErrorDomain 509 "No active account"` — the false evidence behind issue #16.
  Fix: resolve the URL through `Bundle(for: Self.self)` and use `SKTestSession(contentsOf:)`.
- **`resetToDefaultState()` restores session settings, so it turns `disableDialogs` back
  OFF.** Setting that flag *before* the reset leaves purchase dialogs on, and the Ask-to-Buy
  cases then block forever waiting for a tap no headless run will make — presenting as a hang,
  not a failure. Configure the session **after** resetting it.

Run them anywhere **except one runtime**: `-only-testing:"OwnFrameTests/StoreKitClientTests"`.
Verified 7/7 on iOS 18.6 sim, iPad Pro 11" M4 (18.6), Framepad (17.7.10) and FramePhone
(26.0.1). Always pass `-test-timeouts-enabled YES` so a future dialog regression fails instead
of hanging the run.

> **The iOS 26.4 simulator serves 0 products (found 2026-07-22).** On the **26.4** runtime —
> iPhone **and** iPad Pro 11" M5, so it is the runtime, not the device — `SKTestSession` loads
> the fixture (the `contentsOf:` unwrap succeeds) yet `Product.products(for:)` returns **0 of 3**,
> failing all 7 cases with `productUnavailable`. This is **neither** of the two setup bugs above
> (those are fixed) **nor** a code regression: the identical `main` build is 7/7 on iOS 18.6,
> on the Framepad (17.7.10), and per the line above on 26.0.1 — so 26.4 is a per-build Apple
> simulator-runtime defect. Run StoreKit tests (and the full suite) on **18.6 / 26.5 / a device**
> rather than 26.4 — switch runtimes; re-running the same 26.4 sim won't help.
- **Animations cannot be verified by screenshot or XCUITest** (timing luck / no mid-frame
  access). Use `simctl io … recordVideo` + `ffprobe signalstats` luma traces; a healthy
  transition moves monotonically between the two photos' YAVG levels, a dip below both is
  backdrop bleed (YAVG 16 = black frame). Measure at **full resolution** — a downscaled
  tracker wrongly judged animating builds as "flat".

### Known flakes (rerun in isolation before blaming the diff)

- **`BrokerSetupUITests` flakes under full-suite load only** — two different tests so far
  (2026-07-11, 2026-07-19), both green 3/3 in isolation. Failure shapes are harness-like
  (a partial element tree, a UserDefaults/cfprefsd race around relaunch). Suspect the diff
  only if it touches `BrokerSetupView`/broker config, or the failure shape matches the change.
- **`SharedLinkPasswordUITests` / `SourceOnboardingUITests` segmented-control taps** —
  a synthesized tap on a `.segmented` `Picker` intermittently doesn't register (~50%),
  leaving the wrong segment selected. Known XCUITest/Simulator quirk, not an app bug.
- **A long session degrades the simulator.** After many consecutive `test_sim` runs, one
  run went 7 min → 29 min with spurious hittability failures across unrelated tests.
  `xcrun simctl erase <id>` (shut down first) restores normal timing — do that before
  trusting a bad full-suite run late in a session.

### SwiftUI landmines

- **An always-present `DisclosureGroup` in a `Form` starves a sibling Section's `.task`** —
  even collapsed, even with empty content. Cost ~1 h to bisect: the Storage "Used" label
  stayed "0 bytes" because its async `.task` never settled. Not fixed by gating content on
  the expanded flag or splitting Sections; the `DisclosureGroup` itself is the trigger.
  This is why the *unentitled* HA settings path renders the broker editor **inline**.
- **`withAnimation` in flight during an `.id` swap cancels the transition.** Use scoped
  `.animation(_:body:)`.
- **A state mutation inside `onAppear` merges into the pending render commit** — the
  from-value is never committed and the animation collapses to a still frame. Defer one
  commit via `DispatchQueue.main.async`.
- **Removed `.id`-swap views drop behind opaque ZStack siblings** without explicit `.zIndex`.

### Environment

- **Any runtime ≥ iOS 17 is a valid destination** since the floor was lowered (verified
  17.5 / 18.6 / 26.0 / 26.5 / **27.0 device**) — **except iOS 26.4, on which `SKTestSession` serves 0 products**
  and all 7 `StoreKitClientTests` fail (see that section). Pin **`simulatorId` only** — when
  session defaults carry both `simulatorName` and `simulatorId`, name resolution wins and may
  pick an ineligible runtime (e.g. booting "iPad Pro 11" M5" onto the broken 26.4).
- **New `.swift` files need no `project.pbxproj` edit** — the project uses
  `PBXFileSystemSynchronizedRootGroup`, so files dropped into a synced folder are
  auto-included. SourceKit "No such module" diagnostics in the editor are noise; the build
  is the source of truth.
- **`xcodebuild` never extracts strings into `Localizable.xcstrings`** — only the Xcode IDE
  does. Hand-edit surgically; don't JSON round-trip (Xcode sorts by ICU collation).
- **The simulator's connected hardware keyboard can SIGABRT sheet presentation** (issue #42):
  presenting the tip jar sheet over a landscape iPad Form aborts in UIKit's focus engine
  (`_UIFocusContainerGuideFallbackItemsContainer`, `parentEnvironment != nil` assert) — an
  unfixed UIKit bug (Apple r.154431813, DTS-confirmed, iPadOS 18.6 and 26.0 alike) that runs
  only while a hardware keyboard is attached. No view-level arrangement prevents it
  (`.sheet(item:)`, `NavigationStack`, detents, focus modifiers — all tried). Defused by
  `FocusEngineUITestWorkaround` in `OwnFrameApp.swift`: DEBUG-only, `--uitest`-gated, no-ops
  `UIFocusSystem.updateFocusIfNeeded`, which XCUITest (accessibility-driven) never needs. The
  keyboardless production frame never runs this path. Regression guard:
  `TipJarPresentationUITests` (landscape is load-bearing there — portrait masks the bug).

### iOS 27 on real hardware (session 2026-07-27)

iOS 27 shipped developer beta 1 on 2026-06-08 and is in public beta; GA is expected ~2026-09-14.
FramePhone (iPhone 13 mini) now runs **27.0**. Findings from the first session against it:

**Xcode 26.6 (SDK 26.5) drives an iOS 27 device fine — no Xcode 27 beta needed to test.**
`build`, `build-for-testing`, `devicectl install`, `devicectl process launch --console`, and
full **XCUITest** all work. Two non-fatal log lines are expected and can be ignored:
`DVTDevice: Error locating DeviceSupport directory … nilError` and
`IDELaunchParametersSnapshot: no debugger version`. What does **not** work is **LLDB attach** —
there is no iOS 27 DeviceSupport, so interactive debugging needs the Xcode 27 beta. Test runs
do not need it.

**Submission is not blocked.** The mandate that landed 2026-04-28 requires the *iOS 26* SDK,
which 26.5 already satisfies; the iOS 27 SDK is not expected to be mandatory until ~April 2027.
Do not hold the gated release for iOS 27.

**Green on 27.0:** app launches and runs without crashing, and `StoreKitClientTests` is **7/7**
on device — the release-gating purchase-gate suite is unaffected.

**Seven UI failures, of which six look OS-related.** Full `OwnFrameUITests` on FramePhone/27.0:
154 executed, **7 failures**, 61 skipped (all skips are the intentional env-gated ones —
device-rig, German sweep, live smoke, ASC screenshots).

| Test | 27.0 device | 26.5 sim, iPhone 17 | 26.5 sim, **13 mini** |
|---|---|---|---|
| `SlideshowChromeUITests/testChromeInsetsStableAcrossOrientationAndKenBurns` | fail | **fail** | — |
| `AlbumBrowserUITests/testAlbumBrowserOpensDrillsIn…` | fail | pass | **pass** |
| `BrokerSetupUITests/testExistingBrokerPrefillsFieldsMasksPasswordAndRemoves` | fail | pass | **pass** |
| `BrokerSetupUITests/testImagePublishTogglePersistsAcrossRelaunch` | fail | pass | **pass** |
| `PurchaseGateUITests/testNoLockedRowsWhenEverythingIsUnlocked` | fail | pass | **pass** |
| `PurchaseGateUITests/testUnlockScreenShowsSupporterPriceAndBuyIdentifiers` | fail | pass | **pass** |
| `SourceOnboardingUITests/testOnboardingAddAlbumSourceReachesSlideshowInLandscape` | fail | pass | **pass** |

The chrome-insets one fails on 26.5 too → **pre-existing, not iOS 27**. The other six were
controlled for screen geometry by creating an **iPhone 13 mini simulator on 26.5**
(`xcrun simctl create … iPhone-13-mini … iOS-26-5`) — all six pass there, so it is **not** the
compact form factor. They fail **deterministically** on device (two full runs, near-identical
durations), so it is not timing flake.

**Failure mode is scroll position / hit-testing, not logic.** The messages cluster:
"must be hittable, not merely present", "should have scrolled as far as the MQTT section",
"confirmation step should offer Start". The failure-time hierarchy dump for the broker test
shows `broker.username`/`password`/`save` present while `broker.host`/`port` have scrolled off
and been recycled out of the a11y tree. The suite's swipe-count and
`coordinate(withNormalizedOffset:)` heuristics land differently under iOS 27's layout.
`AppStoreScreenshotUITests` captures all 7 shots on 26.5 but dies after 2 on 27.0.

> **Confound not yet closed:** every 26.5 baseline above is a **simulator**, every 27.0 data
> point is **real hardware**. Simulator-vs-device is therefore not separated from 26.5-vs-27.0.
> Closing it needs the same suite on a real device running iOS 26.x — "iPad jk" (iPad Pro M4)
> and "jk in da house" (iPhone 16 Pro) are both on 26.5.2 and would do it.

#### iOS 27 demoted as the explanation (rechecked 2026-07-28)

The session above called "iOS 27 regression" the leading hypothesis. **Two follow-ups weakened
it. Treat device-vs-simulator as the leading hypothesis instead, and note that the failure
mode is fully explained by test fragility alone.**

**1. The iOS 27 change that would cause this is gated on the iOS 27 SDK, which we don't link.**
The symptom (content scrolled to a different offset, elements present but not hittable) is what
Liquid Glass **bar minimization** produces: `UINavigationItem.barMinimizeBehavior` +
`barMinimizationSafeAreaAdjustment` (SwiftUI: `toolbarMinimizeBehavior(_:for:)`), where the safe
area reflows as the bar minimizes on scroll. That is **SDK-27-gated** — OwnFrame is built with
SDK 26.5, so it should not receive it. The iOS 27 UIKit changes that *do* apply to every binary
regardless of SDK are display-link deprecations, `UILookToScrollInteraction`, iPadOS menu-image
visibility, and trait inheritance through presentation views — none of which move form fields.
*(Forward note: binaries built with the iOS 27 SDK must use the scene-based lifecycle or they
fail to launch. OwnFrame is SwiftUI with `UIApplicationSceneManifest_Generation = YES`, so it is
already compliant.)*

**2. The software keyboard is NOT the difference — and the pref that would control it does
nothing here.** The plausible sim-vs-device delta was that the sim runs with a hardware keyboard
attached (see the issue #42 note above) while FramePhone has none, so on device the software
keyboard would appear and push form content out of the tree — which fits the recorded
`broker.host`/`broker.port`-scrolled-off hierarchy dump exactly. Measured, and it does not hold:

- All six tests **pass** on a fresh iPhone 13 mini / **26.5** sim
  (`E6A5FDB1-0DAC-4326-BBC7-226ADEBCDD24`) — 6/6, 156 s.
- A throwaway probe (focus `onboarding.sharedLink.url`, then assert `app.keyboards` exists)
  showed the **software keyboard appears in headless `xcodebuild test` runs either way**: it was
  present with `ConnectHardwareKeyboard` unset *and* with it explicitly `= 1`. So the sim
  baseline already behaves like the device here; there is no keyboard delta to explain #50.

> **Trap — `ConnectHardwareKeyboard` is not a usable lever, twice over.** (a) Writing it with
> **PlistBuddy is silently discarded**: cfprefsd owns
> `~/Library/Preferences/com.apple.iphonesimulator.plist` and rewrites the device's
> `DevicePreferences` sub-dict, dropping the key — it printed back correctly and was gone by the
> next read. Use `defaults write com.apple.iphonesimulator DevicePreferences -dict-add "<UDID>"
> '{ConnectHardwareKeyboard = 1;}'` (note: this **replaces** that UDID's whole sub-dict).
> (b) Even when it does persist, it **did not change software-keyboard presentation** in a
> headless `xcodebuild test` run. Don't build a control on it without a probe like the one above.
> This does not disprove the issue #42 mechanism — that is a *focus-engine* crash, and only
> keyboard *presentation* was measured here.

**What remains, cheapest first:** (a) run the suite on a real **iOS 26.5** device — `jk in da
house` (iPhone 16 Pro) — which is the one control that actually separates device from OS;
(b) harden the harness regardless, since fixed swipe counts (`maxSwipes = 8`,
`for _ in 0..<3`) and `coordinate(withNormalizedOffset:)` toggle taps are geometry- and
scroll-physics-dependent and will break at every OS bump. Note that
`PurchaseGateUITests/testNoLockedRowsWhenEverythingIsUnlocked` and `AlbumBrowserUITests` never
type at all — they are pure fixed-swipe sweeps, so **test fragility alone already explains the
six failures without invoking iOS 27**.

**Timing:** iOS 27 GA is predicted **2026-09-14**. Submission is genuinely unblocked — Apple's
upcoming-requirements page lists **only** the 2026-04-28 iOS 26 SDK mandate and **no announced
iOS 27 SDK requirement** (the "~April 2027" above is a projection, not an Apple date).

Sources for the above:

- [SDK minimum requirements (Apple Developer)](https://www.developer.apple.com/news/upcoming-requirements/)
- [What's New in UIKit in iOS 27 — Kyle Howells](https://ikyle.me/blog/2026/whats-new-in-uikit-ios-27) (SDK-gated vs. universal split)
- [What's New in SwiftUI for iOS 27 — Blake Crosley](https://blakecrosley.com/blog/whats-new-swiftui-ios-27)
- [iOS 27: UIBarMinimization — Anton Gubarenko](https://antongubarenko.substack.com/p/ios-27-uibarminimization)
- [UIKit's Scene Mandate: What Fails to Launch on iOS 27](https://blakecrosley.com/blog/uikit-scene-lifecycle-mandate-ios-27)
- [iOS 27: Everything We Know — MacRumors](https://www.macrumors.com/roundup/ios-27/) (GA date estimate)
- [Disable hardware keyboard before XCUITest on CI — fastlane#14685](https://github.com/fastlane/fastlane/issues/14685)

**Trap: on a device, test-runner env vars need the `TEST_RUNNER_` prefix.** `SCREENSHOT_CAPTURE=1
xcodebuild …` silently skips the test (the var never reaches the runner);
`TEST_RUNNER_SCREENSHOT_CAPTURE=1` works. Same for `SCREENSHOT_DE` and `LIVE_SMOKE`.

## Live-server contract check (manual, opt-in)

The hermetic UI test proves the *flow*; it does **not** prove the real Immich API
still matches what `ImmichClient` decodes. That contract is verified ad-hoc against
a real server — never committed, credentials passed via the environment:

```bash
# Temporary host test, deleted after running. Reads creds from the environment.
IMMICH_BASE_URL="https://your-immich.example" \
IMMICH_API_KEY="<key>" \
swift test --filter liveServerFullChain
```

Verified against **Immich 2.7.5** (2026-06-18): `serverVersion()` → `"2.7.5"`,
`albums()` decode, `assets(albumID:)` decode (`type: IMAGE`), and
`preview(assetID:)` thumbnail bytes. The routes `ImmichClient` assumes
(`GET /api/server/version`, `/api/albums`, `/api/albums/{id}`,
`/api/assets/{id}/thumbnail?size=preview`, header `x-api-key`) all match the live API.

> Keep secrets out of the repo. If a key has appeared in a transcript or temp file,
> rotate it on the server.

## Environment / tooling

- **XcodeBuildMCP** drives builds/tests — do not parse raw `xcodebuild`. Session
  defaults: scheme **"OwnFrame"**, simulator an **iPad Pro 11" on iOS 18.6 or 26.5**
  (**not** the M5's default 26.4 runtime — it fails every StoreKit test, see above),
  `preferXcodebuild: true` (the incremental builder chokes on project changes).
- **No `axe`/`idb`** UI-automation backend is installed, so XcodeBuildMCP can only
  *observe* the simulator (`snapshot_ui`/`screenshot`), not tap/type. This is why
  interactive UI verification goes through **XCUITest**, not MCP automation.
