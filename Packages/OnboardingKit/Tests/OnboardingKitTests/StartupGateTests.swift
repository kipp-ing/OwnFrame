import Foundation
import Testing
@testable import OnboardingKit

private let url = URL(string: "https://photos.example.test")!

private func albumLibrary() -> InMemorySourceLibraryStore {
    var library = SourceLibrary()
    library.add(Source(label: "Wohnzimmer", kind: .album(albumID: "a1")))
    return InMemorySourceLibraryStore(library: library)
}

private func sharedLinkLibrary() -> InMemorySourceLibraryStore {
    var library = SourceLibrary()
    library.add(Source(label: "Korsika", kind: .sharedLink(baseURL: url, slug: "korsika")))
    return InMemorySourceLibraryStore(library: library)
}

private func photoLibraryLibrary() -> InMemorySourceLibraryStore {
    var library = SourceLibrary()
    library.add(Source(label: "Beach 2019", kind: .photoLibrary(collectionID: "col-1")))
    return InMemorySourceLibraryStore(library: library)
}

@Test func startupGateReturnsDoneForConnectionAndActiveAlbumSource() {
    let config = InMemoryConfigStore(
        configuration: AppConfiguration(baseURL: url, selectedAlbumID: "a1")
    )
    let keychain = InMemoryKeychainStore(apiKey: "key")
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: albumLibrary())

    #expect(gate.initialStep() == .done)
}

@Test func startupGateReturnsDoneForSharedLinkSourceWithoutAPIKeyOrBaseURL() {
    // A shared link authenticates itself — onboarding is complete with no API key and no
    // separately saved base URL (210, D2).
    let config = InMemoryConfigStore()
    let keychain = InMemoryKeychainStore()
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: sharedLinkLibrary())

    #expect(gate.initialStep() == .done)
}

@Test func startupGateReturnsDoneForPhotoLibrarySourceWithoutAPIKeyOrBaseURL() {
    // A device photo-library source is self-authenticating — photo permission is (re)checked
    // by the provider at engine start (900/R5), so startup resumes straight into the
    // slideshow with no Immich API key or base URL (US1-4 startup parity).
    let config = InMemoryConfigStore()
    let keychain = InMemoryKeychainStore()
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: photoLibraryLibrary())

    #expect(gate.initialStep() == .done)
}

@Test func startupGateReturnsConnectionForAlbumSourceWithoutAPIKey() {
    let config = InMemoryConfigStore(
        configuration: AppConfiguration(baseURL: url, selectedAlbumID: "a1")
    )
    let keychain = InMemoryKeychainStore()
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: albumLibrary())

    #expect(gate.initialStep() == .connection)
}

@Test func startupGateReturnsConnectionForAlbumSourceWithoutBaseURL() {
    let config = InMemoryConfigStore()
    let keychain = InMemoryKeychainStore(apiKey: "key")
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: albumLibrary())

    #expect(gate.initialStep() == .connection)
}

@Test func startupGateReturnsChoiceWhenEmpty() {
    // A blank install opens on the choice screen (shared link vs server), not at the
    // server-connection form (210).
    let config = InMemoryConfigStore()
    let keychain = InMemoryKeychainStore()
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: InMemorySourceLibraryStore())

    #expect(gate.initialStep() == .choice)
}

@Test func startupGateReturnsSourceWhenConnectedButLibraryEmpty() {
    // Connection validated (key + baseURL persisted) but no source added yet → resume at
    // the add-source step rather than dead-ending at the slideshow (120, US2).
    let config = InMemoryConfigStore()
    config.saveBaseURL(url)
    let keychain = InMemoryKeychainStore(apiKey: "key")
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: InMemorySourceLibraryStore())

    #expect(gate.initialStep() == .source)
}

@Test func startupGateMigratesLegacySelectedAlbumIDToDone() {
    // A pre-120 install: baseURL + key + legacy selectedAlbumID, no library yet. The store
    // migrates the album into a one-entry active library on load, so the gate routes to the
    // running slideshow without re-onboarding.
    let defaults = makeStartupGateDefaults()
    defaults.set(url.absoluteString, forKey: "immich.baseURL")
    defaults.set("a1", forKey: "immich.selectedAlbumID")
    let config = UserDefaultsConfigStore(defaults: defaults)
    let sourceStore = UserDefaultsSourceLibraryStore(defaults: defaults)
    let keychain = InMemoryKeychainStore(apiKey: "key")
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: sourceStore)

    #expect(gate.initialStep() == .done)
}

private func makeStartupGateDefaults() -> UserDefaults {
    let suiteName = "StartupGateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
