//
//  SlideshowClock.swift
//  SlideshowKit
//
//  310 — monotonic time seam for retry backoff and the periodic source refresh.
//  Same seam style as SlideshowTicker (Constitution II): the engine schedules
//  against this protocol, production sleeps for real, tests advance a fake
//  deterministically (FR-310-12). `now` is monotonic (never wall-clock), so
//  staleness math survives clock changes and time-zone jumps.
//

import Foundation

public protocol SlideshowClock: Sendable {
    /// Monotonic elapsed time since an arbitrary fixed epoch. Never jumps
    /// backwards; unaffected by wall-clock or time-zone changes.
    var now: Duration { get }

    /// Returns after `duration` has elapsed on this clock. Throws
    /// `CancellationError` when the surrounding task is cancelled.
    func sleep(for duration: Duration) async throws
}

/// Production clock over `ContinuousClock` — monotonic, suspends while the
/// device sleeps (which is fine: retry/refresh are foreground-only anyway,
/// FR-310-10).
public struct ContinuousSlideshowClock: SlideshowClock {
    private let clock = ContinuousClock()
    private let epoch: ContinuousClock.Instant

    public init() {
        epoch = clock.now
    }

    public var now: Duration {
        epoch.duration(to: clock.now)
    }

    public func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}
