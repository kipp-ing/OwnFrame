/// Drives the resolve-first / ask-password-only-when-needed flow shared by onboarding
/// and Settings → Sources (210, D6). A link is resolved before anything is persisted;
/// a password is requested only when the server reports one is required.
public enum SharedLinkAddState: Sendable, Equatable {
    /// No resolution in flight.
    case idle
    /// A resolve call is in flight (show a spinner).
    case resolving
    /// The server returned `passwordRequired`; show the password prompt. Nothing persisted.
    case needsPassword
    /// The link resolved and the source was persisted; `sourceID` is the saved/reused source.
    case resolved(sourceID: String)
    /// Malformed / invalid / expired / unreachable / wrong-password — nothing persisted.
    case error(String)
}
