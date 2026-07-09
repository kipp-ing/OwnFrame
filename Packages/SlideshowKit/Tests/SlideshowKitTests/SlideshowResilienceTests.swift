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
