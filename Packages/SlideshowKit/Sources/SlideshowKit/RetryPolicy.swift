//
//  RetryPolicy.swift
//  SlideshowKit
//
//  310 — backoff math for the engine's auto-retry (FR-310-01/02) plus the
//  transient-vs-auth classification over ImmichClient's error taxonomy
//  (FR-310-05). Policy lives here, not in ImmichClient: the client reports what
//  happened, the engine decides how to react (research R2). Auth failures skip
//  the ramp and retry at the cap only — no hot loop against a 401, but the
//  server may also be misconfigured temporarily, so retrying never stops.
//

import Foundation
import ImmichClient

/// Why the most recent fetch failed — drives the calm error message variant
/// (FR-310-05) and the backoff mode.
public enum SlideshowFailureReason: Sendable, Equatable {
    /// Network/server hiccup — full exponential backoff curve.
    case transient
    /// 401/403, expired or re-passworded shared link — cap-only retry and an
    /// actionable message ("check your connection settings").
    case authentication
    /// Server older than the supported Immich major version (130, FR-130-06).
    /// Terminal: the app speaks the v3 API only and cannot operate against it, so the engine
    /// surfaces the "needs Immich v3+" notice and does NOT arm the backoff loop.
    case unsupportedServer

    /// Terminal reasons stop the auto-retry loop entirely — no backoff, not even cap-retry.
    public var isTerminal: Bool { self == .unsupportedServer }
}

/// Backoff parameters and attempt state. A plain value owned by the engine
/// (single @MainActor owner); jitter comes from an injected RNG so tests are
/// deterministic (SC-310-04).
public struct RetryPolicy {
    public struct Configuration: Sendable, Equatable {
        public var initialDelay: Duration
        public var factor: Double
        public var maxDelay: Duration
        public var jitter: Double

        public init(initialDelay: Duration, factor: Double, maxDelay: Duration, jitter: Double) {
            precondition(initialDelay > .zero, "initialDelay must be > 0")
            precondition(factor >= 1, "factor must be >= 1")
            precondition(maxDelay >= initialDelay, "maxDelay must be >= initialDelay")
            precondition(jitter >= 0 && jitter < 1, "jitter must be in [0, 1)")
            self.initialDelay = initialDelay
            self.factor = factor
            self.maxDelay = maxDelay
            self.jitter = jitter
        }

        /// FR-310-02: ~1 s initial, doubling, 5-minute cap, ±20 % jitter.
        public static let `default` = Configuration(
            initialDelay: .seconds(1), factor: 2, maxDelay: .seconds(300), jitter: 0.2
        )
    }

    private let configuration: Configuration
    private var rng: AnyRandomNumberGenerator
    private var attempt = 0

    public init(
        configuration: Configuration = .default,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.configuration = configuration
        self.rng = AnyRandomNumberGenerator(rng)
    }

    /// Increments the attempt counter and returns the jittered delay for this
    /// error: transient walks the exponential curve, auth is always the cap.
    public mutating func nextDelay(for error: any Error) -> Duration {
        attempt += 1

        let maxSeconds = Self.seconds(configuration.maxDelay)
        let nominal: Double
        switch Self.classify(error) {
        case .authentication, .unsupportedServer:
            // Terminal reasons are not scheduled by the engine; cap defensively if ever asked.
            nominal = maxSeconds
        case .transient:
            let initial = Self.seconds(configuration.initialDelay)
            // Clamp the exponent so factor^n never overflows for long outages.
            let exponent = min(Double(attempt - 1), 64)
            nominal = min(initial * pow(configuration.factor, exponent), maxSeconds)
        }

        let jitterFactor = Double.random(
            in: (1 - configuration.jitter)...(1 + configuration.jitter), using: &rng
        )
        return .seconds(nominal * jitterFactor)
    }

    /// Back to attempt 0 — called on any successful fetch and on manual retry
    /// (FR-310-02/04).
    public mutating func reset() {
        attempt = 0
    }

    /// FR-310-05: the four unambiguous auth conditions; everything else —
    /// including non-ImmichError transport surprises — is worth a normal retry.
    public static func classify(_ error: any Error) -> SlideshowFailureReason {
        // serverTooOld carries an associated value, so match it before the no-payload cases.
        if let immich = error as? ImmichError, case .serverTooOld = immich {
            return .unsupportedServer
        }
        switch error {
        case ImmichError.unauthorized, ImmichError.shareLinkExpired,
             ImmichError.wrongPassword, ImmichError.passwordRequired:
            return .authentication
        default:
            return .transient
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// Type-erased RNG so the policy can store an injected generator and still pass
/// it `inout` to `Double.random(in:using:)` — same pattern as the engine's
/// shuffle RNG.
private struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: any RandomNumberGenerator) {
        self.base = base
    }

    mutating func next() -> UInt64 {
        base.next()
    }
}
