import Foundation

/// Secret sync (topic 1000, FR-1000-06/12). The iPad publishes `SyncedSecret` into CloudKit
/// encrypted fields; the Apple TV fetches once and writes each secret into its local keychain.
public protocol SecretSyncStore: Sendable {
    /// iPad -> CloudKit `encryptedValues`. Idempotent; overwrites the single secret record.
    func publish(_ secret: SyncedSecret) async throws
    /// tvOS <- CloudKit. `nil` when no record exists yet.
    func fetch() async throws -> SyncedSecret?
}

/// Failure surface for `SecretSyncStore`. The consumer degrades silently to manual entry on
/// `iCloudUnavailable` (US2-3/4).
public enum SecretSyncError: Error {
    case iCloudUnavailable
    case notFound
    case transport(Error)
}

/// In-memory `SecretSyncStore` fake for host tests. Holds one `SyncedSecret?` and can be primed
/// to throw `.iCloudUnavailable` on both `fetch` and `publish`.
public final class InMemorySecretSyncStore: SecretSyncStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SyncedSecret?
    private var failure: SecretSyncError?

    public init(stored: SyncedSecret? = nil) {
        self.stored = stored
    }

    /// Prime (or clear) a failure returned by both `fetch` and `publish`.
    public func primeFailure(_ error: SecretSyncError?) {
        lock.withLock { failure = error }
    }

    /// Non-throwing peek at the stored secret, for test assertions.
    public func peekStored() -> SyncedSecret? {
        lock.withLock { stored }
    }

    public func publish(_ secret: SyncedSecret) async throws {
        let failure: SecretSyncError? = lock.withLock {
            if self.failure == nil { stored = secret }
            return self.failure
        }
        if let failure { throw failure }
    }

    public func fetch() async throws -> SyncedSecret? {
        let (failure, stored): (SecretSyncError?, SyncedSecret?) = lock.withLock {
            (self.failure, self.stored)
        }
        if let failure { throw failure }
        return stored
    }
}
