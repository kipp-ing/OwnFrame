public enum ImmichError: Error, Equatable {
    case unauthorized
    case unreachable
    case invalidResponse
    case invalidShareLink
    case shareLinkExpired
    case wrongPassword
    case passwordRequired
    /// The connected server is older than the minimum supported Immich major version (v3).
    /// Terminal: the app speaks the v3 API only and cannot operate against v2 (130).
    case serverTooOld(version: String)
}
