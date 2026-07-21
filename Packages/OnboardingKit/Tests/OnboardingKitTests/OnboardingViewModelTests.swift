import Foundation
import Testing
@testable import OnboardingKit
import ImmichClient

// @covers FR-210-01
@MainActor @Test func choosePathRoutesSharedLinkToSetup() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))
    vm.step = .choice

    vm.choosePath(.sharedLink)

    #expect(vm.step == .sharedLinkSetup)
    #expect(vm.errorMessage == nil)
}

// @covers FR-210-01
@MainActor @Test func choosePathRoutesServerToConnection() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))
    vm.step = .choice

    vm.choosePath(.server)

    #expect(vm.step == .connection)
}

// Finding 3 (FR-210-26): every step after the choice screen can step back in-place, without
// an app restart and without discarding entered configuration.
// @covers FR-210-26
@MainActor @Test func backFromSharedLinkSetupReturnsToChoice() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))
    vm.step = .sharedLinkSetup

    vm.back()

    #expect(vm.step == .choice)
}

// @covers FR-210-26
@MainActor @Test func backFromConnectionReturnsToChoice() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))
    vm.step = .connection

    vm.back()

    #expect(vm.step == .choice)
}

// @covers FR-210-26
@MainActor @Test func backFromSourceReturnsToConnection() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))
    vm.step = .source

    vm.back()

    #expect(vm.step == .connection)
}

// @covers FR-210-26
@MainActor @Test func backFromConfirmReturnsToSource() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))
    vm.step = .confirm

    vm.back()

    #expect(vm.step == .source)
}

// @covers FR-210-26, FR-220-09
@MainActor @Test func backFromChoiceIsNoOp() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))
    vm.step = .choice

    vm.back()

    #expect(vm.step == .choice)
}

// @covers FR-210-26
@MainActor @Test func canGoBackIsFalseOnlyAtChoiceAndDone() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))

    vm.step = .choice
    #expect(vm.canGoBack == false)
    vm.step = .done
    #expect(vm.canGoBack == false)
    vm.step = .sharedLinkSetup
    #expect(vm.canGoBack == true)
    vm.step = .connection
    #expect(vm.canGoBack == true)
    vm.step = .source
    #expect(vm.canGoBack == true)
    vm.step = .confirm
    #expect(vm.canGoBack == true)
}

// @covers FR-210-26
@MainActor @Test func backPreservesEnteredConnectionInputs() {
    let vm = makeVM(api: AlbumsAPI(result: .success([])))
    vm.serverURLInput = "https://immich.example.test"
    vm.apiKeyInput = "secret-key"
    vm.step = .source

    vm.back()

    #expect(vm.step == .connection)
    #expect(vm.serverURLInput == "https://immich.example.test")
    #expect(vm.apiKeyInput == "secret-key")
}

// @covers FR-210-02, FR-220-09
@MainActor @Test func finishFromSharedLinkOnlyPathCompletesWithoutAPIKeyOrConfig() {
    // The low-friction path: the resolve engine has already made a shared link the active
    // source. Finishing routes to the slideshow with no API key and no AppConfiguration.
    let config = InMemoryConfigStore()
    let keychain = InMemoryKeychainStore()
    var library = SourceLibrary()
    library.add(Source(label: "Korsika", kind: .sharedLink(baseURL: URL(string: "https://bilder.example.test")!, slug: "korsika")))
    let sourceStore = InMemorySourceLibraryStore(library: library)
    let vm = makeVM(api: AlbumsAPI(result: .success([])), config: config, keychain: keychain, sourceStore: sourceStore)
    vm.step = .sharedLinkSetup

    vm.finish()

    #expect(vm.step == .done)
    #expect(keychain.read() == nil)
    #expect(config.load() == nil)
}

// @covers FR-200-05
@MainActor @Test func rejectsNonHTTPSURL() async {
    let api = AlbumsAPI(result: .failure(ImmichError.unreachable))
    let vm = makeVM(api: api)
    vm.serverURLInput = "http://foo"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .connection)
    #expect(vm.errorMessage != nil)
    #expect(await api.albumsCallCount == 0)
}

// @covers FR-200-06
@MainActor @Test func advancesToSourceWhenReachableAndAuthorized() async throws {
    let keychain = InMemoryKeychainStore()
    let config = InMemoryConfigStore()
    let api = AlbumsAPI(result: .success([Album(id: "a1", name: "Fam")]))
    let vm = makeVM(api: api, config: config, keychain: keychain)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .source)
    #expect(keychain.read() == "key")
    // The base URL is persisted at connection so a shared-link-first source still resolves.
    #expect(config.loadBaseURL()?.host == "photos.example.test")
    #expect(vm.albums.map(\.id) == ["a1"])
    #expect(vm.errorMessage == nil)
    #expect(await api.albumsCallCount == 1)
}

// 130 FR-130-05: a pre-v3 server blocks the connection with the upgrade notice and never
// advances to the source step; the album fetch is gated out.
@MainActor @Test func submitConnectionBlocksPreV3ServerWithUpgradeNotice() async {
    let api = AlbumsAPI(result: .success([Album(id: "a1", name: "Fam")]), serverVersion: "2.118.0")
    let vm = makeVM(api: api)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .connection)
    #expect(vm.errorMessage == ConnectionError.message(for: .serverTooOld(version: "2.118.0")))
    #expect(await api.albumsCallCount == 0)
}

@MainActor @Test func advancesToSourceEvenWhenAlbumListEmpty() async throws {
    // An empty album list still proves the connection works; the user can add a shared
    // link on the source step, so onboarding advances instead of erroring (120, US2).
    let keychain = InMemoryKeychainStore()
    let config = InMemoryConfigStore()
    let api = AlbumsAPI(result: .success([]))
    let vm = makeVM(api: api, config: config, keychain: keychain)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .source)
    #expect(keychain.read() == "key")
    #expect(config.loadBaseURL()?.host == "photos.example.test")
    #expect(vm.albums.isEmpty)
    #expect(vm.errorMessage == nil)
}

// @covers FR-200-09
@MainActor @Test func finishWithActiveAlbumSourcePersistsConfigurationAndCompletes() async throws {
    let config = InMemoryConfigStore()
    var library = SourceLibrary()
    library.add(Source(label: "Fam", kind: .album(albumID: "a1")))
    let sourceStore = InMemorySourceLibraryStore(library: library)
    let vm = makeVM(api: AlbumsAPI(result: .success([])), config: config, sourceStore: sourceStore)
    config.saveBaseURL(URL(string: "https://photos.example.test")!)
    vm.step = .confirm

    vm.finish()

    #expect(vm.step == .done)
    let saved = config.load()
    #expect(saved?.selectedAlbumID == "a1")
    #expect(saved?.baseURL.host == "photos.example.test")
}

@MainActor @Test func finishWithActiveSharedLinkSourceCompletesWithoutSelectedAlbum() async throws {
    let config = InMemoryConfigStore()
    var library = SourceLibrary()
    library.add(Source(label: "Korsika", kind: .sharedLink(baseURL: URL(string: "https://bilder.example.test")!, slug: "korsika")))
    let sourceStore = InMemorySourceLibraryStore(library: library)
    let vm = makeVM(api: AlbumsAPI(result: .success([])), config: config, sourceStore: sourceStore)
    config.saveBaseURL(URL(string: "https://photos.example.test")!)
    vm.step = .confirm

    vm.finish()

    #expect(vm.step == .done)
    // No album was chosen, so there is no AppConfiguration — only the saved base URL.
    #expect(config.load() == nil)
    #expect(config.loadBaseURL()?.host == "photos.example.test")
}

@MainActor @Test func retriesUnreachableThenAdvancesWhenPermissionGranted() async {
    // The iOS Local Network prompt makes the first connection fail on a fresh install;
    // once the user grants access the retry succeeds. A bounded auto-retry rides that
    // out so onboarding advances instead of dead-ending on "server not available" the
    // user has to dismiss and re-trigger (Bug 1).
    let keychain = InMemoryKeychainStore()
    let config = InMemoryConfigStore()
    let api = FlakyAlbumsAPI(failuresBeforeSuccess: 1, albums: [Album(id: "a1", name: "Fam")])
    let vm = makeVM(api: api, config: config, keychain: keychain, retryLimit: 4)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .source)
    #expect(keychain.read() == "key")
    #expect(config.loadBaseURL()?.host == "photos.example.test")
    #expect(vm.albums.map(\.id) == ["a1"])
    #expect(vm.errorMessage == nil)
    // One failed attempt + one successful retry.
    #expect(await api.albumsCallCount == 2)
}

@MainActor @Test func surfacesUnreachableAfterExhaustingRetries() async {
    // A genuinely unreachable server still errors out — bounded, not an infinite loop.
    let keychain = InMemoryKeychainStore()
    let api = AlbumsAPI(result: .failure(ImmichError.unreachable))
    let vm = makeVM(api: api, keychain: keychain, retryLimit: 2)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .connection)
    #expect(keychain.read() == nil)
    #expect(vm.errorMessage == ConnectionError.message(for: .unreachable))
    // Initial attempt + retryLimit retries, then it gives up.
    #expect(await api.albumsCallCount == 3)
}

@MainActor @Test func doesNotRetryDeterministicErrors() async {
    // Auth failures won't change on retry, so they surface immediately without burning
    // the retry budget (the retry is scoped to `.unreachable`).
    let keychain = InMemoryKeychainStore()
    let api = AlbumsAPI(result: .failure(ImmichError.unauthorized))
    let vm = makeVM(api: api, keychain: keychain, retryLimit: 4)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .connection)
    #expect(vm.errorMessage == ConnectionError.message(for: .unauthorized))
    #expect(await api.albumsCallCount == 1)
}

// @covers FR-200-07
@MainActor @Test func staysWhenServerUnreachable() async {
    let keychain = InMemoryKeychainStore()
    let api = AlbumsAPI(result: .failure(ImmichError.unreachable))
    let vm = makeVM(api: api, keychain: keychain)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .connection)
    #expect(keychain.read() == nil)
    #expect(vm.errorMessage == ConnectionError.message(for: .unreachable))
    #expect(await api.albumsCallCount == 1)
}

// @covers FR-200-07
@MainActor @Test func staysWhenUnauthorized() async {
    let keychain = InMemoryKeychainStore()
    let api = AlbumsAPI(result: .failure(ImmichError.unauthorized))
    let vm = makeVM(api: api, keychain: keychain)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    let unauthorizedMessage = ConnectionError.message(for: .unauthorized)
    let unreachableMessage = ConnectionError.message(for: .unreachable)
    #expect(vm.step == .connection)
    #expect(keychain.read() == nil)
    #expect(vm.errorMessage == unauthorizedMessage)
    #expect(unauthorizedMessage != unreachableMessage)
    #expect(await api.albumsCallCount == 1)
}

// @covers FR-200-07
@MainActor @Test func staysWhenInvalidResponsePreservesConnectionInputsAndClassifiesError() async {
    let keychain = InMemoryKeychainStore()
    let api = AlbumsAPI(result: .failure(ImmichError.invalidResponse))
    let vm = makeVM(api: api, keychain: keychain)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    let invalidResponseMessage = ConnectionError.message(for: .invalidResponse)
    #expect(vm.step == .connection)
    #expect(keychain.read() == nil)
    #expect(vm.serverURLInput == "https://photos.example.test")
    #expect(vm.apiKeyInput == "key")
    #expect(vm.errorMessage == invalidResponseMessage)
    #expect(invalidResponseMessage != ConnectionError.message(for: .unreachable))
    #expect(invalidResponseMessage != ConnectionError.message(for: .unauthorized))
    #expect(await api.albumsCallCount == 1)
}

@MainActor @Test func staysWhenKeychainSaveFails() async {
    let keychain = InMemoryKeychainStore(failSave: true)
    let api = AlbumsAPI(result: .success([Album(id: "a1", name: "Fam")]))
    let vm = makeVM(api: api, keychain: keychain)
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"

    await vm.submitConnection()

    #expect(vm.step == .connection)
    #expect(vm.errorMessage != nil)
    #expect(await api.albumsCallCount == 1)
}

// @covers FR-200-24
@MainActor @Test func resetReturnsToConnectionAndClearsLibrary() {
    let config = InMemoryConfigStore(configuration: AppConfiguration(
        baseURL: URL(string: "https://photos.example.test")!,
        selectedAlbumID: "a1"
    ))
    let keychain = InMemoryKeychainStore(apiKey: "key")
    var library = SourceLibrary()
    library.add(Source(label: "Fam", kind: .album(albumID: "a1")))
    let sourceStore = InMemorySourceLibraryStore(library: library)
    let vm = makeVM(api: AlbumsAPI(result: .success([])), config: config, keychain: keychain, sourceStore: sourceStore)
    vm.step = .confirm
    vm.serverURLInput = "https://photos.example.test"
    vm.apiKeyInput = "key"
    vm.albums = [Album(id: "a1", name: "Fam")]
    vm.errorMessage = "etwas"

    vm.reset()

    #expect(config.load() == nil)
    #expect(keychain.read() == nil)
    #expect(sourceStore.load().sources.isEmpty)
    #expect(vm.step == .connection)
    #expect(vm.serverURLInput == "")
    #expect(vm.apiKeyInput == "")
    #expect(vm.albums.isEmpty)
    #expect(vm.errorMessage == nil)
}

@MainActor private func makeVM(
    api: any ImmichAPI,
    config: InMemoryConfigStore = .init(),
    keychain: InMemoryKeychainStore = .init(),
    sourceStore: InMemorySourceLibraryStore = .init(),
    retryLimit: Int = 0
) -> OnboardingViewModel {
    OnboardingViewModel(
        api: { _ in api },
        config: config,
        keychain: keychain,
        sourceStore: sourceStore,
        connectionRetryLimit: retryLimit,
        connectionRetryDelay: .zero,
        // No real waiting in tests — the retry cadence is host behaviour, not under test.
        sleep: { _ in }
    )
}

private actor AlbumsAPI: ImmichAPI {
    private let result: Result<[Album], Error>
    private let serverVersionString: String
    private(set) var albumsCallCount = 0

    init(result: Result<[Album], Error>, serverVersion: String = "3.0.2") {
        self.result = result
        self.serverVersionString = serverVersion
    }

    func serverVersion() async throws -> String {
        serverVersionString
    }

    func albums() async throws -> [Album] {
        albumsCallCount += 1
        return try result.get()
    }

    func assets(albumID: String) async throws -> [Asset] {
        []
    }

    func preview(assetID: String) async throws -> Data {
        Data()
    }
}

/// Fails `.unreachable` for the first `failuresBeforeSuccess` calls, then returns
/// `albums` — models the Local Network prompt blocking the first request and the
/// retry succeeding once the user grants access.
private actor FlakyAlbumsAPI: ImmichAPI {
    private let failuresBeforeSuccess: Int
    private let albumsResult: [Album]
    private(set) var albumsCallCount = 0

    init(failuresBeforeSuccess: Int, albums: [Album]) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.albumsResult = albums
    }

    func serverVersion() async throws -> String {
        "3.0.2"
    }

    func albums() async throws -> [Album] {
        albumsCallCount += 1
        if albumsCallCount <= failuresBeforeSuccess {
            throw ImmichError.unreachable
        }
        return albumsResult
    }

    func assets(albumID: String) async throws -> [Asset] {
        []
    }

    func preview(assetID: String) async throws -> Data {
        Data()
    }
}
