# Contract — SlideshowKit Resilience API (310)

The external interface of this feature is `SlideshowKit`'s public API as consumed by the app
target (and, unchanged, by `SlideshowRemoteControlAdapter`). Everything below is additive;
no existing signature changes, no existing caller breaks.

## New protocol: `SlideshowClock`

```swift
public protocol SlideshowClock: Sendable {
    /// Monotonic elapsed time since an arbitrary fixed epoch. Never jumps backwards;
    /// unaffected by wall-clock or time-zone changes.
    var now: Duration { get }

    /// Returns after `duration` has elapsed on this clock. Throws `CancellationError`
    /// when the surrounding task is cancelled.
    func sleep(for duration: Duration) async throws
}

/// Production implementation over ContinuousClock.
public struct ContinuousSlideshowClock: SlideshowClock {
    public init()
}
```

## New types: `RetryPolicy`, `SlideshowFailureReason`

```swift
public enum SlideshowFailureReason: Sendable, Equatable {
    case transient        // network/server hiccup — full backoff curve
    case authentication   // 401/403, expired/repassworded shared link — cap-only retry
}

public struct RetryPolicy {
    public struct Configuration: Sendable, Equatable {
        public var initialDelay: Duration   // default 1 s
        public var factor: Double           // default 2
        public var maxDelay: Duration       // default 300 s
        public var jitter: Double           // default 0.2 (±20 %)
        public static let `default`: Configuration
    }

    public init(configuration: Configuration = .default,
                rng: any RandomNumberGenerator = SystemRandomNumberGenerator())

    /// Classify-then-schedule: increments the attempt counter and returns the jittered
    /// delay for this error (transient: exponential; auth: always maxDelay).
    public mutating func nextDelay(for error: any Error) -> Duration

    /// Back to attempt 0. Called on success and on manual retry.
    public mutating func reset()

    public static func classify(_ error: any Error) -> SlideshowFailureReason
}
```

Contract guarantees (asserted by `RetryPolicyTests`):

- Transient delays follow `initial × factor^(n-1)` capped at `maxDelay`, each within
  ±`jitter` of the nominal value (FR-310-02, SC-310-04).
- Auth delays equal `maxDelay` (± jitter) from the first attempt (FR-310-05).
- `reset()` returns the sequence to `initialDelay` (FR-310-02).
- `classify` maps `ImmichError.unauthorized/.shareLinkExpired/.wrongPassword/.passwordRequired`
  → `.authentication`; every other error (including non-`ImmichError`) → `.transient`.

## New type: `RotationReconciler`

```swift
public enum RotationReconciler {
    public static func reconcile(
        oldAssets: [Asset], newAssets: [Asset],
        playOrder: [Int], cursor: Int,
        order: PlayOrder, currentAssetID: String?,
        rng: inout some RandomNumberGenerator
    ) -> (playOrder: [Int], cursor: Int)
}
```

Guarantees: see data-model.md invariants 1–6 (full permutation, no-op on identical lists,
sequential = identity + anchored cursor, shuffle preserves the current cycle and folds
additions into the unplayed remainder, removed-current lands the cursor before its successor).

## `SlideshowViewModel` — additive API surface

```swift
// init gains two injected seams (defaults keep existing call sites source-compatible):
public init(api: any ImmichAPI, albumID: String, ticker: any SlideshowTicker,
            clock: any SlideshowClock = ContinuousSlideshowClock(),
            retryPolicy: RetryPolicy = RetryPolicy(),
            cache: ImageCache = ..., config: SlideshowConfig = .default,
            settingsStore: any ThemeSettingsStore,
            rng: any RandomNumberGenerator = SystemRandomNumberGenerator())

/// nil while healthy; set when the most recent fetch attempt failed.
public private(set) var failureReason: SlideshowFailureReason?
```

Behavioral contract (asserted by `SlideshowResilienceTests`):

| Trigger | Guarantee |
|---|---|
| Fetch/image failure while an image is on screen | image stays, retries fire on the backoff schedule, no error surface (FR-310-01/03, FR-310-09) |
| Fetch failure with nothing to show | `phase == .failed`, `failureReason` set, auto-retry runs behind the calm state (US1-2) |
| Fake recovers | playback resumes within one current-backoff interval, backoff resets, `failureReason == nil` (SC-310-01) |
| `retry()` (manual) | immediate attempt + backoff reset; works exactly as before from `.failed` (FR-310-04) |
| `refreshInterval` elapses (foreground) | one `assets(albumID:)` call; on-screen photo, ticker deadline, and cycle position untouched (FR-310-06/07) |
| Refresh fails | rotation keeps playing stale; retry loop takes over (FR-310-09) |
| Background (`pause()`) | no retry/refresh timer fires (FR-310-10) |
| Foreground (`resume()`) stale | immediate refresh; pending retry resumes / fires if overdue (FR-310-10, US3) |
| `switchAlbum` / `start()` | all timers rebind to the new source; none leak (FR-310-11) |

## `SlideshowConfig` — one new field

```swift
public var refreshInterval: Duration   // default .seconds(3600), FR-310-06
```

## Unchanged surfaces (compatibility guarantees)

- `SlideshowPhase`: no new cases, no associated values — `SlideshowRemoteControlAdapter`'s
  phase mapping and all `phase == .failed` call sites compile and behave unchanged.
- `ImmichAPI`, `ImmichError`: untouched (classification is SlideshowKit-side).
- `SlideshowTicker`: untouched; the advance timer works exactly as today.
- App-facing UI contract: `SlideshowErrorView` gains an optional failure-reason input; the
  auth variant reads "check your connection settings" style copy (FR-310-05) — accessibility
  identifiers `slideshow.error` / `slideshow.retry` stay stable for the existing UITests.
