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
import ThemeKit
import ThemeKitTestSupport
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
// Sleeper bookkeeping: a playing engine keeps the hourly refresh parked on the
// clock (1 sleeper); failure passages park the backoff retry on top (2). A
// failed-at-launch engine has no refresh yet — only the retry (1).

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
        // Two sleepers: the hourly refresh (parked since start) and the retry.
        api.setPreviewData(Data([1]), for: "image-1")
        api.setPreviewData(Data([2]), for: "image-2")
        api.setPreviewData(Data([3]), for: "image-3")
        await clock.waitUntilSleeperCount(2)
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
        // sit out at least 0.8 × 8 s). Two sleepers: hourly refresh + retry.
        api.setPreviewData(Data([2]), for: "image-2")
        await clock.waitUntilSleeperCount(2)
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

// MARK: - US2: New photos appear without a restart (T013)
//
// A healthy playing engine keeps exactly one sleeper parked on the clock: the
// hourly refresh. Failure passages park a second one (the backoff retry).

@Suite("Resilience US2 — periodic source refresh")
@MainActor
struct PeriodicRefreshTests {
    private func makePlayingModel(
        api: StubImmichAPI,
        ticker: ManualTicker,
        clock: TestClock,
        assets ids: [String],
        store: InMemoryThemeStore? = nil
    ) async -> SlideshowViewModel {
        api.setAssets(ids.map { Asset(id: $0, type: "IMAGE") }, for: "album")
        for id in ids {
            api.setPreviewData(Data(id.utf8), for: id)
        }
        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            settingsStore: store ?? sequentialThemeStore()
        )
        await model.start()
        return model
    }

    // US2-1/3 + FR-310-06/07 + SC-310-05: exactly one background re-fetch per
    // interval; the on-screen photo, the pending tick, and the cursor are
    // untouched by a same-list refresh.
    @Test func hourlyRefreshRefetchesWithoutDisturbingPlayback() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock, assets: ["image-1", "image-2"]
        )
        #expect(model.currentAssetID == "image-1")
        #expect(api.assetsCallCount == 1)

        // Provably parked until the interval elapses…
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3599))
        #expect(clock.sleeperCount == 1)
        #expect(api.assetsCallCount == 1)

        // …exactly one re-fetch at the hour.
        clock.advance(by: .seconds(1))
        await waitUntil(api.assetsCallCount == 2)
        #expect(api.assetsCallCount == 2)

        // FR-310-07: nothing visible moved — same photo, same cycle position,
        // and the auto-advance wait was never re-armed (timer not reset).
        #expect(model.currentAssetID == "image-1")
        #expect(model.phase == .playing)
        #expect(ticker.requestedDurations.count == 1)

        // The rotation still advances normally afterwards.
        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID == "image-2")
        #expect(model.currentAssetID == "image-2")

        // And the next hourly refresh is re-armed.
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3600))
        await waitUntil(api.assetsCallCount == 3)
        #expect(api.assetsCallCount == 3)
    }

    // US2-2 (sequential) + SC-310-02: additions appear at their album position.
    @Test func sequentialAdditionEntersAtItsAlbumPosition() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock, assets: ["image-a", "image-c"]
        )
        #expect(model.currentAssetID == "image-a")

        // image-b lands between a and c server-side.
        api.setAssets([
            Asset(id: "image-a", type: "IMAGE"),
            Asset(id: "image-b", type: "IMAGE"),
            Asset(id: "image-c", type: "IMAGE")
        ], for: "album")
        api.setPreviewData(Data("image-b".utf8), for: "image-b")

        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3600))
        await waitUntil(api.assetsCallCount == 2)
        #expect(model.currentAssetID == "image-a")   // undisturbed

        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID == "image-b")
        #expect(model.currentAssetID == "image-b")
        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID == "image-c")
        #expect(model.currentAssetID == "image-c")
    }

    // US2-2 (shuffle) + SC-310-02: additions join the running cycle — every
    // remaining photo, including the new one, plays exactly once before the wrap.
    @Test func shuffleAdditionJoinsTheCurrentCycle() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let store = InMemoryThemeStore(
            settings: ThemeSettings(order: .shuffle, duration: .seconds(15))
        )
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock,
            assets: ["image-a", "image-b", "image-c"], store: store
        )
        let first = model.currentAssetID
        #expect(first != nil)

        api.setAssets([
            Asset(id: "image-a", type: "IMAGE"),
            Asset(id: "image-b", type: "IMAGE"),
            Asset(id: "image-c", type: "IMAGE"),
            Asset(id: "image-d", type: "IMAGE")
        ], for: "album")
        api.setPreviewData(Data("image-d".utf8), for: "image-d")

        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3600))
        await waitUntil(api.assetsCallCount == 2)
        #expect(model.currentAssetID == first)   // undisturbed

        // The three remaining slots of this cycle show the three photos not
        // yet seen — image-d among them, nothing twice (FR-300-05 holds).
        var seen: [String] = [first!]
        for _ in 0..<3 {
            let before = model.currentAssetID
            await ticker.waitUntilWaiting()
            ticker.tick()
            await waitUntil(model.currentAssetID != before)
            seen.append(model.currentAssetID!)
        }
        #expect(seen.count == 4)
        #expect(Set(seen) == Set(["image-a", "image-b", "image-c", "image-d"]))
    }

    // US2-5 first half: a removed asset never shows again.
    @Test func removedAssetLeavesTheRotation() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock,
            assets: ["image-a", "image-b", "image-c"]
        )

        api.setAssets([
            Asset(id: "image-a", type: "IMAGE"),
            Asset(id: "image-c", type: "IMAGE")
        ], for: "album")

        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3600))
        await waitUntil(api.assetsCallCount == 2)

        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID == "image-c")
        #expect(model.currentAssetID == "image-c")   // b was skipped entirely
    }

    // US2-5 second half + SC-310-03: the removed *current* photo finishes its
    // slot on screen and is skipped afterwards — no crash, no blank.
    @Test func removedCurrentPhotoFinishesItsSlotThenIsSkipped() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock,
            assets: ["image-a", "image-b", "image-c"]
        )
        #expect(model.currentAssetID == "image-a")

        api.setAssets([
            Asset(id: "image-b", type: "IMAGE"),
            Asset(id: "image-c", type: "IMAGE")
        ], for: "album")

        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3600))
        await waitUntil(api.assetsCallCount == 2)

        // Still visible after the refresh that dropped it…
        #expect(model.currentAssetID == "image-a")
        #expect(model.currentImageData == Data("image-a".utf8))
        #expect(model.phase == .playing)

        // …and the next advance moves to its successor.
        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID == "image-b")
        #expect(model.currentAssetID == "image-b")
    }

    // US2-4 + FR-310-09: a failed refresh never replaces a working slideshow —
    // stale keeps playing and the backoff retry takes over; its success is the
    // refresh and re-arms the hourly cadence.
    @Test func refreshFailureKeepsStalePlayingAndHandsToRetry() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock, assets: ["image-1", "image-2"]
        )

        api.setAssetsError(ImmichError.unreachable, for: "album")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3600))
        await waitUntil(api.assetsCallCount == 2)

        // Stale-but-working: no error surface, playback continues.
        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-1")
        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID == "image-2")
        #expect(model.currentAssetID == "image-2")

        // The retry recovers the source within one backoff interval…
        api.setAssets([
            Asset(id: "image-1", type: "IMAGE"),
            Asset(id: "image-2", type: "IMAGE"),
            Asset(id: "image-3", type: "IMAGE")
        ], for: "album")
        api.setPreviewData(Data("image-3".utf8), for: "image-3")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .milliseconds(1200))
        // Wait on the MainActor-visible outcome, not the stub's call counter —
        // the counter bumps inside the fetch, before clearFailure() runs.
        await waitUntil(api.assetsCallCount == 3 && model.failureReason == nil)
        #expect(api.assetsCallCount == 3)
        #expect(model.failureReason == nil)

        // …its success counts as the refresh: the next fetch is an hour out,
        // and the recovered list is live (image-3 joined the rotation).
        #expect(model.currentAssetID == "image-2")   // still undisturbed
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3599))
        #expect(api.assetsCallCount == 3)
        clock.advance(by: .seconds(1))
        await waitUntil(api.assetsCallCount == 4)
        #expect(api.assetsCallCount == 4)

        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID == "image-3")
        #expect(model.currentAssetID == "image-3")
    }

    // US3-2 + FR-310-10: while backgrounded, no retry or refresh timer fires —
    // however much time passes.
    @Test func backgroundStopsAllTimers() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock, assets: ["image-1"]
        )
        await clock.waitUntilSleeperCount(1)   // the hourly refresh is parked

        model.pause()
        #expect(clock.sleeperCount == 0)

        clock.advance(by: .seconds(5 * 3600))
        await waitUntil(false)   // settle the executor
        #expect(api.assetsCallCount == 1)
    }

    // US3-1: returning to the foreground stale (last refresh older than the
    // interval) triggers an immediate refresh — no waiting out a fresh hour.
    @Test func staleForegroundReturnRefreshesImmediately() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock, assets: ["image-1"]
        )

        model.pause()
        clock.advance(by: .seconds(2 * 3600))   // asleep for two hours

        model.resume()
        await waitUntil(api.assetsCallCount == 2)
        #expect(api.assetsCallCount == 2)
    }

    // US3-1 inverse: a short background trip is not stale — the refresh keeps
    // its original due time instead of firing on every foreground return.
    @Test func freshForegroundReturnKeepsTheOriginalSchedule() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock, assets: ["image-1"]
        )

        model.pause()
        clock.advance(by: .seconds(600))   // 10 minutes — well inside the hour

        model.resume()
        await clock.waitUntilSleeperCount(1)
        await waitUntil(false)   // settle: provably no immediate fetch
        #expect(api.assetsCallCount == 1)

        // The original cadence holds: due 50 minutes later, not a fresh hour.
        clock.advance(by: .seconds(3000))
        await waitUntil(api.assetsCallCount == 2)
        #expect(api.assetsCallCount == 2)
    }

    // US3-3: a retry that was pending at background time resumes on foreground
    // return — immediately when overdue.
    @Test func overduePendingRetryFiresImmediatelyOnForegroundReturn() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        api.setAssetsError(ImmichError.unreachable, for: "album")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        await clock.waitUntilSleeperCount(1)   // retry parked

        model.pause()
        #expect(clock.sleeperCount == 0)

        // The server comes back while the app sleeps past the retry's due time;
        // nothing fires in the background.
        api.setAssets([Asset(id: "image-1", type: "IMAGE")], for: "album")
        api.setPreviewData(Data([1]), for: "image-1")
        clock.advance(by: .seconds(10))
        await waitUntil(false)   // settle
        #expect(model.phase == .failed)

        model.resume()
        await waitUntil(model.phase == .playing)
        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-1")
    }

    // US3-3 second half: a retry that is not yet due resumes with its remaining
    // delay instead of firing early.
    @Test func pendingRetryResumesWithItsRemainingDelay() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        api.setAssetsError(ImmichError.unreachable, for: "album")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        let calls0 = api.assetsCallCount
        await clock.waitUntilSleeperCount(1)

        model.pause()
        model.resume()   // no time passed: full delay remains

        await clock.waitUntilSleeperCount(1)
        await waitUntil(false)   // settle: provably not fired early
        #expect(api.assetsCallCount == calls0)

        clock.advance(by: .milliseconds(1200))
        await waitUntil(api.assetsCallCount > calls0)
        #expect(api.assetsCallCount == calls0 + 1)
    }

    // Research R7: the background re-arm is independent of the user-intent
    // pause — a paused frame still refreshes its list; only the auto-advance
    // stays stopped.
    @Test func userPausedFrameStillRefreshesOnForegroundReturn() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock, assets: ["image-1", "image-2"]
        )
        await ticker.waitUntilWaiting()   // the advance loop has parked once

        model.togglePause()   // user-intent pause (chrome button)
        #expect(model.isPaused)

        model.pause()
        clock.advance(by: .seconds(2 * 3600))
        model.resume()

        await waitUntil(api.assetsCallCount == 2)
        #expect(api.assetsCallCount == 2)

        // The auto-advance stayed stopped: no new tick wait was armed and the
        // photo did not move.
        #expect(ticker.requestedDurations.count == 1)
        #expect(model.currentAssetID == "image-1")
        #expect(model.isPaused)
    }

    // FR-310-11 (T017): a source switch while a retry is pending rebinds every
    // timer — nothing ever fires against the old source, and the schedule
    // belongs to the new one.
    @Test func sourceSwitchMidRetryRebindsAllTimers() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        api.setAssetsError(ImmichError.unreachable, for: "album-a")
        api.setAssets([Asset(id: "image-b", type: "IMAGE")], for: "album-b")
        api.setPreviewData(Data([1]), for: "image-b")

        let model = SlideshowViewModel(
            api: api, albumID: "album-a", ticker: ticker, clock: clock,
            settingsStore: sequentialThemeStore()
        )
        await model.start()
        #expect(model.phase == .failed)
        await clock.waitUntilSleeperCount(1)   // retry against album-a parked

        await model.switchAlbum("album-b")
        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-b")
        #expect(model.failureReason == nil)

        // Exact call accounting across a window covering both the old retry's
        // due time (~1 s) and the new refresh interval: exactly ONE further
        // fetch (album-b's hourly refresh) may happen. A leaked album-a retry
        // would add a second.
        let callsAfterSwitch = api.assetsCallCount
        await clock.waitUntilSleeperCount(1)   // album-b's refresh parked
        clock.advance(by: .seconds(3600))
        await waitUntil(api.assetsCallCount == callsAfterSwitch + 1)
        await waitUntil(false)   // settle any strays
        #expect(api.assetsCallCount == callsAfterSwitch + 1)
        #expect(model.phase == .playing)
    }

    // SC-310-06 (T018): a long simulated run of network flaps, refreshes with
    // list churn, and advances ends with the show still advancing and the
    // image cache inside its bound.
    @Test func longRunSoakSurvivesFlapsAndChurn() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let cache = ImageCache(limit: 3)
        let config = SlideshowConfig(prefetchDepth: 1, cacheLimit: 3)
        let allIDs = (1...6).map { "image-\($0)" }
        for id in allIDs {
            api.setPreviewData(Data(id.utf8), for: id)
        }
        api.setAssets(allIDs.map { Asset(id: $0, type: "IMAGE") }, for: "album")

        let model = SlideshowViewModel(
            api: api, albumID: "album", ticker: ticker, clock: clock,
            cache: cache, config: config, settingsStore: sequentialThemeStore()
        )
        await model.start()
        #expect(model.phase == .playing)

        for round in 0..<12 {
            // Advance a couple of slides.
            for _ in 0..<2 {
                let before = model.currentAssetID
                await ticker.waitUntilWaiting()
                ticker.tick()
                await waitUntil(model.currentAssetID != before)
            }

            switch round % 3 {
            case 0:
                // Network flap: the hourly refresh fails, the retry recovers.
                api.setAssetsError(ImmichError.unreachable, for: "album")
                let calls = api.assetsCallCount
                clock.advance(by: .seconds(3600))
                await waitUntil(api.assetsCallCount == calls + 1)
                api.setAssets(allIDs.map { Asset(id: $0, type: "IMAGE") }, for: "album")
                await clock.waitUntilSleeperCount(1)
                clock.advance(by: .milliseconds(1200))
                await waitUntil(api.assetsCallCount == calls + 2 && model.failureReason == nil)
                #expect(model.failureReason == nil)
            case 1:
                // Churn: drop one asset, keep playing on the fresh list.
                let keep = allIDs.filter { $0 != model.currentAssetID }.dropFirst().map { $0 }
                api.setAssets(keep.map { Asset(id: $0, type: "IMAGE") }, for: "album")
                let calls = api.assetsCallCount
                clock.advance(by: .seconds(3600))
                await waitUntil(api.assetsCallCount == calls + 1)
            default:
                // Full list returns.
                api.setAssets(allIDs.map { Asset(id: $0, type: "IMAGE") }, for: "album")
                let calls = api.assetsCallCount
                clock.advance(by: .seconds(3600))
                await waitUntil(api.assetsCallCount == calls + 1)
            }

            #expect(model.phase == .playing, "round \(round)")
            #expect(cache.count <= 3, "round \(round)")
        }

        // Still advancing at the end.
        let before = model.currentAssetID
        await ticker.waitUntilWaiting()
        ticker.tick()
        await waitUntil(model.currentAssetID != before)
        #expect(model.currentAssetID != before)
        #expect(cache.count <= 3)
    }

    // US2-6: the source emptied server-side — the next refresh moves to the
    // calm empty state; a later refresh with photos recovers playback.
    @Test func refreshToEmptySourceMovesToEmptyStateAndBack() async {
        let api = StubImmichAPI()
        let ticker = ManualTicker()
        let clock = TestClock()
        let model = await makePlayingModel(
            api: api, ticker: ticker, clock: clock, assets: ["image-1"]
        )

        api.setAssets([], for: "album")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3600))
        await waitUntil(model.phase == .empty)
        #expect(model.phase == .empty)
        #expect(model.currentAssetID == nil)

        // Photos return: the refresh keeps running in the empty state and
        // brings the show back without a restart.
        api.setAssets([Asset(id: "image-9", type: "IMAGE")], for: "album")
        api.setPreviewData(Data([9]), for: "image-9")
        await clock.waitUntilSleeperCount(1)
        clock.advance(by: .seconds(3600))
        await waitUntil(model.phase == .playing)
        #expect(model.phase == .playing)
        #expect(model.currentAssetID == "image-9")
    }
}
