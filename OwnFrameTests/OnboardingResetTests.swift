//
//  OnboardingResetTests.swift
//  OwnFrameTests
//
//  App-hosted test for reset() against the REAL stores on the iPad simulator:
//  a complete state (UserDefaultsConfigStore + KeychainAPIKeyStore) is wiped and
//  the flow returns to step 1, with the API key actually removed from the
//  keychain (US3, FR-012/SC-006). The host suite covers reset() with fakes; this
//  proves it through the real Security-backed keychain.
//

import Foundation
import Testing
import ImmichClient
import OnboardingKit

@MainActor
struct OnboardingResetTests {

    @Test func resetClearsRealConfigAndKeychainAndReturnsToConnection() throws {
        let suiteName = "de.kippings.ImmichSlideshow.tests.reset"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = UserDefaultsConfigStore(defaults: defaults)
        let keychain = KeychainAPIKeyStore(
            service: "de.kippings.ImmichSlideshow.tests.reset.apiKey",
            account: "reset-account"
        )
        keychain.delete() // clean slate
        defer { keychain.delete() }

        let viewModel = OnboardingViewModel(
            api: { ImmichClient(config: $0) },
            config: config,
            keychain: keychain
        )

        // Seed a complete state through the real stores.
        let baseURL = try #require(URL(string: "https://photos.example.test"))
        config.save(AppConfiguration(baseURL: baseURL, selectedAlbumID: "a1"))
        try keychain.save("secret-key")
        viewModel.step = .done

        #expect(config.load() != nil)
        #expect(keychain.read() == "secret-key")

        viewModel.reset()

        #expect(config.load() == nil)
        #expect(keychain.read() == nil)
        #expect(viewModel.step == .connection)
    }

    /// 120, FR-120-14 (#73): a saved Immich link's password must not outlive Reset. Goes through
    /// the real Keychain-backed secret store under a test-only service name.
    // @covers FR-120-14
    @Test func resetDeletesSavedLinkPasswordsFromTheRealKeychain() throws {
        let suiteName = "de.kippings.ImmichSlideshow.tests.reset.links"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secretStore = KeychainSharedLinkSecretStore(
            service: "de.kippings.ImmichSlideshow.tests.reset.linkPassword"
        )
        let linkBaseURL = try #require(URL(string: "https://photos.example.test"))
        let link = Source(id: "link-1", label: "Family", kind: .sharedLink(baseURL: linkBaseURL, slug: "family"))
        let album = Source(id: "album-1", label: "Iceland", kind: .album(albumID: "a1"))
        secretStore.deletePassword(forSourceID: link.id) // clean slate
        defer { secretStore.deletePassword(forSourceID: link.id) }
        try secretStore.savePassword("link-secret", forSourceID: link.id)

        let sourceStore = InMemorySourceLibraryStore(
            library: SourceLibrary(sources: [link, album], activeID: link.id)
        )
        let viewModel = OnboardingViewModel(
            api: { ImmichClient(config: $0) },
            config: UserDefaultsConfigStore(defaults: defaults),
            keychain: KeychainAPIKeyStore(
                service: "de.kippings.ImmichSlideshow.tests.reset.links.apiKey",
                account: "reset-account"
            ),
            sourceStore: sourceStore,
            secretStore: secretStore
        )
        #expect(secretStore.readPassword(forSourceID: link.id) == "link-secret")

        viewModel.reset()

        #expect(secretStore.readPassword(forSourceID: link.id) == nil)
        #expect(sourceStore.load().sources.isEmpty)
    }
}
