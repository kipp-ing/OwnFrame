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

@MainActor
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
@Test func resolveSharedLinkRequiringPasswordAsksAndPersistsNothing() async {
    let store = InMemorySourceLibraryStore()
    let vm = makeViewModel(store: store, resolver: PasswordGatedResolver(correctPassword: "pw"))

    await vm.resolveSharedLink(urlString: geoURL, label: "Geo")

    #expect(vm.addState == .needsPassword)
    #expect(vm.sources.isEmpty)
    #expect(store.load().sources.isEmpty)
}

@MainActor
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

@MainActor
@Test func resolveSharedLinkMalformedURLErrorsWithoutNetwork() async {
    let resolver = PasswordGatedResolver(correctPassword: nil)
    let vm = makeViewModel(resolver: resolver)

    await vm.resolveSharedLink(urlString: "http://insecure.example", label: "Bad")

    if case .error = vm.addState {} else { Issue.record("expected .error, got \(vm.addState)") }
    #expect(resolver.requests.isEmpty) // HTTPS-only guard short-circuits before any request
    #expect(vm.sources.isEmpty)
}

@MainActor
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

/// Resolver modelling a password-gated link: `correctPassword == nil` ⇒ no password
/// needed (any resolve succeeds); otherwise a `nil` password ⇒ `.passwordRequired`, the
/// correct password ⇒ success, any other password ⇒ `.wrongPassword`.
private final class PasswordGatedResolver: SharedLinkResolving, @unchecked Sendable {
    let correctPassword: String?
    private(set) var requests: [(baseURL: URL, slug: String, password: String?)] = []

    init(correctPassword: String? = nil) {
        self.correctPassword = correctPassword
    }

    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        requests.append((baseURL, slug, password))
        guard let correctPassword else {
            return SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil)
        }
        guard let password else { throw ImmichError.passwordRequired }
        guard password == correctPassword else { throw ImmichError.wrongPassword }
        return SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil)
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

    init(result: Result<SharedLinkResolution, Error> = .success(SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil))) {
        self.result = result
    }

    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        requests.append(Request(baseURL: baseURL, slug: slug, password: password))
        return try result.get()
    }
}
