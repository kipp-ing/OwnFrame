//
//  RetryPolicyTests.swift
//  SlideshowKitTests
//
//  310, T005 — the backoff math and the transient-vs-auth classification
//  (FR-310-02, FR-310-05, SC-310-04). Deterministic via the seeded RNG; every
//  jittered delay must fall inside [1 - jitter, 1 + jitter] × nominal.
//

import Foundation
import Testing
import ImmichClient
@testable import SlideshowKit

private struct DummyError: Error {}

private func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

@Suite("RetryPolicy")
struct RetryPolicyTests {
    // FR-310-02: 1 s initial, ×2 per attempt, capped at 300 s, ±20 % jitter.
    @Test func transientDelaysFollowTheDoublingCurveWithinJitterBounds() {
        var policy = RetryPolicy(rng: SeededRandomNumberGenerator(seed: 7))

        for attempt in 1...10 {
            let nominal = min(pow(2, Double(attempt - 1)), 300)
            let delay = seconds(policy.nextDelay(for: ImmichError.unreachable))
            #expect(delay >= 0.8 * nominal - 1e-9, "attempt \(attempt) below jitter floor")
            #expect(delay <= 1.2 * nominal + 1e-9, "attempt \(attempt) above jitter ceiling")
        }
    }

    // FR-310-02: the curve saturates at the cap and stays there — deep attempt
    // counts never overflow past it.
    @Test func delaysSaturateAtTheCap() {
        var policy = RetryPolicy(rng: SeededRandomNumberGenerator(seed: 11))

        for _ in 1...30 {
            _ = policy.nextDelay(for: ImmichError.unreachable)
        }
        let deep = seconds(policy.nextDelay(for: ImmichError.unreachable))
        #expect(deep >= 0.8 * 300 - 1e-9)
        #expect(deep <= 1.2 * 300 + 1e-9)
    }

    // FR-310-02: reset returns the sequence to the initial delay.
    @Test func resetReturnsToTheInitialDelay() {
        var policy = RetryPolicy(rng: SeededRandomNumberGenerator(seed: 3))
        for _ in 1...5 {
            _ = policy.nextDelay(for: ImmichError.unreachable)
        }

        policy.reset()
        let delay = seconds(policy.nextDelay(for: ImmichError.unreachable))
        #expect(delay >= 0.8 - 1e-9)
        #expect(delay <= 1.2 + 1e-9)
    }

    // FR-310-05: auth failures never walk the ramp — cap-only from the first attempt.
    @Test(arguments: [
        ImmichError.unauthorized,
        ImmichError.shareLinkExpired,
        ImmichError.wrongPassword,
        ImmichError.passwordRequired
    ])
    func authFailuresRetryAtTheCapFromTheFirstAttempt(error: ImmichError) {
        var policy = RetryPolicy(rng: SeededRandomNumberGenerator(seed: 5))

        let first = seconds(policy.nextDelay(for: error))
        #expect(first >= 0.8 * 300 - 1e-9)
        #expect(first <= 1.2 * 300 + 1e-9)
    }

    // Retry-storm edge case: jitter is actually applied — repeated same-nominal
    // delays are not all identical.
    @Test func jitterVariesTheDelays() {
        var policy = RetryPolicy(rng: SeededRandomNumberGenerator(seed: 42))

        let delays = (1...8).map { _ in seconds(policy.nextDelay(for: ImmichError.unauthorized)) }
        #expect(Set(delays).count > 1)
    }

    // Custom configuration is honored (engine tests tighten these in places).
    @Test func customConfigurationDrivesTheBounds() {
        let config = RetryPolicy.Configuration(
            initialDelay: .seconds(2), factor: 3, maxDelay: .seconds(18), jitter: 0.1
        )
        var policy = RetryPolicy(configuration: config, rng: SeededRandomNumberGenerator(seed: 9))

        let nominals: [Double] = [2, 6, 18, 18]
        for nominal in nominals {
            let delay = seconds(policy.nextDelay(for: ImmichError.unreachable))
            #expect(delay >= 0.9 * nominal - 1e-9)
            #expect(delay <= 1.1 * nominal + 1e-9)
        }
    }

    // FR-310-05 classification: the four auth conditions vs everything else.
    @Test func classifyMapsAuthConditionsToAuthentication() {
        #expect(RetryPolicy.classify(ImmichError.unauthorized) == .authentication)
        #expect(RetryPolicy.classify(ImmichError.shareLinkExpired) == .authentication)
        #expect(RetryPolicy.classify(ImmichError.wrongPassword) == .authentication)
        #expect(RetryPolicy.classify(ImmichError.passwordRequired) == .authentication)
    }

    @Test func classifyMapsEverythingElseToTransient() {
        #expect(RetryPolicy.classify(ImmichError.unreachable) == .transient)
        #expect(RetryPolicy.classify(ImmichError.invalidResponse) == .transient)
        #expect(RetryPolicy.classify(ImmichError.invalidShareLink) == .transient)
        #expect(RetryPolicy.classify(DummyError()) == .transient)
        #expect(RetryPolicy.classify(CancellationError()) == .transient)
    }
}
