# Research — 310 Slideshow Resilience

Phase 0 output. Resolves the design unknowns for auto-retry + periodic refresh. No external
research needed — every decision is an internal architecture choice against existing code.

## R1 — Shape of the time seam

**Decision**: A new `SlideshowClock` protocol in `SlideshowKit` with exactly two requirements:
a monotonic `now` (a `Duration` since an arbitrary epoch) and `sleep(for: Duration) async
throws` (cancellation-transparent). Production implementation `ContinuousSlideshowClock` wraps
`ContinuousClock`. Tests use a `TestClock` fake whose `advance(by:)` releases due sleepers
deterministically.

**Rationale**: FR-310-12 demands injected scheduling; FR-310-10 and the clock-jump edge case
demand a *monotonic* "now" for staleness math ("last successful refresh older than the
interval"), which the existing `SlideshowTicker` seam cannot provide (it is sleep-only, re-armed
per advance cycle). A tiny house protocol follows the proven `SlideshowTicker` pattern and
keeps the test double trivial.

**Alternatives considered**:
- *Swift's `Clock` protocol directly* (`any Clock<Duration>`): rejected — conforming a manual
  test clock (custom `Instant`, `sleep(until:)` bookkeeping) is substantially more code than
  the two-method seam, for no added power here.
- *swift-clocks package (pointfree)*: rejected — new third-party dependency for ~30 lines.
- *Extend `SlideshowTicker`*: rejected — the ticker is the *advance* seam with live-duration
  re-arming semantics; overloading it with monotonic-now would churn green tests and conflate
  two concerns.

## R2 — Transient vs. auth classification

**Decision**: Classification lives in `SlideshowKit` (a function on `RetryPolicy`), mapping
the existing `ImmichError`: **auth** = `.unauthorized`, `.shareLinkExpired`, `.wrongPassword`,
`.passwordRequired`; **transient** = `.unreachable`, `.invalidResponse`, and any non-`ImmichError`
error. Auth failures retry at the backoff cap only (FR-310-05); transient failures walk the
full backoff curve.

**Rationale**: The spec's assumption ("topic 100 already distinguishes… if not, amendment in
scope") resolves to *no amendment needed*: `ImmichClient.responseData` already maps 401/403 →
`.unauthorized` and `URLError` → `.unreachable`. The shared-link secret errors exist for
resolve-time flows but are included defensively — they are unambiguous auth conditions.
Policy (how to react) belongs to the engine, mechanism (what happened) to the client.

**Alternatives considered**: an `isTransient` property on `ImmichError` in `ImmichClient` —
rejected; it would encode retry policy into the transport package and force topic-100 spec
surgery for a consumer-side concern.

## R3 — Where the failure detail surfaces

**Decision**: `SlideshowPhase` stays exactly as is. The view model gains
`public private(set) var failureReason: SlideshowFailureReason?` (`.transient` /
`.authentication`), set whenever a fetch fails and cleared on success. `SlideshowErrorView`
renders the actionable auth message ("check your connection settings") when the reason is
`.authentication`; the existing generic message otherwise.

**Rationale**: `phase == .failed` and `case .failed` are matched in
`SlideshowRemoteControlAdapter` (mapped into HAControlKit's own phase enum), `SlideshowView`,
`AlbumBrowserView`, and `SourceLibraryView`. An associated value would ripple through all of
them plus HAControlKit for zero benefit — HA diagnostics for retry state are explicitly
Roadmap, not in scope.

**Alternatives considered**: `case failed(SlideshowFailureReason)` — rejected per above;
a separate observable `RetryStatus` object — rejected, over-engineered for one label.

## R4 — Loop topology: how retry and refresh relate

**Decision**: Two concerns, one backoff. The view model keeps **one `RetryPolicy` instance**
and **two cancellable tasks** (`retryTask`, `refreshTask`), both weak-self detached in the
existing `runTask` style, both cancelled in `pause()` and re-armed in `resume()`:

- **Refresh loop** (FR-310-06): sleeps until `lastSuccessfulRefresh + refreshInterval` on the
  monotonic clock, then re-fetches the asset list and reconciles. Success updates
  `lastSuccessfulRefresh` and resets the backoff. Failure does *not* touch the playing
  rotation (FR-310-09) — it hands over to the retry loop and the refresh loop re-arms after
  the retry succeeds.
- **Retry loop** (FR-310-01): armed whenever a source fetch or an image-load pass fails.
  Sleeps `policy.nextDelay(for: error)`, then re-attempts *the operation that failed*: a full
  source reload when the list fetch failed (start/refresh path), a reload-from-cursor when an
  image load exhausted the cycle (step path). On success: reset backoff, clear
  `failureReason`, resume normal operation (ticker restarts if it was running).

The retry loop is the single owner of backoff state; the refresh loop never sleeps on backoff
durations. A refresh due while a retry is pending is subsumed by the retry (its success path
is a fresh list fetch + reconcile, which *is* a refresh and stamps `lastSuccessfulRefresh`).

**Rationale**: One backoff curve matches the spec's single Retry Policy entity and prevents
two loops hammering the same dead server on different schedules. Keeping the tasks separate
(rather than one merged min-deadline loop) keeps each loop's test assertions independent and
mirrors how the acceptance scenarios are written (US1 vs US2).

**Alternatives considered**: a single merged scheduler task computing
`min(refreshDue, retryDue)` — rejected as harder to reason about and test; independent backoff
per concern — rejected (double-fetch races against one dead server, two sources of truth).

## R5 — Rotation reconciliation without breaking the cycle

**Decision**: A pure static function `RotationReconciler.reconcile(old:new:playOrder:cursor:order:rng:)
→ (playOrder: [Int], cursor: Int)` over asset-index permutations:

- **Sequential**: new play order is the identity permutation of the new list; cursor points at
  the current photo's position in the new list. Additions thereby appear exactly at their
  album position (FR-310-08).
- **Shuffle**: the current cycle is preserved — already-played and upcoming entries are
  remapped to new-list indices, removed assets are dropped from the remainder, and *added
  assets are shuffled into the unplayed remainder* of the current cycle. Every photo still
  appears exactly once per cycle (FR-300-05 invariant) and additions join "no later than the
  next cycle" (they join the current one). No reshuffle of the played portion, so FR-310-07's
  "no mid-cycle restart" holds.
- **Removed current photo**: the cursor is placed on the *slot before the next photo to play*
  (the reconciler returns the cursor such that the next `advance()` lands on what would have
  followed the removed photo). The on-screen image data is untouched — the photo "finishes its
  slot" and is skipped afterwards (FR-310-08, SC-310-03). If the removed current was the
  cycle's last entry, the next advance starts a new cycle, as it would have anyway.
- **Same list**: reconcile returns the inputs unchanged — a strict no-op (edge case: no
  reshuffle, no timer reset).

The output play order is always a full permutation of the new asset list, so
`ensureSequenceForCurrentOrder`'s `playOrder.count != imageAssets.count` guard never fires a
surprise rebuild after a refresh.

**Rationale**: The engine's existing invariants (full permutation, count-guard rebuild,
anchor-preserving order switches) dictate the contract. Making it a pure value-level function
gives the fiddly diff logic its own exhaustive host test suite — this is also the cleanest
Codex-delegable slice.

**Alternatives considered**: "just call `rebuildSequence` after swapping the list" — rejected:
reshuffles mid-cycle (violates FR-310-07) and loses cursor anchoring on removals; deferring
all additions to the next cycle in shuffle — allowed by spec but strictly worse than joining
the unplayed remainder, and costs the same code.

## R6 — Where the tuning constants live

**Decision**: `SlideshowConfig` gains `refreshInterval: Duration = .seconds(3600)`.
`RetryPolicy` carries its own backoff constants (initial 1 s, factor 2, cap 300 s, jitter
±20 %) as a `RetryPolicy.Configuration` with a `.default`, injected into the view model with
the policy.

**Rationale**: `SlideshowConfig`'s charter is exactly "fixed slideshow plumbing parameters…
not user-facing" — the refresh interval is one (spec Assumptions: deliberately not a setting).
Backoff constants belong with the math that uses them; tests override them per-case without
touching the shared config.

**Alternatives considered**: everything in `SlideshowConfig` — rejected, drags five
retry-only numbers into an unrelated type; a UserDefaults-backed setting — explicitly out of
scope (spec: Roadmap).

## R7 — Foreground/background and source-switch semantics

**Decision**: `pause()` cancels `retryTask`/`refreshTask` alongside the ticker task; the due
times (`nextRetryDue`, monotonic) survive as stored state. `resume()` re-arms both: overdue
work fires immediately (US3 scenarios 1/3), otherwise sleep the remaining time. The re-arm is
independent of `isPaused` (a user-paused frame still refreshes its list and recovers its
connection; only auto-advance stays stopped). `start()` — which both `switchAlbum` and the
retry path use — cancels both tasks, resets the policy and `lastSuccessfulRefresh`, so timers
always rebind to the new source and never leak from the old one (FR-310-11). The app-side
full-rebuild path discards the view model; weak-self detached tasks die with it (existing
`runTask` pattern).

**Rationale**: This is FR-310-10/FR-300-14 alignment with the least machinery — the app
already routes scenePhase into `pause()`/`resume()` (`SlideshowView.swift:110-120`), so no new
lifecycle plumbing is needed. Refresh-while-user-paused is deliberate: FR-310-06 gates on
foreground, not on playback intent, and a stale paused frame violates US2's promise the moment
it is unpaused.
