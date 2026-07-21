# Testing Guide

How this project is tested, and how to run each layer. All commands go through
**XcodeBuildMCP** (or `swift` on the host) — see [CLAUDE.md](../CLAUDE.md) for the
constitution-level rules (TDD first; see also [tdd-workflow.md](../tdd-workflow.md)).

## The test pyramid

| Layer | Where | Runs on | Speed | What it covers |
|-------|-------|---------|-------|----------------|
| **Unit (host)** | `Packages/*/Tests` | macOS host (`swift test`) | sub-second | Pure module logic behind protocols (API decode, view-model state, config/keychain stores) |
| **App-hosted** | `Immich SlideshowTests` | iOS Simulator | seconds | Things that need the real device runtime: real Keychain round-trip, reset, integration decode |
| **UI (XCUITest)** | `Immich SlideshowUITests` | iOS Simulator | ~10–20 s/test | The user-facing flow, driven end to end and hermetically |

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

## Layer 2 — App-hosted tests (`Immich SlideshowTests`)

These link the packages into the app and run on the simulator — used where the
host can't help: the **real `KeychainAPIKeyStore`** round-trip, the reset flow
(real key removal), and `ImmichClient` integration decode against a stub transport.

Run the whole simulator suite:

```text
XcodeBuildMCP → test_sim   (scheme "Immich Slideshow", iPad Pro 11" M5, preferXcodebuild: true)
```

## Layer 3 — UI tests (hermetic XCUITest)

This is the first-party "Xcode way" to test the SwiftUI flow. It is **hermetic**:
no live server, no real Keychain, fully deterministic and CI-safe.

**How it works:**

1. The test launches with a flag:
   ```swift
   app.launchArguments = ["--uitest"]
   ```
2. That trips a **DEBUG-only** seam, `UITestSupport`, in
   `Immich Slideshow/Immich_SlideshowApp.swift`. It injects a **stub `ImmichAPI`**
   (canned albums) plus **in-memory** `ConfigStore`/`KeychainStore`. The production
   launch path is untouched and the seam is never compiled into Release.
3. Views carry **accessibility identifiers** as stable anchors:

   | Identifier | Element |
   |------------|---------|
   | `onboarding.serverURL` | server URL text field |
   | `onboarding.server.continue` | "Weiter" button (step 1) |
   | `onboarding.apiKey` | API-key secure field |
   | `onboarding.apiKey.connect` | "Verbinden" button (step 2) |
   | `onboarding.album.<id>` | each album row |
   | `main.completed` | the post-onboarding main screen |

**Current tests** (`Immich SlideshowUITests/Immich_SlideshowUITests.swift`):

- `testOnboardingHappyPathReachesMainScreen` — drives Server → API key → album → main screen.
- `testFreshLaunchShowsServerStep` — a fresh launch starts at step 1.

**Run just the flow** (skips the slow launch-perf suite):

```text
test_sim  extraArgs:
  -only-testing:Immich SlideshowUITests/Immich_SlideshowUITests/testOnboardingHappyPathReachesMainScreen
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

Run them anywhere: `-only-testing:"Immich SlideshowTests/StoreKitClientTests"`. Verified
2026-07-21 on iOS 18.6 sim, Framepad (17.7.10) and FramePhone (26.0.1) — 7/7 each. Always pass
`-test-timeouts-enabled YES` so a future dialog regression fails instead of hanging the run.
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
  17.5 / 18.6 / 26.x). Pin **`simulatorId` only** — when session defaults carry both
  `simulatorName` and `simulatorId`, name resolution wins and may pick an ineligible runtime.
- **New `.swift` files need no `project.pbxproj` edit** — the project uses
  `PBXFileSystemSynchronizedRootGroup`, so files dropped into a synced folder are
  auto-included. SourceKit "No such module" diagnostics in the editor are noise; the build
  is the source of truth.
- **`xcodebuild` never extracts strings into `Localizable.xcstrings`** — only the Xcode IDE
  does. Hand-edit surgically; don't JSON round-trip (Xcode sorts by ICU collation).

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
  defaults: scheme **"Immich Slideshow"**, simulator **iPad Pro 11" (M5)**,
  `preferXcodebuild: true` (the incremental builder chokes on project changes).
- **No `axe`/`idb`** UI-automation backend is installed, so XcodeBuildMCP can only
  *observe* the simulator (`snapshot_ui`/`screenshot`), not tap/type. This is why
  interactive UI verification goes through **XCUITest**, not MCP automation.
