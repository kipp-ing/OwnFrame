import Foundation
import ImmichClient
import Testing
@testable import OnboardingKit

// Topic 210 (FR-210-28, issue #71): a picker tap only marks an album; Done commits exactly the
// marked albums in one pass, Cancel discards. Nothing persists until the commit.

// MARK: - Marking

// @covers FR-210-28
@Test func albumSelectionToggleMarksAndUnmarks() {
    var selection = AlbumSelection()
    let family = AlbumSelection.Candidate(kind: .album(albumID: "album-1"), label: "Family", position: 0)

    #expect(selection.isEmpty)
    #expect(selection.count == 0)

    selection.toggle(family, in: SourceLibrary())
    #expect(selection.isMarked(.album(albumID: "album-1")))
    #expect(selection.count == 1)
    #expect(!selection.isEmpty)

    selection.toggle(family, in: SourceLibrary())
    #expect(!selection.isMarked(.album(albumID: "album-1")))
    #expect(selection.count == 0)
    #expect(selection.isEmpty)
}

// @covers FR-210-28
@Test func albumSelectionCannotMarkAnAlbumAlreadyInTheLibrary() {
    var library = SourceLibrary()
    library.add(Source(label: "Renamed Family", kind: .album(albumID: "album-1")))
    var selection = AlbumSelection()

    selection.toggle(.init(kind: .album(albumID: "album-1"), label: "Family", position: 0), in: library)

    #expect(!selection.isMarked(.album(albumID: "album-1")))
    #expect(selection.isEmpty)
}

// @covers FR-210-28
@Test func albumSelectionCannotMarkAPhotoLibraryCollectionAlreadyInTheLibrary() {
    var library = SourceLibrary()
    library.add(Source(label: "Beach", kind: .photoLibrary(collectionID: "col-1")))
    var selection = AlbumSelection()

    selection.toggle(.init(kind: .photoLibrary(collectionID: "col-1"), label: "Beach 2019", position: 0), in: library)

    #expect(selection.isEmpty)
}

// @covers FR-210-28
@Test func albumSelectionMarksADifferentAlbumSharingAnExistingLabel() {
    var library = SourceLibrary()
    library.add(Source(label: "Trip", kind: .album(albumID: "album-1")))
    var selection = AlbumSelection()

    selection.toggle(.init(kind: .album(albumID: "album-2"), label: "Trip", position: 1), in: library)

    #expect(selection.isMarked(.album(albumID: "album-2")))
    #expect(selection.count == 1)
}

@Test func albumSelectionIgnoresASharedLinkCandidate() throws {
    var selection = AlbumSelection()
    let url = try #require(URL(string: "https://photos.example.com"))

    selection.toggle(.init(kind: .sharedLink(baseURL: url, slug: "trip"), label: "Trip", position: 0), in: SourceLibrary())

    #expect(selection.isEmpty)
}

// @covers FR-210-28
@Test func albumSelectionOrdersAlbumsBeforePhotoLibraryEachByPosition() {
    var selection = AlbumSelection()
    let library = SourceLibrary()

    selection.toggle(.init(kind: .photoLibrary(collectionID: "col-b"), label: "B", position: 4), in: library)
    selection.toggle(.init(kind: .album(albumID: "album-z"), label: "Z", position: 7), in: library)
    selection.toggle(.init(kind: .photoLibrary(collectionID: "col-a"), label: "A", position: 1), in: library)
    selection.toggle(.init(kind: .album(albumID: "album-y"), label: "Y", position: 2), in: library)

    #expect(selection.marked.map(\.kind) == [
        .album(albumID: "album-y"),
        .album(albumID: "album-z"),
        .photoLibrary(collectionID: "col-a"),
        .photoLibrary(collectionID: "col-b"),
    ])
}

// @covers FR-210-28
@Test func albumSelectionMarkSurvivesASearchFilterChange() {
    var selection = AlbumSelection()
    let library = SourceLibrary()

    // Marked from the unfiltered list, then the filter changes and another row is tapped.
    selection.toggle(.init(kind: .album(albumID: "album-5"), label: "Garden", position: 5), in: library)
    selection.toggle(.init(kind: .album(albumID: "album-1"), label: "Gardening", position: 1), in: library)

    #expect(selection.isMarked(.album(albumID: "album-5")))
    #expect(selection.isMarked(.album(albumID: "album-1")))
    #expect(selection.count == 2)
}

// MARK: - Commit / discard

@MainActor
// @covers FR-210-28
@Test func albumSelectionCommitAddsExactlyTheMarkedSourcesInOrder() {
    let store = RecordingSourceLibraryStore()
    let viewModel = makeSelectionViewModel(store: store)
    var selection = AlbumSelection()

    selection.toggle(.init(kind: .photoLibrary(collectionID: "col-1"), label: "Beach", position: 0), in: viewModel.library)
    selection.toggle(.init(kind: .album(albumID: "album-2"), label: "", position: 3), in: viewModel.library)
    selection.toggle(.init(kind: .album(albumID: "album-1"), label: "  Family ", position: 1), in: viewModel.library)

    let added = selection.commit(into: viewModel)

    #expect(added == 3)
    #expect(viewModel.sources.map(\.kind) == [
        .album(albumID: "album-1"),
        .album(albumID: "album-2"),
        .photoLibrary(collectionID: "col-1"),
    ])
    // An unnamed album is stored under its album id; the display layer maps it to a placeholder.
    #expect(viewModel.sources.map(\.label) == ["Family", "album-2", "Beach"])
    #expect(store.load().sources.map(\.label) == ["Family", "album-2", "Beach"])
    #expect(selection.isEmpty)
    #expect(viewModel.errorMessage == nil)
}

@MainActor
// @covers FR-210-28
@Test func albumSelectionCommitSuffixesACollidingLabel() {
    var seeded = SourceLibrary()
    seeded.add(Source(label: "Trip", kind: .album(albumID: "album-1")))
    let store = RecordingSourceLibraryStore(library: seeded)
    let viewModel = makeSelectionViewModel(store: store)
    var selection = AlbumSelection()

    selection.toggle(.init(kind: .album(albumID: "album-2"), label: "Trip", position: 0), in: viewModel.library)
    selection.toggle(.init(kind: .album(albumID: "album-3"), label: "Trip", position: 1), in: viewModel.library)

    let added = selection.commit(into: viewModel)

    #expect(added == 2)
    #expect(viewModel.sources.map(\.label) == ["Trip", "Trip 2", "Trip 3"])
}

@MainActor
@Test func albumSelectionCommitIntoAnEmptyLibraryActivatesTheFirstSource() {
    var switched: [String] = []
    let viewModel = makeSelectionViewModel(store: RecordingSourceLibraryStore()) { switched.append($0) }
    var selection = AlbumSelection()

    selection.toggle(.init(kind: .album(albumID: "album-2"), label: "Second", position: 2), in: viewModel.library)
    selection.toggle(.init(kind: .album(albumID: "album-1"), label: "First", position: 1), in: viewModel.library)
    selection.commit(into: viewModel)

    #expect(viewModel.activeID == viewModel.sources.first?.id)
    #expect(viewModel.sources.first?.label == "First")
    #expect(switched.isEmpty)
}

@MainActor
// @covers FR-210-28
@Test func albumSelectionMarkingAndDiscardNeverWriteTheStore() {
    let store = RecordingSourceLibraryStore()
    let viewModel = makeSelectionViewModel(store: store)
    var selection = AlbumSelection()

    selection.toggle(.init(kind: .album(albumID: "album-1"), label: "Family", position: 0), in: viewModel.library)
    selection.toggle(.init(kind: .photoLibrary(collectionID: "col-1"), label: "Beach", position: 1), in: viewModel.library)
    #expect(store.saveCount == 0)

    selection.discard()

    #expect(selection.isEmpty)
    #expect(store.saveCount == 0)
    #expect(viewModel.sources.isEmpty)
}

@MainActor
// @covers FR-210-28
@Test func albumSelectionCommitWritesTheStoreExactlyOnce() {
    let store = RecordingSourceLibraryStore()
    let viewModel = makeSelectionViewModel(store: store)
    var selection = AlbumSelection()

    selection.toggle(.init(kind: .album(albumID: "album-1"), label: "Family", position: 0), in: viewModel.library)
    selection.toggle(.init(kind: .album(albumID: "album-2"), label: "Trips", position: 1), in: viewModel.library)
    selection.toggle(.init(kind: .photoLibrary(collectionID: "col-1"), label: "Beach", position: 2), in: viewModel.library)
    selection.commit(into: viewModel)

    #expect(store.saveCount == 1)
    #expect(store.load().sources.count == 3)
}

@MainActor
@Test func albumSelectionCommittingAnEmptySelectionWritesNothing() {
    let store = RecordingSourceLibraryStore()
    let viewModel = makeSelectionViewModel(store: store)
    var selection = AlbumSelection()

    let added = selection.commit(into: viewModel)

    #expect(added == 0)
    #expect(store.saveCount == 0)
}

// MARK: - addSources

@MainActor
@Test func addSourcesSkipsSharedLinksExistingKindsAndBatchRepeats() throws {
    var seeded = SourceLibrary()
    seeded.add(Source(label: "Family", kind: .album(albumID: "album-1")))
    let store = RecordingSourceLibraryStore(library: seeded)
    let viewModel = makeSelectionViewModel(store: store)
    let url = try #require(URL(string: "https://photos.example.com"))

    let added = viewModel.addSources([
        .init(kind: .album(albumID: "album-1"), label: "Family again", position: 0),
        .init(kind: .sharedLink(baseURL: url, slug: "trip"), label: "Trip", position: 1),
        .init(kind: .album(albumID: "album-2"), label: "Trips", position: 2),
        .init(kind: .album(albumID: "album-2"), label: "Trips copy", position: 3),
    ])

    #expect(added == 1)
    #expect(viewModel.sources.map(\.label) == ["Family", "Trips"])
    #expect(store.saveCount == 1)
}

@MainActor
@Test func addSourcesWithNothingNewWritesNothingAndClearsTheError() {
    var seeded = SourceLibrary()
    seeded.add(Source(label: "Family", kind: .album(albumID: "album-1")))
    let store = RecordingSourceLibraryStore(library: seeded)
    let viewModel = makeSelectionViewModel(store: store)
    viewModel.addAlbumSource(albumID: "album-9", label: "Family") // duplicate label ⇒ error
    #expect(viewModel.errorMessage != nil)
    let savesBefore = store.saveCount

    let added = viewModel.addSources([.init(kind: .album(albumID: "album-1"), label: "Family", position: 0)])

    #expect(added == 0)
    #expect(store.saveCount == savesBefore)
    #expect(viewModel.errorMessage == nil)
}

// MARK: - Helpers

@MainActor
private func makeSelectionViewModel(
    store: RecordingSourceLibraryStore,
    onSwitchActive: @escaping (String) -> Void = { _ in }
) -> SourceLibraryViewModel {
    SourceLibraryViewModel(
        store: store,
        secretStore: InMemorySharedLinkSecretStore(),
        resolver: SelectionUnusedResolver(),
        onSwitchActive: onSwitchActive
    )
}

/// Counts `save` calls so a test can assert one persist per committed pass.
private final class RecordingSourceLibraryStore: SourceLibraryStore, @unchecked Sendable {
    private var library: SourceLibrary
    private(set) var saveCount = 0

    init(library: SourceLibrary = SourceLibrary()) {
        self.library = library
    }

    func load() -> SourceLibrary { library }

    func save(_ library: SourceLibrary) {
        saveCount += 1
        self.library = library
    }

    func clear() { library = SourceLibrary() }
}

/// Album selection never touches the resolver; fail loudly if it ever does.
private struct SelectionUnusedResolver: SharedLinkResolving {
    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        Issue.record("album selection must not resolve links")
        throw ImmichError.invalidResponse
    }
}
