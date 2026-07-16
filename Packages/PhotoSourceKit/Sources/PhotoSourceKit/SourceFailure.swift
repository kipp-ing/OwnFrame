//
//  SourceFailure.swift
//  PhotoSourceKit
//
//  900 — the closed, backend-neutral error taxonomy the engine reacts to (R3). Each
//  backend maps its own errors onto these four arms; `RetryPolicy.classify(SourceFailure)`
//  drives backoff (`.transient`), the calm-actionable state (`.authentication`), the
//  vanish state (`.notFound`, FR-900-16), and the manual-recovery state (`.permanent`).
//

import Foundation

/// The four ways a source can fail to serve the engine. Closed on purpose so the engine
/// can switch exhaustively — a new failure mode is a deliberate taxonomy change, not a
/// silent open case.
public enum SourceFailure: Error, Sendable {
    /// Retry with backoff (FR-310): network drops, 5xx, timeouts, iCloud throttling.
    case transient(underlying: any Error)
    /// Calm actionable state + slow retry: 401/403, denied/downgraded authorization.
    case authentication
    /// Vanish state (FR-900-16): the collection is gone (album deleted / unshared /
    /// upgraded to the new iCloud format). Other sources are untouched.
    case notFound
    /// Calm error state, manual recovery: decode/contract errors.
    case permanent(underlying: any Error)
}
