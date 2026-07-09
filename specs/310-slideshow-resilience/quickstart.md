# Quickstart — Validating 310 Slideshow Resilience

How to prove the feature works, end to end. Contracts:
[contracts/slideshow-resilience-api.md](./contracts/slideshow-resilience-api.md); entity
rules: [data-model.md](./data-model.md).

## Prerequisites

- macOS host with the repo checked out on `310-slideshow-resilience`.
- No server, no network: every scenario below runs against `StubImmichAPI` + `TestClock`
  (FR-310-12 — real timers are a spec violation, not a convenience).
- Simulator gates run through XcodeBuildMCP (session defaults: see memory
  `sim-build-destination` — only iOS 26.5 sims build the app scheme).

## Host gate (primary)

```bash
cd Packages/SlideshowKit && swift test
```

Green means all four suites pass:

| Suite | Proves | Spec IDs |
|---|---|---|
| `RetryPolicyTests` | delay sequence 1 s → ×2 → 300 s cap, jitter within ±20 % (seeded RNG, numeric bounds), reset-on-success, auth ⇒ cap-only, classification table | FR-310-02/05, SC-310-04 |
| `RotationReconcilerTests` | permutation invariant, identical-list no-op, sequential anchor, shuffle cycle preservation + additions in unplayed remainder, removed-current cursor rule | FR-310-07/08, SC-310-03 |
| `SlideshowResilienceTests` | the acceptance-scenario table below | US1/US2/US3 |
| `SlideshowViewModelTests` (existing, extended) | no regression: advance/pause/shuffle/duration behavior unchanged | FR-300-* |

### Acceptance scenarios → tests (US1/US2/US3)

Each row is one deterministic test: arrange `StubImmichAPI` state, drive `TestClock.advance`,
assert.

1. **Mid-playback fetch failure** — image load starts failing: current photo stays on screen,
   `assetsCallCount`/`previewCallCount` grow on the backoff schedule, no phase change (US1-1).
2. **Dead server at launch** — `setAssetsError(.unreachable)` before `start()`: `phase ==
   .failed`, `failureReason == .transient`; clear the error, advance one backoff interval:
   `phase == .playing` with no user input (US1-2, SC-310-01).
3. **Recovery resets backoff** — fail 5×, recover, fail again: next delay is back at ~1 s
   (US1-3/4).
4. **Manual retry** — pending 5-min backoff, call `retry()`: immediate fetch, backoff reset
   (US1-5).
5. **Auth failure** — `setAssetsError(.unauthorized)`: `failureReason == .authentication`,
   observed delays all ≈ cap (US1-6).
6. **Hourly refresh** — advance 60 min: exactly one extra `assets()` call; `currentAssetID`,
   ticker deadline, and cursor unchanged (US2-1/3, SC-310-05).
7. **Additions** — sequential: new asset appears at album position; shuffle (seeded): appears
   within the current cycle's remainder, cycle invariant holds (US2-2, SC-310-02).
8. **Removals** — removed asset never shown again; removing the *current* asset keeps it on
   screen until the next advance, then skips it; no crash, no blank (US2-5, SC-310-03).
9. **Refresh failure** — stale list keeps playing, retry loop engages, no error surface
   (US2-4).
10. **Empty on refresh** — next refresh finds zero assets: `phase == .empty` (US2-6).
11. **Background/foreground** — `pause()`, advance the clock hours, no fetches happen;
    `resume()`: immediate refresh (stale) and pending retry fires (US3-1/2/3, FR-310-10).
12. **Source switch mid-retry** — `switchAlbum` while a retry is pending: old timers dead,
    new source fetched fresh, backoff reset (FR-310-11).
13. **Long-run soak** — scripted loop of flaps + refreshes under the injected clock: still
    `playing`, cache count ≤ `cacheLimit` (SC-310-06).

## Simulator gates (Claude-owned, after host green)

1. **App-target tests** — XcodeBuildMCP `test_sim` on the whole new/changed classes (never a
   single `@Test` — false green, see memory `xcodebuildmcp-single-test-false-green`).
2. **UI verification** — `SlideshowErrorView` preview renders both message variants (generic
   transient vs. actionable auth copy); accessibility IDs `slideshow.error`/`slideshow.retry`
   unchanged.
3. **Full XCUITest suite** before merge (SwiftUI files touched — repo rule).

## Manual smoke (optional, live server)

With the real frame setup: start the slideshow, kill the Wi-Fi for ~2 min, restore — playback
must resume by itself within ~2 min of restore (SC-310-01 at real-world scale). Then add a
photo to the active album server-side and leave the frame foregrounded for an hour — it must
appear without touching the iPad (SC-310-02).
