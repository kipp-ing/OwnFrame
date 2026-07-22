import Foundation

/// Pure, host-testable predicate for "is an Immich server connection configured?".
///
/// Returns `true` only when **both** a server base URL is stored (`ConfigStore.loadBaseURL()`,
/// which already requires an `https` scheme + non-nil host) **and** an API key is stored
/// (`KeychainStore.read()`). This is exactly the precondition the app's server-API-client
/// factory checks before it can list a server's albums.
///
/// Lifting it into a standalone helper (rather than burying it inside a SwiftUI view) lets the
/// album picker distinguish two reasons it cannot show albums — "no server configured" (guide
/// the user to add a server, FR-210-29) versus a genuine network/load error against a configured
/// server — instead of collapsing both into one misleading "couldn't load albums" message
/// (210, FR-210-30 / SC-210-13).
///
/// It performs only the two presence reads and no network call, so the no-server branch never
/// touches the network.
public func serverConfigured(config: any ConfigStore, keychain: any KeychainStore) -> Bool {
    config.loadBaseURL() != nil && keychain.read() != nil
}
