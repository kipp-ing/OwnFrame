import Foundation
import ImmichClient
import Testing
@testable import OnboardingKit

// Topic 1000 (US2, tvOS onboarding): picking an album must never dead-end on a duplicate
// label — an existing source for the same album is reused (and activated), and a genuinely
// new source gets a uniquified label instead of a silent rejection.

@MainActor
@Test func activateAlbumSourceAddsAndActivatesANewAlbum() {
    let store = InMemorySourceLibraryStore()
    let viewModel = makeActivateViewModel(store: store)

    let id = viewModel.activateAlbumSource(albumID: "album-1", label: "Family")

    #expect(id != nil)
    #expect(viewModel.sources.count == 1)
    #expect(viewModel.sources[0].kind == .album(albumID: "album-1"))
    #expect(store.load().activeID == id)
}

@MainActor
@Test func activateAlbumSourceReusesAnExistingSourceForTheSameAlbum() {
    var seeded = SourceLibrary()
    seeded.add(Source(id: "existing", label: "Family", kind: .album(albumID: "album-1")))
    seeded.add(Source(id: "other", label: "Trips", kind: .album(albumID: "album-2")))
    var switched: [String] = []
    let store = InMemorySourceLibraryStore(library: seeded)
    // Mirror the app-level onSwitchActive contract: persist the active change, then the
    // view model reloads it (setActive itself deliberately does not persist).
    let viewModel = makeActivateViewModel(store: store) { id in
        var library = store.load()
        library.setActive(id: id)
        store.save(library)
        switched.append(id)
    }

    // Make "other" active first so reactivating "existing" is an actual switch.
    viewModel.setActive(id: "other")
    let id = viewModel.activateAlbumSource(albumID: "album-1", label: "Family")

    #expect(id == "existing")
    #expect(viewModel.sources.count == 2)
    #expect(switched.last == "existing")
}

@MainActor
@Test func activateAlbumSourceUniquifiesADuplicateLabelForADifferentAlbum() {
    var seeded = SourceLibrary()
    seeded.add(Source(id: "existing", label: "Family", kind: .album(albumID: "album-1")))
    let store = InMemorySourceLibraryStore(library: seeded)
    let viewModel = makeActivateViewModel(store: store)

    let id = viewModel.activateAlbumSource(albumID: "album-2", label: "Family")

    #expect(id != nil)
    #expect(id != "existing")
    #expect(viewModel.sources.count == 2)
    #expect(viewModel.sources.map(\.label).sorted() == ["Family", "Family 2"])
    #expect(viewModel.errorMessage == nil)
}

@MainActor
@Test func activateAlbumSourceRejectsAnEmptyLabelAndAlbumFallbackApplies() {
    let store = InMemorySourceLibraryStore()
    let viewModel = makeActivateViewModel(store: store)

    let id = viewModel.activateAlbumSource(albumID: "album-1", label: "   ")

    // An all-whitespace label falls back to the album id so the pick still lands.
    #expect(id != nil)
    #expect(viewModel.sources.count == 1)
    #expect(viewModel.sources[0].label == "album-1")
}

@MainActor
private func makeActivateViewModel(
    store: InMemorySourceLibraryStore = InMemorySourceLibraryStore(),
    onSwitchActive: @escaping (String) -> Void = { _ in }
) -> SourceLibraryViewModel {
    SourceLibraryViewModel(
        store: store,
        secretStore: InMemorySharedLinkSecretStore(),
        resolver: UnusedResolver(),
        onSwitchActive: onSwitchActive
    )
}

/// Album activation never touches the resolver; fail loudly if it ever does.
private struct UnusedResolver: SharedLinkResolving {
    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        Issue.record("activateAlbumSource must not resolve links")
        throw ImmichError.invalidResponse
    }
}
