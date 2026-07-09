# Implementation Plan: Slideshow Resilience (Auto-Retry + Periodic Refresh)

**Branch**: `310-slideshow-resilience` | **Date**: 2026-07-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/310-slideshow-resilience/spec.md`

## Summary

Make the slideshow engine survive unattended operation: transient failures auto-retry with
exponential backoff (1 s → ×2 → 5 min cap, ±20 % jitter, reset on success), and the active
source's asset list re-fetches hourly so new photos enter rotation without a restart. All new
behavior lives in `SlideshowKit`'s `SlideshowViewModel`, behind a new injected monotonic
clock/scheduler seam (`SlideshowClock`) that follows the existing `SlideshowTicker` pattern —
no real timers anywhere in tests (FR-310-12). Three new pure/isolated types carry the logic:
`RetryPolicy` (backoff math + transient-vs-auth classification over the existing `ImmichError`
taxonomy — no topic-100 amendment needed), `RotationReconciler` (pure diff of playing list vs
freshly fetched list, preserving the current photo and the shuffle-cycle invariant), and the
`SlideshowClock` protocol (production impl on `ContinuousClock`). `SlideshowPhase` stays
unchanged (it is matched in HAControlKit and three app views); the auth-vs-transient
distinction surfaces as a new `failureReason` property that `SlideshowErrorView` renders as an
actionable message. App-side changes are minimal: inject the production clock, show the
actionable auth text.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: Foundation, Observation, Swift Testing; existing packages
SlideshowKit (host of all new logic), ImmichClient (error taxonomy, unchanged), ThemeKit
(order/duration settings, unchanged). No new external dependencies.

**Storage**: N/A — retry/refresh state is in-memory only (monotonic instants, attempt
counter). Nothing persists; nothing touches UserDefaults or the Keychain.

**Testing**: Swift Testing (`@Test`) on the host (`swift test` in `Packages/SlideshowKit`)
against `StubImmichAPI`, `ManualTicker`, a new `TestClock` fake, and the existing seeded RNG;
XcodeBuildMCP `test_sim` (whole test classes — single-`@Test` runs are a false green) for the
app target; full XCUITest before merging the SwiftUI changes.

**Target Platform**: iPadOS 26+ on `main` (an iOS 17 floor exists on the unmerged
`feat/ios17-deployment-target` branch; this feature uses no API newer than iOS 17).

**Project Type**: Mobile app (SwiftUI, MVVM with `@Observable`), Swift Package Manager modules

**Performance Goals**: recovery within one current-backoff interval of the fake server
returning (SC-310-01); a completed refresh leaves the on-screen photo's timer untouched — no
stall, no flicker, no timer reset (SC-310-05); a long simulated run of network flaps ends with
the show still advancing and memory inside the existing cache bounds (SC-310-06).

**Constraints**: foreground-only — no retry/refresh timer fires in the background (FR-310-10,
FR-300-14); intervals measured on a monotonic reference, immune to wall-clock/timezone jumps;
no hot loop against auth errors (cap-only retry, FR-310-05); jittered backoff so many frames
behind one server don't synchronize (edge case "retry storm"); failure paths never log secrets
(FR-310-13); no real timers in unit tests (FR-310-12).

**Scale/Scope**: one package (`SlideshowKit`: 3 new source files, 2 modified) + 3 app files
touched; ~3 new host test suites plus additions to `SlideshowViewModelTests`; no new entities
outside the engine.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Test-First (NON-NEGOTIABLE)**: PASS — every slice lands red-first on the host:
  `RetryPolicy` (backoff sequence, jitter bounds, classification), `RotationReconciler`
  (add/remove/current-photo cases), and the view-model loops (retry, refresh, foreground
  return) against the injected `TestClock`/`StubImmichAPI`. UI change (auth message) is
  preview-verified and covered by the existing UITest suite run.
- **II. Modular Isolation**: PASS — time is injected via the new `SlideshowClock` protocol
  (same seam style as `SlideshowTicker`); network stays behind `ImmichAPI`; the two new logic
  types are pure values with no dependencies. No hidden singletons.
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)**: PASS — no new storage at all; FR-310-13
  reasserts that failure-path logging carries status/paths only (existing `ImmichClient` log
  style), never the API key or shared-link password.
- **IV. Transport-Layer Security**: PASS — no transport changes; retries re-use the same
  TLS-validated `URLSession` path through the existing client.
- **V. Respect Platform Boundaries**: PASS — the feature is explicitly designed *inside* the
  foreground-only boundary: `pause()` cancels all timers, `resume()` re-arms them and
  compensates for background time via the stale-on-return check instead of background timers.
- **VI. Verifiable Acceptance Criteria**: PASS — SC-310-01…06 each map to a deterministic
  host test under the injected clock (see quickstart.md); the backoff sequence and jitter
  bounds are asserted numerically with a seeded RNG.
- **VII. Plain and Light by Default**: PASS — no new UI surface or setting (60-minute refresh
  is a fixed default by design); the only visible change is a calmer, more actionable error
  message when auth is the cause.

**Result**: PASS — no violations; Complexity Tracking left empty.

## Project Structure

### Documentation (this feature)

```text
specs/310-slideshow-resilience/
├── plan.md                          # This file
├── research.md                      # Phase 0 — seam shape, failure surface, loop topology,
│                                    #   reconciliation strategy, config placement
├── data-model.md                    # Phase 1 — RetryPolicy, RefreshSchedule, RotationDiff
├── quickstart.md                    # Phase 1 — validation scenarios mapped to FR/SC
└── contracts/
    └── slideshow-resilience-api.md  # Phase 1 — SlideshowClock protocol, RetryPolicy surface,
                                     #   SlideshowViewModel API additions
```

### Source Code (repository root)

```text
Packages/SlideshowKit/Sources/SlideshowKit/
├── SlideshowClock.swift        # NEW: monotonic now + sleep(for:) protocol (SlideshowTicker
│                               #   pattern); ContinuousSlideshowClock production impl
├── RetryPolicy.swift           # NEW: backoff math (initial 1 s, ×2, cap 300 s, ±20 % jitter
│                               #   via injected RNG), attempt state, reset; classifies
│                               #   ImmichError into transient vs auth (auth ⇒ cap-only delay)
├── RotationReconciler.swift    # NEW: pure diff (old assets, new assets, playOrder, cursor,
│                               #   order) → (playOrder, cursor); preserves current photo and
│                               #   the shuffle cycle; additions join per active order
├── SlideshowViewModel.swift    # retry loop + refresh loop as cancellable tasks (weak self,
│                               #   same style as runTask); failureReason: published auth/
│                               #   transient distinction; pause() cancels / resume() re-arms
│                               #   with overdue-fires-immediately; retry() resets backoff;
│                               #   switchAlbum/start rebind all timers to the new source
├── SlideshowConfig.swift       # + refreshInterval (Duration, default 3600 s) — fixed
│                               #   plumbing, not user-facing, same charter as prefetch/cache
└── SlideshowPhase.swift        # UNCHANGED (matched in HAControlKit + 3 app views; failure
                                #   detail lives in the view model instead)

Packages/SlideshowKit/Tests/SlideshowKitTests/
├── Fakes.swift                 # + TestClock (manual monotonic clock: advance(by:) releases
│                               #   due sleepers deterministically)
├── RetryPolicyTests.swift      # NEW: sequence, cap, jitter bounds (seeded RNG), reset,
│                               #   classification per ImmichError case
├── RotationReconcilerTests.swift  # NEW: additions (sequential position / shuffle remainder),
│                               #   removals, removed-current-photo, same-list no-op
└── SlideshowResilienceTests.swift # NEW: view-model level — US1/US2/US3 acceptance scenarios
                                #   under TestClock + StubImmichAPI (see quickstart.md)

Immich Slideshow/
├── Immich_SlideshowApp.swift   # inject ContinuousSlideshowClock() at the two
│                               #   SlideshowViewModel build sites (default parameter keeps
│                               #   this a one-line change per site)
└── Slideshow/
    ├── SlideshowView.swift     # pass viewModel.failureReason into SlideshowErrorView
    └── SlideshowErrorView.swift # actionable message variant for auth failures
                                #   ("check your connection settings"), FR-310-05

Packages/ImmichClient/          — no changes (ImmichError already separates unauthorized /
                                  unreachable / invalidResponse; shared-link secret errors
                                  exist for resolve-time; classification lives in SlideshowKit)
Packages/HAControlKit/          — no changes (phase enum untouched; retry/refresh diagnostics
                                  are explicitly Roadmap, not in scope)
```

**Structure Decision**: All resilience logic stays inside `SlideshowKit` — the engine already
owns the advance timer, the asset list, and the play order, and the two new concerns (when to
re-fetch, how to merge a re-fetch) are engine concerns. Sources are resolved upstream into
`api + albumID` before the view model exists, so FR-310-11's "identical for both source
kinds" holds by construction: shared-link and API-key album sources pass through the same
`ImmichAPI` seam, and both source-switch paths (`switchAlbum` and the full rebuild) already
funnel through `start()` / view-model teardown, where timers are cancelled and re-armed. The
classification of `ImmichError` into transient-vs-auth lives in `SlideshowKit` (policy), not
`ImmichClient` (mechanism) — the client keeps reporting *what* happened, the engine decides
*how to react*, and the spec's topic-100-amendment contingency turns out not to be needed.

## Complexity Tracking

> No constitution violations — section intentionally empty.
