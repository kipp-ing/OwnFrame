import Foundation
import ImmichClient
import Testing
@testable import OnboardingKit

@MainActor
@Test func sourceLibraryViewModelLoadsLibraryOnInit() {
    var seeded = SourceLibrary()
    seeded.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))
    let store = InMemorySourceLibraryStore(library: seeded)

    let viewModel = makeViewModel(store: store)

    #expect(viewModel.sources.map(\.id) == ["source-1"])
    #expect(viewModel.activeID == "source-1")
}

@MainActor
// @covers FR-120-04
@Test func sourceLibraryViewModelAddAlbumSourcePersistsAndActivatesFirst() {
    let store = InMemorySourceLibraryStore()
    let viewModel = makeViewModel(store: store)

    viewModel.addAlbumSource(albumID: "album-1", label: "Living Room")

    #expect(viewModel.sources.count == 1)
    #expect(viewModel.sources[0].kind == .album(albumID: "album-1"))
    #expect(viewModel.activeID == viewModel.sources[0].id)
    #expect(store.load().sources.map(\.label) == ["Living Room"])
}

@MainActor
// @covers FR-120-04, FR-220-10
@Test func sourceLibraryViewModelAddPhotoLibrarySourcePersistsAndActivatesFirst() {
    let store = InMemorySourceLibraryStore()
    let viewModel = makeViewModel(store: store)

    viewModel.addPhotoLibrarySource(collectionID: "selected-photos", label: "Selected Photos")

    #expect(viewModel.sources.count == 1)
    #expect(viewModel.sources[0].kind == .photoLibrary(collectionID: "selected-photos"))
    #expect(viewModel.sources[0].label == "Selected Photos")
    #expect(viewModel.activeID == viewModel.sources[0].id)
    #expect(store.load().sources.map(\.label) == ["Selected Photos"])
}

@MainActor
// @covers FR-220-10
@Test func sourceLibraryViewModelListsAndActivatesPhotoLibrarySourceLikeAnyOther() {
    var seeded = SourceLibrary()
    seeded.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))
    seeded.add(Source(id: "source-2", label: "Beach 2019", kind: .photoLibrary(collectionID: "col-2")))
    let store = InMemorySourceLibraryStore(library: seeded)
    var switched: [String] = []
    let viewModel = makeViewModel(store: store, onSwitchActive: { id in
        switched.append(id)
        var lib = store.load()
        lib.setActive(id: id)
        store.save(lib)
    })

    // Listed with the label set at save time — no special casing for the photoLibrary kind.
    #expect(viewModel.sources.map(\.label) == ["Family", "Beach 2019"])

    viewModel.setActive(id: "source-2")

    #expect(switched == ["source-2"])
    #expect(viewModel.activeID == "source-2")
}

@MainActor
@Test func sourceLibraryViewModelRejectsDuplicateLabel() {
    let store = InMemorySourceLibraryStore()
    let viewModel = makeViewModel(store: store)
    viewModel.addAlbumSource(albumID: "album-1", label: "Family")

    viewModel.addAlbumSource(albumID: "album-2", label: "Family")

    #expect(viewModel.sources.count == 1)
    #expect(viewModel.errorMessage != nil)
}

// The shared-link add path is the two-phase resolve flow (210, US4) — see the
// "Two-phase resolve" section below. Removing such a source must delete its secret.
@MainActor
// @covers FR-120-04, FR-120-14
@Test func sourceLibraryViewModelRemoveSharedLinkDeletesPassword() async {
    let store = InMemorySourceLibraryStore()
    let secretStore = InMemorySharedLinkSecretStore()
    let viewModel = makeViewModel(store: store, secretStore: secretStore, resolver: PasswordGatedResolver(correctPassword: "pw"))
    await viewModel.resolveSharedLink(urlString: geoURL, label: "Geo")
    await viewModel.confirmSharedLinkPassword("pw")
    let id = viewModel.sources[0].id
    #expect(secretStore.readPassword(forSourceID: id) == "pw")

    viewModel.remove(id: id)

    #expect(viewModel.sources.isEmpty)
    #expect(secretStore.readPassword(forSourceID: id) == nil)
    #expect(store.load().sources.isEmpty)
}

// Issue #80's offline fallback keeps a link's resolved share key in the Keychain. Like the
// password, it must not outlive its source.
@MainActor
// @covers FR-120-14
@Test func sourceLibraryViewModelRemoveSharedLinkDeletesCachedResolution() async {
    let resolutionCache = InMemorySharedLinkResolutionStore()
    let viewModel = SourceLibraryViewModel(
        store: InMemorySourceLibraryStore(),
        secretStore: InMemorySharedLinkSecretStore(),
        resolver: StubResolver(),
        resolutionCache: resolutionCache
    )
    await viewModel.resolveSharedLink(urlString: geoURL, label: "Geo")
    let id = viewModel.sources[0].id
    resolutionCache.save(SharedLinkResolution(key: "share-key", albumID: "a1", expiresAt: nil), forSourceID: id)

    viewModel.remove(id: id)

    #expect(resolutionCache.read(forSourceID: id) == nil)
}

// 120 T040 (FR-120-14): only a link has a password — removing an album source deletes none.
@MainActor
// @covers FR-120-14
@Test func sourceLibraryViewModelRemoveAlbumSourceDeletesNoPassword() {
    var seeded = SourceLibrary()
    seeded.add(Source(id: "album-source", label: "Family", kind: .album(albumID: "album-1")))
    let store = InMemorySourceLibraryStore(library: seeded)
    let secretStore = RecordingSecretStore()
    let viewModel = SourceLibraryViewModel(store: store, secretStore: secretStore, resolver: StubResolver())

    viewModel.remove(id: "album-source")

    #expect(viewModel.sources.isEmpty)
    #expect(secretStore.deletedIDs.isEmpty)
}

@MainActor
// @covers FR-120-04
@Test func sourceLibraryViewModelRenameAndMovePersist() {
    let store = InMemorySourceLibraryStore()
    let viewModel = makeViewModel(store: store)
    viewModel.addAlbumSource(albumID: "album-1", label: "Family")
    viewModel.addAlbumSource(albumID: "album-2", label: "Travel")

    viewModel.rename(id: viewModel.sources[1].id, to: "Summer")
    viewModel.move(from: IndexSet(integer: 1), to: 0)

    #expect(store.load().sources.map(\.label) == ["Summer", "Family"])
}

@MainActor
// @covers FR-120-04
@Test func sourceLibraryViewModelSetActiveDelegatesAndReflectsReload() {
    var seeded = SourceLibrary()
    seeded.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))
    seeded.add(Source(id: "source-2", label: "Travel", kind: .album(albumID: "album-2")))
    let store = InMemorySourceLibraryStore(library: seeded)
    var switched: [String] = []
    // The app layer owns persisting the active change (US1 switchActiveSource); the VM
    // delegates and then reflects the reloaded library.
    let viewModel = makeViewModel(store: store, onSwitchActive: { id in
        switched.append(id)
        var lib = store.load()
        lib.setActive(id: id)
        store.save(lib)
    })

    viewModel.setActive(id: "source-2")

    #expect(switched == ["source-2"])
    #expect(viewModel.activeID == "source-2")
}

@MainActor
@Test func sourceLibraryViewModelSetActiveIgnoresUnknownAndAlreadyActive() {
    var seeded = SourceLibrary()
    seeded.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))
    let store = InMemorySourceLibraryStore(library: seeded)
    var switched: [String] = []
    let viewModel = makeViewModel(store: store, onSwitchActive: { switched.append($0) })

    viewModel.setActive(id: "source-1") // already active
    viewModel.setActive(id: "missing")  // unknown

    #expect(switched.isEmpty)
}

// MARK: - Two-phase resolve (210, US1/US4)

private let geoURL = "https://bilder.kippings.de/s/geo2026"
private let geoBaseURL = URL(string: "https://bilder.kippings.de")!

@MainActor
// @covers FR-210-06, FR-210-08, FR-120-09
@Test func resolveSharedLinkWithoutPasswordPersistsAndResolves() async {
    let store = InMemorySourceLibraryStore()
    let secretStore = InMemorySharedLinkSecretStore()
    let vm = makeViewModel(store: store, secretStore: secretStore, resolver: PasswordGatedResolver(correctPassword: nil))

    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

    #expect(vm.addState == .resolved(sourceID: vm.sources[0].id))
    #expect(vm.sources.count == 1)
    #expect(vm.sources[0].kind == .sharedLink(baseURL: geoBaseURL, slug: "geo2026"))
    #expect(secretStore.readPassword(forSourceID: vm.sources[0].id) == nil)
    #expect(store.load().sources.count == 1)
}

@MainActor
// @covers FR-210-06, FR-210-08, FR-120-09
@Test func resolveSharedLinkRequiringPasswordAsksAndPersistsNothing() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: PasswordGatedResolver(correctPassword: "pw"))

    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

    #expect(vm.addState == .needsPassword)
    #expect(vm.sources.isEmpty)
    #expect(store.load().sources.isEmpty)
}

@MainActor
// @covers FR-210-08
@Test func confirmSharedLinkPasswordPersistsSourceAndStoresSecret() async {
    let store = InMemorySourceLibraryStore()
    let secretStore = InMemorySharedLinkSecretStore()
    let vm = makeViewModel(store: store, secretStore: secretStore, resolver: PasswordGatedResolver(correctPassword: "pw"))
    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

    await vm.confirmSharedLinkPassword("pw")

    #expect(vm.addState == .resolved(sourceID: vm.sources[0].id))
    #expect(vm.sources.count == 1)
    #expect(secretStore.readPassword(forSourceID: vm.sources[0].id) == "pw")
    #expect(store.load().sources.count == 1)
}

@MainActor
// @covers FR-210-08, FR-120-09
@Test func confirmSharedLinkWrongPasswordErrorsAndPersistsNothing() async {
    let store = InMemorySourceLibraryStore()
    let secretStore = InMemorySharedLinkSecretStore()
    let vm = makeViewModel(store: store, secretStore: secretStore, resolver: PasswordGatedResolver(correctPassword: "pw"))
    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

    await vm.confirmSharedLinkPassword("bad")

    #expect(vm.addState == .error(ConnectionError.message(for: .wrongPassword)))
    #expect(vm.sources.isEmpty)
    #expect(store.load().sources.isEmpty)
}

// The prompt stays open after a wrong password with Continue enabled, so a second try in the
// same prompt must be resolved — not silently dropped (found on iPad jk, 2026-09-25: after
// one typo the right password did nothing until the person cancelled and started over).
@MainActor
// @covers FR-210-08
@Test func confirmSharedLinkRightPasswordAfterAWrongOneResolves() async {
    let secretStore = InMemorySharedLinkSecretStore()
    let vm = makeViewModel(secretStore: secretStore, resolver: PasswordGatedResolver(correctPassword: "pw"))
    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")
    await vm.confirmSharedLinkPassword("bad")

    await vm.confirmSharedLinkPassword("pw")

    #expect(vm.sources.count == 1)
    #expect(secretStore.readPassword(forSourceID: vm.sources[0].id) == "pw")
}

@MainActor
// @covers FR-210-09, FR-210-17
@Test func resolveSharedLinkMalformedURLErrorsWithoutNetwork() async {
    let resolver = PasswordGatedResolver(correctPassword: nil)
    let vm = makeViewModel(resolver: resolver)

    await vm.resolveSharedLink(urlString: "http://insecure.example", label: "Bad")

    if case .error = vm.addState {} else { Issue.record("expected .error, got \(vm.addState)") }
    #expect(resolver.requests.isEmpty) // HTTPS-only guard short-circuits before any request
    #expect(vm.sources.isEmpty)
}

@MainActor
// @covers FR-210-08, FR-120-09, FR-210-17
@Test func resolveSharedLinkSurfacesResolverErrorAndPersistsNothing() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: StubResolver(result: .failure(ImmichError.invalidShareLink)))

    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

    #expect(vm.addState == .error(ConnectionError.message(for: .invalidShareLink)))
    #expect(vm.sources.isEmpty)
    #expect(store.load().sources.isEmpty)
}

@MainActor
@Test func confirmSharedLinkPasswordIsNoOpUnlessNeedsPassword() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: PasswordGatedResolver(correctPassword: nil))

    await vm.confirmSharedLinkPassword("pw") // addState is .idle

    #expect(vm.addState == .idle)
    #expect(store.load().sources.isEmpty)
}

@MainActor
// @covers FR-210-16
@Test func resolveSharedLinkDedupsByBaseURLAndSlug() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: PasswordGatedResolver(correctPassword: nil))

    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")
    let firstID = vm.sources[0].id
    await vm.resolveSharedLink(urlString: geoURL, label: "Geo again")

    #expect(vm.sources.count == 1)
    #expect(vm.addState == .resolved(sourceID: firstID))
    #expect(store.load().sources.count == 1)
}

// MARK: - Album-name default label (310 Phase 7, #61)

@MainActor
// @covers FR-310-16, FR-120-13
@Test func resolveSharedLinkWithoutLabelStoresTheAlbumName() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: StubResolver(albumName: "Iceland 2021"))

    await vm.resolveSharedLink(urlString: geoURL, label: "")

    #expect(vm.sources.map(\.label) == ["Iceland 2021"])
    #expect(store.load().sources.map(\.label) == ["Iceland 2021"])
}

@MainActor
// @covers FR-310-16, FR-120-13
@Test func confirmSharedLinkPasswordWithoutLabelStoresTheAlbumName() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: PasswordGatedResolver(correctPassword: "pw", albumName: "Iceland 2021"))
    await vm.resolveSharedLink(urlString: geoURL, label: "")

    await vm.confirmSharedLinkPassword("pw")

    #expect(vm.sources.map(\.label) == ["Iceland 2021"])
    #expect(store.load().sources.map(\.label) == ["Iceland 2021"])
}

@MainActor
// @covers FR-310-16, FR-120-13
@Test func addScannedSharedLinkWithoutLabelStoresTheAlbumName() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: StubResolver(albumName: "Iceland 2021"))

    await vm.addScannedSharedLink(using: FixedScanner(result: geoURL), label: "")

    #expect(vm.sources.map(\.label) == ["Iceland 2021"])
    #expect(store.load().sources.map(\.label) == ["Iceland 2021"])
}

@MainActor
// @covers FR-310-16, FR-120-13
@Test func typedLabelWinsOverTheAlbumName() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: StubResolver(albumName: "Iceland 2021"))

    await vm.resolveSharedLink(urlString: geoURL, label: "  Geo  ")

    #expect(store.load().sources.map(\.label) == ["Geo"])
}

@MainActor
// @covers FR-310-16
@Test func collidingAlbumNameGetsANumericSuffix() async {
    var seeded = SourceLibrary()
    seeded.add(Source(label: "Iceland 2021", kind: .album(albumID: "album-1")))
    let store = InMemorySourceLibraryStore(library: seeded)
    let vm = makeViewModel(store: store, resolver: StubResolver(albumName: "Iceland 2021"))

    await vm.resolveSharedLink(urlString: geoURL, label: "")

    #expect(store.load().sources.map(\.label) == ["Iceland 2021", "Iceland 2021 2"])
}

// Without a reported name the stored label keeps today's non-empty host fallback — never the
// localized placeholder, which is applied only at display time (FR-120-13).
@MainActor
// @covers FR-310-16, FR-120-13
@Test(arguments: [nil, "", "   "] as [String?])
func sharedLinkWithoutAlbumNameStoresTheHostFallback(_ albumName: String?) async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: StubResolver(albumName: albumName))

    await vm.resolveSharedLink(urlString: geoURL, label: "")

    #expect(store.load().sources.map(\.label) == [geoBaseURL.host!])
}

// MARK: - Local Network permission retry (found on device 2026-09-25)

@MainActor
@Test func resolveSharedLinkRetriesUnreachableThenSucceeds() async {
    for failures in [1, 2] {
        let store = InMemorySourceLibraryStore()
        let resolver = ScriptedResolver(Array(repeating: .failure(ImmichError.unreachable), count: failures) + [.success])
        var sleeps: [Duration] = []
        let vm = makeRetryingViewModel(store: store, resolver: resolver) { sleeps.append($0) }

        await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

        #expect(resolver.requests.count == failures + 1)
        #expect(sleeps.count == failures)
        #expect(vm.sources.count == 1)
        #expect(vm.addState == .resolved(sourceID: vm.sources.first?.id ?? "<none>"))
        #expect(store.load().sources.count == 1)
    }
}

@MainActor
@Test func resolveSharedLinkGivesUpAfterRetryLimitWithTheSameError() async {
    let store = InMemorySourceLibraryStore()
    let resolver = ScriptedResolver(Array(repeating: .failure(ImmichError.unreachable), count: 10))
    let vm = makeRetryingViewModel(store: store, resolver: resolver, retryLimit: 4)

    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

    #expect(resolver.requests.count == 5)
    #expect(vm.addState == .error(ConnectionError.message(for: .unreachable)))
    #expect(vm.sources.isEmpty)
    #expect(store.load().sources.isEmpty)
}

@MainActor
@Test func resolveSharedLinkDoesNotRetryDeterministicErrors() async {
    for error in [ImmichError.passwordRequired, .invalidShareLink, .wrongPassword] {
        let resolver = ScriptedResolver([.failure(error), .success])
        var sleeps: [Duration] = []
        let vm = makeRetryingViewModel(resolver: resolver) { sleeps.append($0) }

        await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

        #expect(resolver.requests.count == 1)
        #expect(sleeps.isEmpty)
        #expect(vm.sources.isEmpty)
    }
}

@MainActor
@Test func confirmSharedLinkPasswordRetriesUnreachableThenSucceeds() async {
    let store = InMemorySourceLibraryStore()
    let secretStore = InMemorySharedLinkSecretStore()
    let resolver = ScriptedResolver([
        .failure(ImmichError.passwordRequired),
        .failure(ImmichError.unreachable),
        .failure(ImmichError.unreachable),
        .success,
    ])
    let vm = makeRetryingViewModel(store: store, secretStore: secretStore, resolver: resolver)

    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")
    #expect(vm.addState == .needsPassword)

    await vm.confirmSharedLinkPassword("pw")

    #expect(resolver.requests.map(\.password) == [nil, "pw", "pw", "pw"])
    #expect(vm.sources.count == 1)
    let id = vm.sources.first?.id ?? "<none>"
    #expect(vm.addState == .resolved(sourceID: id))
    #expect(secretStore.readPassword(forSourceID: id) == "pw")
}

@MainActor
@Test func resolveSharedLinkStaysResolvingDuringRetries() async {
    let resolver = ScriptedResolver([.failure(ImmichError.unreachable), .success])
    var statesDuringSleep: [SharedLinkAddState] = []
    var vm: SourceLibraryViewModel!
    vm = makeRetryingViewModel(resolver: resolver) { _ in statesDuringSleep.append(vm.addState) }

    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

    #expect(statesDuringSleep == [.resolving])
}

// MARK: - Helpers

@MainActor
private func makeViewModel(
    store: InMemorySourceLibraryStore = InMemorySourceLibraryStore(),
    secretStore: InMemorySharedLinkSecretStore = InMemorySharedLinkSecretStore(),
    resolver: any SharedLinkResolving = StubResolver(),
    onSwitchActive: @escaping (String) -> Void = { _ in }
) -> SourceLibraryViewModel {
    SourceLibraryViewModel(
        store: store,
        secretStore: secretStore,
        resolver: resolver,
        onSwitchActive: onSwitchActive
    )
}

@MainActor
private func makeRetryingViewModel(
    store: InMemorySourceLibraryStore = InMemorySourceLibraryStore(),
    secretStore: InMemorySharedLinkSecretStore = InMemorySharedLinkSecretStore(),
    resolver: any SharedLinkResolving,
    retryLimit: Int = 4,
    sleep: @escaping @MainActor (Duration) -> Void = { _ in }
) -> SourceLibraryViewModel {
    SourceLibraryViewModel(
        store: store,
        secretStore: secretStore,
        resolver: resolver,
        resolveRetryLimit: retryLimit,
        resolveRetryDelay: .zero,
        sleep: { await sleep($0) }
    )
}

/// Resolver that plays back a fixed script of outcomes, one per call (the last one repeats).
private final class ScriptedResolver: SharedLinkResolving, @unchecked Sendable {
    enum Outcome {
        case success
        case failure(ImmichError)
    }

    private var script: [Outcome]
    private(set) var requests: [(baseURL: URL, slug: String, password: String?)] = []

    init(_ script: [Outcome]) {
        self.script = script
    }

    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        requests.append((baseURL, slug, password))
        let outcome = script.count > 1 ? script.removeFirst() : script[0]
        switch outcome {
        case .success:
            return SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil, albumName: "Iceland 2021")
        case let .failure(error):
            throw error
        }
    }
}

/// Resolver modelling a password-gated link: `correctPassword == nil` ⇒ no password
/// needed (any resolve succeeds); otherwise a `nil` password ⇒ `.passwordRequired`, the
/// correct password ⇒ success, any other password ⇒ `.wrongPassword`.
private final class PasswordGatedResolver: SharedLinkResolving, @unchecked Sendable {
    let correctPassword: String?
    let albumName: String?
    private(set) var requests: [(baseURL: URL, slug: String, password: String?)] = []

    init(correctPassword: String? = nil, albumName: String? = "Iceland 2021") {
        self.correctPassword = correctPassword
        self.albumName = albumName
    }

    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        requests.append((baseURL, slug, password))
        guard let correctPassword else {
            return SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil, albumName: albumName)
        }
        guard let password else { throw ImmichError.passwordRequired }
        guard password == correctPassword else { throw ImmichError.wrongPassword }
        return SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil, albumName: albumName)
    }
}

private final class StubResolver: SharedLinkResolving, @unchecked Sendable {
    struct Request: Equatable {
        let baseURL: URL
        let slug: String
        let password: String?
    }

    private let result: Result<SharedLinkResolution, Error>
    private(set) var requests: [Request] = []

    init(albumName: String? = "Iceland 2021") {
        self.result = .success(SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil, albumName: albumName))
    }

    init(result: Result<SharedLinkResolution, Error>) {
        self.result = result
    }

    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        requests.append(Request(baseURL: baseURL, slug: slug, password: password))
        return try result.get()
    }
}

private struct FixedScanner: CodeScanning {
    let result: String?

    func scan() async -> String? {
        result
    }
}

/// Records every password delete so a test can assert none happened.
private final class RecordingSecretStore: SharedLinkSecretStore, @unchecked Sendable {
    private(set) var deletedIDs: [String] = []

    func savePassword(_ password: String, forSourceID id: String) throws {}

    func readPassword(forSourceID id: String) -> String? { nil }

    func deletePassword(forSourceID id: String) {
        deletedIDs.append(id)
    }
}
