# OwnFrame

iPad slideshow app for Immich (formerly "Photo Frame for Immich"; the code target/module was
"Immich Slideshow"). Standalone, **not a fork** of the official Immich app.
Immich serves only as a data source via the REST API. Bundle IDs
(`ing.kipp.Immich-Slideshow`) are deliberately unchanged to preserve the App Store record,
Keychain items, and the app group; only the human-readable names were changed to OwnFrame.

## Quick Reference
- Platform: iPadOS/iOS 17+ deployment floor, built against the current SDK (iPad-first, iPhone optional)
- Language: Swift 6
- UI: SwiftUI
- Architecture: MVVM with `@Observable`
- Package Manager: Swift Package Manager
- Test Framework: Swift Testing (`@Test`), XCTest only where needed

## XcodeBuildMCP
This project uses XcodeBuildMCP for builds, tests, and the simulator.
- Run builds/tests via the MCP tools, **not** by parsing raw `xcodebuild` output.
- On red tests: read the error from the structured MCP output, fix it targetedly.
- Use SwiftUI previews for visual verification when the Apple Xcode MCP is active.

## Testing Target (current policy, 2026-07-21 — until further notice)
**iOS first. Framepad is the testing target. tvOS is deferred.**

- **Framepad** — the real frame iPad (iPad Pro 10.5, **iOS 17.7.10 = the deployment floor**) — is
  the reasonable hardware target for all device work. Recipes and traps:
  `docs/device-testing.md`; drive it with `.claude/scripts/framepad.sh`.
- **Do not spend effort on tvOS constraints for now.** tvOS code stays built and compiling, but
  its gates, its missing test target/hermetic seam (issue #17), and any success criterion needing
  a second device are **deferred** — not cancelled. Revisit once the iOS side is fully ready.
- When a requirement can only be verified on tvOS or with two devices, record it as deferred and
  move on rather than blocking iOS progress on it.

## Working Method (binding)
- **TDD**: test first (red), then minimal implementation (green), then refactor. Details in
  `tdd-workflow.md`.
- **SDD via Spec Kit**: no feature code without a prior spec + plan + tasks. See `.specify/`.
- Every module is testable in isolation (protocols + dependency injection, no hidden
  singletons).
- Network behind a protocol (`ImmichAPI`), so tests run without a real server (mock/stub).

## Orchestration: Claude Orchestrates, Codex Implements
A two-model workflow applies to non-trivial implementation work:

- **Claude (you) orchestrates and judges.** Read the task, decide what to delegate, write the
  briefing, review Codex's diff, own the verification gate. Write as little code yourself as
  possible — implementation is delegated.
- **Codex is the implementation army.** Codex agents (via the `codex-agent` CLI of the
  `codex-orchestrator` plugin, or `/codex:rescue` for small/quick tasks) implement against a
  briefing, run their own unit tests, and commit their own work.
- **Cross-model review.** `/codex:review` or `/codex:adversarial-review` for an independent
  look — a different model reviews code it didn't generate itself.

### When to Delegate
Delegate well-scoped implementation work: a feature slice, a bugfix, a refactor with a clear
goal. **Keep inline:**
- Test *design* for shared/concurrent state, races, timing (e.g. the SlideshowView timer)
- Security-critical/cross-cutting work: keychain, TLS, onboarding wiring, app entry point
- SwiftUI/UI that needs the simulator for verification (Codex only tests logic on the host)
- Anything that would break the 2-round limit below — finish it inline instead

### Briefing Workflow
Before delegating:

    .claude/scripts/codex-brief.sh "<task description>" <file1> <file2> ...

This renders a briefing to stdout: task, in-scope files, current `git status` /
`git diff --stat`, verification command, and house rules. `codex-agent start` takes its prompt
as a positional argument (not via stdin), so pass it via command substitution:

    codex-agent start "$(.claude/scripts/codex-brief.sh "..." Packages/ImmichClient/Sources/ImmichClient/ImmichClient.swift)" --map -s workspace-write

`--map` injects `docs/CODEBASE_MAP.md`. This file is **automatically regenerated lean on every
session start** (`.claude/scripts/build-map.sh`, deterministic, no LLM — via the `SessionStart`
hook in `.claude/settings.json`; the file is git-ignored). For the richer, narrated variant, run
`/cartographer` manually when needed (token-intensive — Claude never starts it on its own).
`--dry-run` shows the prompt up front without starting an agent.

### Codex Coding Session (Target Flow)
1. **Map** — automatic on session start (`build-map.sh`); otherwise manual `/cartographer`.
2. **Briefing** — render `codex-brief.sh`, `codex-agent start ... --map` (map gets injected).
3. **Implement** — Codex against the briefing (house rules below, 2-round limit).
4. **Review** — at the end, `/codex:review` (cross-model). Optional as a stop gate via
   `/codex:setup`.

### House Rules (non-negotiable)
- **TDD first:** red test before implementation (constitution, NON-NEGOTIABLE).
- **Only touch files listed in the briefing.** Otherwise stop and report back.
- **No secrets in code/UserDefaults/logs; don't disable TLS** (constitution III/IV).
- **Do not touch:** `.specify/**`, `specs/**`, `*.xcodeproj/project.pbxproj` — unless explicitly
  in scope.
- **Stage only with explicit paths** (`git add <path>`), never `-A`/`.`. On `.git/index.lock`:
  leave it uncommitted and report it.
- **Codex: unit tests only** (`swift test` on the host) — no simulator/integration tests.
- **Hard 2-round limit:** one implement round + one fix round. Otherwise finish inline.
- **Delegate bulk reading of large Codex diffs/logs to an `Explore` subagent**, not direct
  `Read`.

### Verification Gate (owned by Claude)
- Build + tests via **XcodeBuildMCP** (Swift Testing) — the primary gate.
- Codex delivers green `swift build`/`swift test` (host, unit only); Claude additionally
  verifies the app target, simulator, and UI/preview via XcodeBuildMCP.

## Modules
1. **ImmichClient** — REST against Immich. Auth via `x-api-key` header. Endpoints: album list,
   album assets, asset preview thumbnail. URLSession.
2. **SlideshowView** — full screen, one asset, timer, fade. Prefetch of the next 1–2 images.
   Bounded image cache.
3. **Onboarding** — 3 steps: server URL → API key → album. API key in the **keychain**, never
   UserDefaults.
4. **PowerManager** — `isIdleTimerDisabled` during the slideshow; `UIScreen.brightness`
   (0.0–1.0).
5. **ThemeSettings** — transition, duration, Ken Burns, background, clock overlay. In
   UserDefaults. Default: light, calm, no overlay.
6. **HAControl** — MQTT over **TLS** to the existing broker. HA discovery (light/select/switch +
   LWT availability). Remotely controls brightness, album, pause/play.

## Constraints (hard limits, don't design against them)
- An iOS app **cannot physically turn off the display** — only dim brightness toward ~0.
- Brightness/idle timer only take effect **in the foreground**. Once the app goes to the
  background, iOS reclaims control.
- Current state: the Immich server has a **valid** certificate → standard URLSession without a
  TLS exception. Self-signed/local downgrades are **deliberately not** in scope (coming later).
- Check API paths against the OpenAPI spec of the running Immich version
  (`/api/server/version`). Don't rely on paths from old tutorials.

## Prohibitions
- No secrets in code or in UserDefaults. API key + MQTT credentials → keychain.
- Never disable TLS validation (as long as a valid certificate is in place).
- No dependency on the official Immich codebase.

<!-- SPECKIT START -->
Specs are organized as **one durable spec per module**, numbered in hundreds-blocks (`Nxx` per
topic, with `N10/N20…` reserved for sub-specs). Start at `docs/spec-overview.md` for the map and
reading order, then read the relevant module spec under `specs/Nxx-*/spec.md`. FR/SC IDs carry
the full spec number (`FR-700-03`). There is no single "current plan" — each module spec is the
source of truth for its area.

Active feature: `1100-purchase-gate` (branch `1100-purchase-gate`, cut from `main` 2026-07-19) —
spec at `specs/1100-purchase-gate/spec.md`, current plan at `specs/1100-purchase-gate/plan.md`
(+ research/data-model/contracts/quickstart, 2026-07-19). Purchase gate /
one-time unlocks: the free core stays whole (all sources + full core playback, basic
transitions); one paid **Supporter Unlock** grants everything gated — ambience (**Ken Burns
motion + clock overlay**, amended 2026-07-19; never-publicly-shipped features only) *and*
automation (HA/MQTT + App Intents). The former Pro/Automation tiers and the everything-bundle
were **collapsed into that single unlock on 2026-07-23** (PR #40): `Entitlement` has one case,
`ProductCatalog.unlocks` is `[.supporter]`. One-time purchases only, no subscriptions ever,
never the word "lifetime"; Family Sharing + universal purchase (incl. tvOS); on-device
entitlement caching so unattended frames work offline indefinitely; never-claw-back
(FR-1100-13); **sequencing is release-blocking: the gated build must be the first version the
public ever sees — approved v1.0 build 8 stays unreleased (FR-1100-17)**. No price points
anywhere in this public repo — pricing is decided in App Store Connect at submission.
**Status (2026-07-20): implemented on-branch** — new `Packages/PurchaseKit` (entitlement model,
`AmbienceGate` per-photo latch, `StoreClient` + host-testable resolver/cache/store, and now the
**real `StoreKitClient` StoreKit 2 adapter**, `LockedRow`/`UnlockScreenView`/`TipJarView`), gates
at the point of effect in both apps, Unlocks settings section (Restore + tip jar), US5 broker
degradation (masked config behind a locked banner), and launch `refresh()` + `listenForUpdates()`
now wired on both apps' production entry points. **Current measured gate (2026-07-25, iPad Pro
11-inch (M4) sim): PurchaseKit 106 host tests green, full iOS suite 163/0/5** — the 5 skips are
the ASC-screenshot, live-smoke, and 3 device-rig items. (The older "110 host / 153/0/9" figures
predate the tier collapse and the post-PR-#40 review; re-measure before quoting any count.)
**T030 fully done — the old "caveat" was a misdiagnosis, corrected
2026-07-21.** It held that `SKTestSession` serves 0 products under headless `xcodebuild` ("the
runner, not the runtime") so its 7 cases needed the Xcode IDE or a device. Actually two setup bugs
in the test: `configurationFileNamed:` resolves against `Bundle.main` (the *host app* bundle, which
lacks `Configuration.storekit`) and fails **silently**; and `resetToDefaultState()` clears
`disableDialogs`, so setting it first left Ask-to-Buy blocking on a dialog. Both fixed, skip-guard
replaced by a hard assertion, all 7 passing on the iOS 18.6 sim + Framepad (17.7.10) + FramePhone
(26.0.1). Runs headlessly in CI; nothing folds into T042. See `docs/testing.md`; issue #16 closed.
**Resolved:** the two failures a 2026-07-21 run found pre-existing on `main` — `BrokerSetupUITests`
(#21) and `ShareSheetIncomingUITests` (#22, order-dependent) — were fixed in PR #36; both issues are
closed and all six of their cases pass in the 2026-07-25 run. **T033 done (2026-07-20):** the tvOS unlock surface — new `TVSettingsView` (gear
destination) with the ambience locked row, a Home-Assistant row (both Supporter-gated since the
2026-07-23 collapse; they were Pro- and Automation-gated when T033 landed)
(`TVLockedBrokerView` masked-config banner when unentitled), and an Unlocks section (Restore +
tip), reusing PurchaseKit UI via `fullScreenCover`; Apple-TV-simulator screenshot-verified under
the `--uitest-entitlements` seams; the shared unlock/tip screens gained a tvOS-only opaque
backing. **Code-complete (T001–T041 done):** final gate 2026-07-20 — PurchaseKit 110 host + full
iOS XCUITest 153/0/9 (iOS 26.5, same on 18.6) green, iOS + tvOS build. **Remaining: T042 only** —
the manual ASC/device day (create IAPs, sandbox purchase/restore/Family-Sharing/universal checks,
release sequencing v1.0-b8-stays-unreleased → v1.1-gated-first, FR-1100-17); blocked on Jan's ASC
access. Now purely ASC-gated — the StoreKitTest run came off this list on 2026-07-21.

Prior feature `1000-apple-tv` (tvOS port + 13 review fixes + Ken Burns micro-judder redesign:
shared scoped-animation `KenBurnsMotionModifier` + `DecodedImageStore` decode-ahead) is
**merged to main + pushed (2026-07-18)**. Remaining there: real-hardware device gates
(SC-1000-02/05/06/08, CloudKit-decrypt-on-tvOS proof, 24h soak), real MQTT/CloudKit, and the
tvOS clock + FR-1000-10 pixel-shift — tick-list in `docs/manual-verification.md` ("FINAL DEVICE
DAY"). Earlier context: `510` clock merged; `900`/`800`/`220` merged + implemented (their device
ship-gates share that same device day); v1.0 in App Store review; `310`/`320` implemented.
<!-- SPECKIT END -->
