//
//  SlideshowResilienceTests.swift
//  SlideshowKitTests
//
//  310 — auto-retry with backoff + periodic source refresh. Everything here runs
//  against the injected TestClock (FR-310-12): no real timers, no real waiting.
//  The TestClock sanity suite at the top proves the fake itself is deterministic
//  before any engine behavior is asserted against it.
//

import Foundation
import ImmichClient
import Testing
@testable import SlideshowKit

// MARK: - TestClock sanity (T002)

@Suite("TestClock")
struct TestClockTests {
    @Test func nowAdvancesByExactlyTheAdvancedAmount() {
        let clock = TestClock()
        #expect(clock.now == .zero)

        clock.advance(by: .seconds(90))
        #expect(clock.now == .seconds(90))

        clock.advance(by: .milliseconds(500))
        #expect(clock.now == .seconds(90) + .milliseconds(500))
    }

    @Test func sleepCompletesOnlyWhenAdvancedPastItsDeadline() async throws {
        let clock = TestClock()
        let sleeper = Task {
            try await clock.sleep(for: .seconds(10))
            return true
        }

        await clock.waitUntilSleeperCount(1)

        // Not due yet: the continuation is provably still parked (synchronous
        // state under the clock's lock — no race in this assertion).
        clock.advance(by: .seconds(5))
        #expect(clock.sleeperCount == 1)

        // Crossing the deadline releases it.
        clock.advance(by: .seconds(5))
        #expect(try await sleeper.value)
        #expect(clock.sleeperCount == 0)
    }

    @Test func advanceReleasesOnlyTheSleepersThatAreDue() async throws {
        let clock = TestClock()
        let early = Task {
            try await clock.sleep(for: .seconds(5))
            return "early"
        }
        await clock.waitUntilSleeperCount(1)
        let late = Task {
            try await clock.sleep(for: .seconds(10))
            return "late"
        }
        await clock.waitUntilSleeperCount(2)

        clock.advance(by: .seconds(7))
        #expect(try await early.value == "early")
        #expect(clock.sleeperCount == 1)

        clock.advance(by: .seconds(3))
        #expect(try await late.value == "late")
        #expect(clock.sleeperCount == 0)
    }

    @Test func zeroOrNegativeSleepReturnsImmediately() async throws {
        let clock = TestClock()
        try await clock.sleep(for: .zero)
        try await clock.sleep(for: .seconds(-1))
        #expect(clock.sleeperCount == 0)
    }

    @Test func cancellationThrowsCancellationErrorAndRemovesTheSleeper() async {
        let clock = TestClock()
        let sleeper = Task {
            try await clock.sleep(for: .seconds(60))
        }

        await clock.waitUntilSleeperCount(1)
        sleeper.cancel()

        await #expect(throws: CancellationError.self) {
            try await sleeper.value
        }
        #expect(clock.sleeperCount == 0)
    }

    @Test func sleepOnAnAlreadyCancelledTaskThrowsWithoutParking() async {
        let clock = TestClock()
        let sleeper = Task {
            try await clock.sleep(for: .seconds(60))
        }
        sleeper.cancel()

        await #expect(throws: CancellationError.self) {
            try await sleeper.value
        }
        #expect(clock.sleeperCount == 0)
    }
}

// MARK: - Shared helpers

/// Bounded yield loop (same pattern as SlideshowViewModelTests): lets detached
/// work hop actors without real time. Passing `false` just settles the executor.
@MainActor
private func waitUntil(_ condition: @autoclosure () -> Bool) async {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
}

// MARK: - US1: Unattended recovery from network loss (T007)
//
// Timing assertions are bounds-based: every backoff delay lies inside
// [0.8, 1.2] × nominal (default jitter ±20 %), so "advance to just below the
// floor ⇒ provably still parked" and "advance to the ceiling ⇒ provably fired"
// are deterministic without a seeded RNG at the engine level.
//
// TODO(T014): once the hourly refresh loop lands, a *playing* engine keeps one
// extra sleeper parked on the clock — revisit every waitUntilSleeperCount in
// playing-state passages below (failed-at-launch passages stay at 1).

@Suite("Resilience US1 — auto-retry with backoff")
@MainActor
struct AutoRetryTests {
    // US1-2 + SC-310-01: dead server at launch → calm failed state, auto-retry
    // behind it, playback starts by itself when the server returns; success
    // clears the failure reason.
    @Test func deadServerAtLaunchShowsCalmStateAndAutoRecovers() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        api.setAssetsError(ImmichError.unreachable, for: "album")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            settingsStore: sequentialThemeStore()
        )
        await model.start()

        #expect(model.phase == .failed)
        #expect(model.failureReason == .transient)

        // Server comes back before the first retry fires.
        api.setAssets([Asset(id: "image-1", type: "IMAGE")], for: "album")
        api.setPreviewData(Data([1]), for: "image-1")

        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(1200))   // ≥ 1.2 × 1 s ⇒ attempt provably due
        await waitUntil(model.phase == .playing)

        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-1")
        #expect(model.failureReason == nil)
    }

    // FR-310-02 at engine level: the retry provably waits out the backoff delay.
    @Test func retryWaitsOutTheBackoffDelayBeforeRefetching() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        api.setAssetsError(ImmichError.unreachable, for: "album")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        let callsAfterStart = api.assetsCallCount

        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(790))    // < 0.8 × 1 s ⇒ provably not due yet
        #expect(clock.sleeperCount == 1)
        #expect(api.assetsCallCount == callsAfterStart)

        clock.advance(by: .milliseconds(410))    // total 1.2 s ⇒ provably due
        await waitUntil(api.assetsCallCount > callsAfterStart)
        #expect(api.assetsCallCount == callsAfterStart + 1)
    }

    // US1-1/3 + FR-310-03: total image-load failure mid-playback keeps the
    // current photo on screen (no error surface), parks the pointless
    // auto-advance, and recovers to the *next* photo within one backoff
    // interval of the images returning.
    @Test func imageExhaustionKeepsCurrentImageAndAutoRecovers() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let cache = ImageCache(limit: 2)
        let config = SlideshowConfig(prefetchDepth: 1, cacheLimit: 2)
        api.setAssets([
            Asset(id: "image-1", type: "IMAGE"),
            Asset(id: "image-2", type: "IMAGE"),
            Asset(id: "image-3", type: "IMAGE")
        ], for: "album")
        api.setPreviewData(Data([1]), for: "image-1")
        api.setPreviewData(Data([2]), for: "image-2")
        api.setPreviewData(Data([3]), for: "image-3")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            cache: cache, config: config, settingsStore: sequentialThemeStore()
        )
        await model.start()
        await waitUntil(cache.contains("image-2"))
        // Evict everything, then let every fetch fail: nothing in the ring loads.
        cache.store(Data([9]), for: "unrelated-1")
        cache.store(Data([10]), for: "unrelated-2")
        api.setPreviewError(ImmichError.unreachable, for: "image-1")
        api.setPreviewError(ImmichError.unreachable, for: "image-2")
        api.setPreviewError(ImmichError.unreachable, for: "image-3")

        await model.advance()

        // FR-310-03: current image survives, no error surface replaces it.
        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-1")
        #expect(model.currentImageData == Data([1]))
        #expect(model.failureReason == .transient)

        // The auto-advance is parked: a stray tick moves nothing.
        ticker.tick()
        await waitUntil(false)   // settle the executor
        #expect(model.currentAssetID == "image-1")

        // Images return; one backoff interval later the show moves on by itself.
        api.setPreviewData(Data([1]), for: "image-1")
        api.setPreviewData(Data([2]), for: "image-2")
        api.setPreviewData(Data([3]), for: "image-3")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(1200))
        await waitUntil(model.currentAssetID == "image-2")

        #expect(model.currentAssetID == "image-2")
        #expect(model.failureReason == nil)

        // And the ticker is re-armed: the next tick advances normally again.
        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID == "image-3")
        #expect(model.currentAssetID == "image-3")
    }

    // US1-3/4: intervals grow while failing, and any success resets the curve —
    // the second breakage (image exhaustion, which does not pass through
    // start()) must begin retrying at ~1 s again, not at attempt 4's ≥ 5.1 s.
    @Test func recoveryResetsTheBackoff() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let cache = ImageCache(limit: 2)
        let config = SlideshowConfig(prefetchDepth: 1, cacheLimit: 2)
        api.setAssetsError(ImmichError.unreachable, for: "album")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            cache: cache, config: config, settingsStore: sequentialThemeStore()
        )
        await model.start()

        // Attempts 1 and 2 fail on the growing curve.
        await clock.waitUntilSleeperCount(1)
        let calls0 = api.assetsCallCount
        clock.advance(by: .milliseconds(1200))
        await waitUntil(api.assetsCallCount == calls0 + 1)
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(2400))
        await waitUntil(api.assetsCallCount == calls0 + 2)

        // Attempt 3 succeeds — the reset moment.
        api.setAssets([
            Asset(id: "image-1", type: "IMAGE"),
            Asset(id: "image-2", type: "IMAGE"),
            Asset(id: "image-3", type: "IMAGE")
        ], for: "album")
        api.setPreviewData(Data([1]), for: "image-1")
        api.setPreviewData(Data([2]), for: "image-2")
        api.setPreviewData(Data([3]), for: "image-3")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(4800))
        await waitUntil(model.phase == .playing)
        #expect(model.phase == .playing)

        // Second breakage without start(): total image failure on the next advance.
        await waitUntil(cache.contains("image-2"))
        cache.store(Data([9]), for: "unrelated-1")
        cache.store(Data([10]), for: "unrelated-2")
        api.setPreviewError(ImmichError.unreachable, for: "image-1")
        api.setPreviewError(ImmichError.unreachable, for: "image-2")
        api.setPreviewError(ImmichError.unreachable, for: "image-3")
        await model.advance()
        #expect(model.failureReason == .transient)

        // Reset curve: the retry fires within 1.2 s (un-reset attempt 4 would
        // sit out at least 0.8 × 8 s).
        api.setPreviewData(Data([2]), for: "image-2")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(1200))
        await waitUntil(model.currentAssetID == "image-2")
        #expect(model.currentAssetID == "image-2")
    }

    // US1-5 + FR-310-04: manual retry fires immediately (no clock movement) and
    // resets the backoff for the next automatic attempt.
    @Test func manualRetryFiresImmediatelyAndResetsBackoff() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        api.setAssetsError(ImmichError.unreachable, for: "album")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            settingsStore: sequentialThemeStore()
        )
        await model.start()

        // Let attempt 1 fail so attempt 2 (nominal 2 s) is pending.
        await clock.waitUntilSleeperCount(1)
        let calls0 = api.assetsCallCount
        clock.advance(by: .milliseconds(1200))
        await waitUntil(api.assetsCallCount == calls0 + 1)
        await clock.waitUntilSleeperCount(1)

        // Manual retry against the still-dead server: immediate attempt.
        await model.retry()
        #expect(api.assetsCallCount == calls0 + 2)

        // Backoff was reset: the next automatic attempt is ~1 s out, not ~3.2 s.
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(1200))
        await waitUntil(api.assetsCallCount == calls0 + 3)
        #expect(api.assetsCallCount == calls0 + 3)
    }

    // US1-6 + FR-310-05: auth failures name the problem and retry at the cap
    // only — no hot loop against a 401, but recovery still happens eventually.
    @Test func authFailureSurfacesActionableReasonAndRetriesAtCapOnly() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        api.setAssetsError(ImmichError.unauthorized, for: "album")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            settingsStore: sequentialThemeStore()
        )
        await model.start()

        #expect(model.phase == .failed)
        #expect(model.failureReason == .authentication)

        // Cap-only: provably parked through 239 s (< 0.8 × 300 s)…
        await clock.waitUntilSleeperCount(1)
        let calls0 = api.assetsCallCount
        clock.advance(by: .seconds(239))
        #expect(clock.sleeperCount == 1)
        #expect(api.assetsCallCount == calls0)

        // …and provably fired by 360 s (1.2 × 300 s). Key was fixed server-side.
        api.setAssets([Asset(id: "image-1", type: "IMAGE")], for: "album")
        api.setPreviewData(Data([1]), for: "image-1")
        clock.advance(by: .seconds(121))
        await waitUntil(model.phase == .playing)
        #expect(model.phase == .playing)
        #expect(model.failureReason == nil)
    }
}
