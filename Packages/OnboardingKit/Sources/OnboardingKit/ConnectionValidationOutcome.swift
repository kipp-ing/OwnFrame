import ImmichClient

public enum ConnectionValidationOutcome: Sendable {
    case malformed
    case unreachable
    case unauthorized
    case invalidResponse
    case keychainFailure
    case albumMissing(albums: [Album])
    /// The server is older than the supported Immich major version (v3) — the connection is
    /// rejected and the caller shows the upgrade notice instead of adopting it (130, FR-130-05).
    case serverTooOld(version: String)
    case success
}
