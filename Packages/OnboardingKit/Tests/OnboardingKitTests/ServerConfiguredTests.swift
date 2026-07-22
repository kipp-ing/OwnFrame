import Foundation
import Testing
@testable import OnboardingKit

/// Host tests for the `serverConfigured` predicate — the discriminator the album picker
/// uses to tell "no server configured" (guide the user to add one) apart from a genuine
/// network/load error against a configured server (210, FR-210-30 / SC-210-13).
///
/// The predicate is `true` only when **both** a server base URL (ConfigStore) and an API
/// key (Keychain) are stored — exactly the precondition the app's server-API-client
/// factory checks — and `false` if either is missing.
// @covers FR-210-30
@Suite struct ServerConfiguredTests {
    private let baseURL = URL(string: "https://photos.example.test")!

    @Test func falseWhenNeitherBaseURLNorAPIKeyIsStored() {
        let config = InMemoryConfigStore()
        let keychain = InMemoryKeychainStore()

        #expect(serverConfigured(config: config, keychain: keychain) == false)
    }

    @Test func falseWhenOnlyBaseURLIsStored() {
        let config = InMemoryConfigStore()
        config.saveBaseURL(baseURL)
        let keychain = InMemoryKeychainStore()

        #expect(serverConfigured(config: config, keychain: keychain) == false)
    }

    @Test func falseWhenOnlyAPIKeyIsStored() {
        let config = InMemoryConfigStore()
        let keychain = InMemoryKeychainStore(apiKey: "secret-key")

        #expect(serverConfigured(config: config, keychain: keychain) == false)
    }

    @Test func trueOnlyWhenBothBaseURLAndAPIKeyAreStored() {
        let config = InMemoryConfigStore()
        config.saveBaseURL(baseURL)
        let keychain = InMemoryKeychainStore(apiKey: "secret-key")

        #expect(serverConfigured(config: config, keychain: keychain) == true)
    }
}
