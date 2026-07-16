import Foundation
import Testing
@testable import OnboardingKit

@Test func sourceLibraryFirstAddBecomesActive() {
    var library = SourceLibrary()
    let source = Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1"))

    library.add(source)

    #expect(library.sources == [source])
    #expect(library.activeID == "source-1")
    #expect(library.active == source)
}

@Test func sourceLibraryRejectsDuplicateLabels() {
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))

    library.add(Source(id: "source-2", label: "Family", kind: .album(albumID: "album-2")))

    #expect(library.sources.map(\.id) == ["source-1"])
}

@Test func sourceLibraryRemoveActivePromotesFirstRemainingSource() {
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))
    library.add(Source(id: "source-2", label: "Travel", kind: .album(albumID: "album-2")))
    library.setActive(id: "source-2")

    library.remove(id: "source-2")

    #expect(library.sources.map(\.id) == ["source-1"])
    #expect(library.activeID == "source-1")
}

@Test func sourceLibraryRemoveActivePromotesNextRemainingSourceWhenAvailable() {
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))
    library.add(Source(id: "source-2", label: "Travel", kind: .album(albumID: "album-2")))
    library.add(Source(id: "source-3", label: "Shared", kind: .sharedLink(baseURL: URL(string: "https://photos.example.test")!, slug: "shared")))
    library.setActive(id: "source-2")

    library.remove(id: "source-2")

    #expect(library.sources.map(\.id) == ["source-1", "source-3"])
    #expect(library.activeID == "source-3")
}

@Test func sourceLibraryRemoveLastActiveClearsActiveID() {
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))

    library.remove(id: "source-1")

    #expect(library.sources.isEmpty)
    #expect(library.activeID == nil)
}

@Test func sourceLibraryDecodingRestoresActiveInvariant() throws {
    let json = """
    {
      "sources": [
        { "id": "source-1", "label": "Family", "kind": { "album": { "albumID": "album-1" } } }
      ],
      "activeID": "missing"
    }
    """

    let library = try JSONDecoder().decode(SourceLibrary.self, from: Data(json.utf8))

    #expect(library.activeID == "source-1")
}

@Test func sourceLibraryMovesSourcesWithoutChangingActive() {
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))
    library.add(Source(id: "source-2", label: "Travel", kind: .album(albumID: "album-2")))
    library.add(Source(id: "source-3", label: "Shared", kind: .sharedLink(baseURL: URL(string: "https://photos.example.test")!, slug: "shared")))
    library.setActive(id: "source-2")

    library.move(from: IndexSet(integer: 2), to: 0)

    #expect(library.sources.map(\.id) == ["source-3", "source-1", "source-2"])
    #expect(library.activeID == "source-2")
}

@Test func sourceLibraryRenameEnforcesUniqueNonEmptyLabel() {
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))
    library.add(Source(id: "source-2", label: "Travel", kind: .album(albumID: "album-2")))

    library.rename(id: "source-2", to: "Family")
    #expect(library.sources[1].label == "Travel")

    library.rename(id: "source-2", to: "")
    #expect(library.sources[1].label == "Travel")

    library.rename(id: "source-2", to: "Summer")
    #expect(library.sources[1].label == "Summer")
}

@Test func sourceLibrarySetActiveIgnoresUnknownIDs() {
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))

    library.setActive(id: "missing")

    #expect(library.activeID == "source-1")
}

@Test func restartStrategyAlbumToAlbumSwapsAlbumOnly() {
    let previous = Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1"))
    let next = Source(id: "source-2", label: "Travel", kind: .album(albumID: "album-2"))

    #expect(SourceLibrary.restartStrategy(from: previous, to: next) == .switchAlbum(albumID: "album-2"))
}

@Test func restartStrategyRebuildsWhenSharedLinkInvolved() {
    let album = Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1"))
    let link = Source(id: "source-2", label: "Shared", kind: .sharedLink(baseURL: URL(string: "https://photos.example.test")!, slug: "shared"))
    let otherLink = Source(id: "source-3", label: "Other", kind: .sharedLink(baseURL: URL(string: "https://photos.example.test")!, slug: "other"))

    #expect(SourceLibrary.restartStrategy(from: album, to: link) == .rebuild)
    #expect(SourceLibrary.restartStrategy(from: link, to: album) == .rebuild)
    #expect(SourceLibrary.restartStrategy(from: link, to: otherLink) == .rebuild)
}

@Test func restartStrategyRebuildsWithoutPreviousActiveSource() {
    let next = Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1"))

    #expect(SourceLibrary.restartStrategy(from: nil, to: next) == .rebuild)
}

@Test func updateActiveAlbumIDRepointsActiveAlbumSource() {
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1")))

    library.updateActiveAlbumID("album-9")

    #expect(library.active?.kind == .album(albumID: "album-9"))
    #expect(library.sources[0].label == "Family")
}

@Test func updateActiveAlbumIDIgnoresSharedLinkActiveSource() {
    var library = SourceLibrary()
    let link = Source(id: "source-1", label: "Shared", kind: .sharedLink(baseURL: URL(string: "https://photos.example.test")!, slug: "shared"))
    library.add(link)

    library.updateActiveAlbumID("album-9")

    #expect(library.active == link)
}

// MARK: - Photo library source kind (900, FR-900-02 / R11)

@Test func sourceKindPhotoLibraryCodableRoundTripsAlongsideExistingKinds() throws {
    let source = Source(id: "source-1", label: "Selected Photos", kind: .photoLibrary(collectionID: "selected-photos"))

    let data = try JSONEncoder().encode(source)
    let decoded = try JSONDecoder().decode(Source.self, from: data)

    #expect(decoded == source)
    #expect(decoded.kind == .photoLibrary(collectionID: "selected-photos"))
    // Additive wire format: the case name keys a nested collectionID (parity with `album`).
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"photoLibrary\""))
    #expect(json.contains("\"collectionID\""))
}

@Test func sourceLibraryDecodesPreExistingKindsAfterPhotoLibraryAddition() throws {
    // A library persisted before the photoLibrary case existed (album + shared link only, in
    // the exact stored format) MUST still decode unchanged — the new case is additive.
    let json = """
    {
      "sources": [
        { "id": "source-1", "label": "Family", "kind": { "album": { "albumID": "album-1" } } },
        { "id": "source-2", "label": "Shared", "kind": { "sharedLink": { "baseURL": "https://photos.example.test", "slug": "summer" } } }
      ],
      "activeID": "source-1"
    }
    """

    let library = try JSONDecoder().decode(SourceLibrary.self, from: Data(json.utf8))

    #expect(library.sources.map(\.id) == ["source-1", "source-2"])
    #expect(library.sources[0].kind == .album(albumID: "album-1"))
    #expect(library.sources[1].kind == .sharedLink(baseURL: URL(string: "https://photos.example.test")!, slug: "summer"))
    #expect(library.activeID == "source-1")
}

@Test func sourceKindPhotoLibraryEqualityFollowsCollectionID() {
    // Mirrors the existing kinds: equality is by associated value; the same string does not
    // make a photoLibrary source equal to an album source.
    #expect(SourceKind.photoLibrary(collectionID: "col-1") == .photoLibrary(collectionID: "col-1"))
    #expect(SourceKind.photoLibrary(collectionID: "col-1") != .photoLibrary(collectionID: "col-2"))
    #expect(SourceKind.photoLibrary(collectionID: "album-1") != .album(albumID: "album-1"))
}
