# Data Model — 310 Slideshow Resilience

Phase 1 output. All types live in `Packages/SlideshowKit/Sources/SlideshowKit/`. Nothing here
persists — every field below is in-memory engine state, gone on view-model teardown.

## RetryPolicy (new, `RetryPolicy.swift`)

Backoff math and attempt state. A plain `struct` mutated by the view model (single `@MainActor`
owner, no locking needed).

| Field | Type | Meaning |
|---|---|---|
| `configuration` | `Configuration` | Tuning constants (below) |
| `attempt` | `Int` | Failed attempts since the last success/reset; drives the exponent |
| `rng` | injected `RandomNumberGenerator` | Jitter source; seeded in tests |

`Configuration` (value type, `.default`):

| Constant | Default | Spec |
|---|---|---|
| `initialDelay` | 1 s | FR-310-02 |
| `factor` | 2 | FR-310-02 |
| `maxDelay` | 300 s | FR-310-02 |
| `jitter` | ±20 % | FR-310-02, retry-storm edge case |

Operations:

- `nextDelay(for error: any Error) -> Duration` — classifies the error, increments `attempt`,
  returns the jittered delay. **Transient**: `min(initial × factor^(attempt-1), max)` ± jitter.
  **Auth** (`.unauthorized`, `.shareLinkExpired`, `.wrongPassword`, `.passwordRequired`):
  always `maxDelay` ± jitter, regardless of attempt count (FR-310-05 — no hot loop, but also
  no slow climb: the server may be temporarily misconfigured).
- `reset()` — attempt back to 0. Called on any successful fetch and on manual retry
  (FR-310-02/04).
- `static classify(_ error: any Error) -> SlideshowFailureReason` — `.authentication` for the
  four auth cases of `ImmichError`, `.transient` for everything else (including
  non-`ImmichError`).

State transitions: `attempt` 0 → 1 → 2 → … (delay saturates at `maxDelay`); any success ⇒ 0.

## SlideshowFailureReason (new, in `RetryPolicy.swift`)

```
enum SlideshowFailureReason: Sendable, Equatable { case transient, authentication }
```

Exposed on the view model as `failureReason: SlideshowFailureReason?` — `nil` while healthy,
set on fetch failure, cleared on success. Drives the `SlideshowErrorView` message variant
(FR-310-05). `SlideshowPhase` itself is **unchanged** (research R3).

## Refresh Schedule (view-model state, not a separate type)

| Field | Type | Meaning |
|---|---|---|
| `lastSuccessfulRefresh` | `Duration?` (monotonic `clock.now`) | Stamped by every successful asset-list fetch — initial load, hourly refresh, or a retry that recovered the source (research R4) |
| `refreshInterval` | `Duration` from `SlideshowConfig` (default 3600 s) | FR-310-06 |

Rules:

- Refresh due at `lastSuccessfulRefresh + refreshInterval` (monotonic — immune to wall-clock
  jumps, clock-change edge case).
- Foreground return: refresh immediately iff `clock.now - lastSuccessfulRefresh >
  refreshInterval` (FR-310-10, US3).
- Runs across `.playing`, `.empty`, and `.failed` phases — an empty source that regains photos
  on the server recovers on the next tick (US2 scenario 6 is symmetric).
- Never runs while backgrounded — `pause()` cancels, `resume()` re-arms (FR-310-10).

## RotationReconciler (new, `RotationReconciler.swift`)

Pure, stateless. One static function (research R5):

```
reconcile(oldAssets: [Asset], newAssets: [Asset],
          playOrder: [Int], cursor: Int,
          order: PlayOrder, currentAssetID: String?,
          rng: inout some RandomNumberGenerator)
  -> (playOrder: [Int], cursor: Int)
```

Invariants (validation rules — each is a test):

1. Output `playOrder` is a full permutation of `newAssets.indices` — the engine's count guard
   never triggers a surprise rebuild after a refresh.
2. Identical lists (same IDs, same order) ⇒ inputs returned unchanged, bitwise — the
   refresh-no-op edge case.
3. **Sequential**: output is the identity permutation; cursor points at `currentAssetID`'s
   position in the new list (additions appear at album position, FR-310-08).
4. **Shuffle**: relative order of surviving entries in the current cycle is preserved (played
   prefix stays played, unplayed suffix stays pending — FR-310-07 "no mid-cycle restart");
   removed assets drop out; added assets are shuffled *into the unplayed remainder only*
   (join no later than the current cycle's end — stricter than FR-310-08's "next cycle").
   Every photo exactly once per cycle (FR-300-05 invariant).
5. **Removed current photo**: cursor lands on the slot *before* the photo that would have
   followed it, so the next `advance()` shows that successor; the currently displayed image
   data is not touched (finishes its slot, then skipped — FR-310-08, SC-310-03). Removed
   current at cycle end ⇒ next advance starts a new cycle, as it would have.
6. Empty `newAssets` is never passed in — the view model routes that to `.empty` first
   (US2 scenario 6).

## SlideshowClock (new protocol, `SlideshowClock.swift`)

| Member | Contract |
|---|---|
| `now: Duration` | Monotonic elapsed time since an arbitrary fixed epoch; never jumps backwards |
| `sleep(for: Duration) async throws` | Returns after the duration; throws `CancellationError` on task cancellation |

Production: `ContinuousSlideshowClock` over `ContinuousClock`. Test: `TestClock` in
`Fakes.swift` — `advance(by:)` moves `now` and resumes all sleepers whose deadline passed,
deterministically (FR-310-12).

## SlideshowViewModel — new/changed state (existing type)

| Field | Change |
|---|---|
| `failureReason: SlideshowFailureReason?` | NEW, published (`@Observable`) |
| `retryPolicy: RetryPolicy` | NEW, private |
| `clock: any SlideshowClock` | NEW, injected (init default: `ContinuousSlideshowClock()`) |
| `retryTask`, `refreshTask: Task<Void, Never>?` | NEW, private — same weak-self detached style as `runTask` |
| `lastSuccessfulRefresh: Duration?` | NEW, private (monotonic) |
| `pendingRetry` context | NEW, private — which operation to re-attempt: source reload vs reload-from-cursor (research R4) |

Behavioral deltas (each maps to an FR):

- Fetch failure in `start()`/refresh: keep phase/image if something is showing (FR-310-03),
  else `.failed` + `failureReason`; always arm the retry task (FR-310-01).
- Image-load exhaustion in `step()`: keep showing the current image, stop the advance ticker,
  arm retry (FR-310-03) — replaces today's unconditional `phase = .failed`.
- `retry()` (manual): allowed from `.failed` *or* whenever a retry is pending; cancels the
  pending timer, resets backoff, attempts immediately (FR-310-04).
- Successful refresh: reconcile via `RotationReconciler`, re-point prefetch; **no** phase
  change, **no** ticker restart, **no** `currentImageData` write (FR-310-07, SC-310-05).
- `pause()`/`resume()`: cancel/re-arm both tasks; overdue work fires immediately on resume
  (FR-310-10, US3). Re-arm is independent of `isPaused` (research R7).
- `start()` (also via `switchAlbum`): cancels both tasks, resets policy +
  `lastSuccessfulRefresh` before fetching — timers rebind, nothing leaks (FR-310-11).
