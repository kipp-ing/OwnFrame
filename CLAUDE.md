# ImmichSlideshow

iPad slideshow app for Immich. Standalone, **not a fork** of the official Immich app.
Immich serves only as a data source via the REST API.

## Quick Reference
- Platform: iPadOS 26+ (iPhone optional)
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

Active feature: none in flight — v1.0 is in App Store review; `310`/`320` are implemented.
Next up: `800-app-intents` (v1.1), then the roadmap majors `900-photo-library-source`
(amended 2026-07-16: full-access gate, shared-album limits, iOS 27 risk) and `1000-apple-tv`
(specced 2026-07-16; secret sync via CloudKit encrypted fields per constitution v1.1.0).
<!-- SPECKIT END -->
