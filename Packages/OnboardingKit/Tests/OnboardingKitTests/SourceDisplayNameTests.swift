// SourceDisplayNameTests.swift — 120 T037 (FR-120-13, #61).
//
// A source's display name — the label shown to a person or returned to another app — is never
// a raw host, a URL or an album id. One pure function maps such stored labels to a neutral
// localized placeholder at display time; it never writes the library.

import Foundation
import ImmichClient
import Testing
@testable import OnboardingKit

private let linkBaseURL = URL(string: "https://bilder.example.org")!
private let albumID = "7f1c2d3e-album"

private func link(_ label: String) -> Source {
    Source(label: label, kind: .sharedLink(baseURL: linkBaseURL, slug: "geo2026"))
}

private func album(_ label: String) -> Source {
    Source(label: label, kind: .album(albumID: albumID))
}

// MARK: - Pass-through

// @covers FR-120-13
@Test(arguments: ["Iceland 2021", "Family", "  Geo  "])
func typedOrAlbumNameLabelPassesThroughUnchanged(_ label: String) {
    #expect(SourceLibraryViewModel.displayName(for: link(label)) == label)
    #expect(SourceLibraryViewModel.displayName(for: album(label)) == label)
}

// @covers FR-120-13
@Test(arguments: [
    "Family on bilder.example.org",
    "bilder.example.org photos",
    "bilder.example.org 2a",
    "bilder.example.org2",
])
func labelMerelyContainingTheHostPassesThrough(_ label: String) {
    #expect(SourceLibraryViewModel.displayName(for: link(label)) == label)
}

// @covers FR-120-13
@Test(arguments: ["Beach 2019", "Selected Photos"])
func photoLibraryLabelPassesThrough(_ label: String) {
    let source = Source(label: label, kind: .photoLibrary(collectionID: "col-1"))
    #expect(SourceLibraryViewModel.displayName(for: source) == label)
}

// MARK: - Link → "Shared album"

// @covers FR-120-13, FR-310-16
@Test(arguments: [
    "bilder.example.org",
    "BILDER.Example.ORG",
    "  bilder.example.org  ",
    "bilder.example.org 2",
    "Bilder.example.org 12",
])
func sharedLinkHostLabelMapsToTheLinkPlaceholder(_ label: String) {
    #expect(SourceLibraryViewModel.displayName(for: link(label)) == SourceLibraryViewModel.sharedAlbumPlaceholder)
}

// @covers FR-120-13
@Test(arguments: ["https://bilder.example.org/s/geo2026", "HTTP://bilder.example.org", "Https://other.example"])
func urlShapedLinkLabelMapsToTheLinkPlaceholder(_ label: String) {
    #expect(SourceLibraryViewModel.displayName(for: link(label)) == SourceLibraryViewModel.sharedAlbumPlaceholder)
}

// @covers FR-120-13
@Test(arguments: ["", "   ", "\n"])
func blankLinkLabelMapsToTheLinkPlaceholder(_ label: String) {
    #expect(SourceLibraryViewModel.displayName(for: link(label)) == SourceLibraryViewModel.sharedAlbumPlaceholder)
}

// MARK: - Immich album → "Immich album"

// @covers FR-120-13
@Test(arguments: [albumID, "\(albumID) 2", " \(albumID) 3 "])
func albumIDLabelMapsToTheAlbumPlaceholder(_ label: String) {
    #expect(SourceLibraryViewModel.displayName(for: album(label)) == SourceLibraryViewModel.immichAlbumPlaceholder)
}

// @covers FR-120-13
@Test(arguments: ["https://photos.example/albums/7f1c", "http://photos.example"])
func urlShapedAlbumLabelMapsToTheAlbumPlaceholder(_ label: String) {
    #expect(SourceLibraryViewModel.displayName(for: album(label)) == SourceLibraryViewModel.immichAlbumPlaceholder)
}

// @covers FR-120-13
@Test(arguments: ["", "  "])
func blankAlbumLabelMapsToTheAlbumPlaceholder(_ label: String) {
    #expect(SourceLibraryViewModel.displayName(for: album(label)) == SourceLibraryViewModel.immichAlbumPlaceholder)
}

// @covers FR-120-13
@Test func placeholdersAreNonEmptyDistinctAndNeverAHost() {
    let linkPlaceholder = SourceLibraryViewModel.sharedAlbumPlaceholder
    let albumPlaceholder = SourceLibraryViewModel.immichAlbumPlaceholder
    #expect(!linkPlaceholder.isEmpty)
    #expect(!albumPlaceholder.isEmpty)
    #expect(linkPlaceholder != albumPlaceholder)
    #expect(linkPlaceholder != linkBaseURL.host)
}

// MARK: - Pure: never writes the library

// @covers FR-120-13
@MainActor
@Test func displayNameNeverWritesTheLibrary() {
    var seeded = SourceLibrary()
    seeded.add(link("bilder.example.org"))
    seeded.add(album(albumID))
    seeded.add(link("Iceland 2021"))
    let store = CountingSourceLibraryStore(library: seeded)
    let viewModel = SourceLibraryViewModel(
        store: store,
        secretStore: InMemorySharedLinkSecretStore(),
        resolver: UnusedDisplayNameResolver()
    )

    let names = viewModel.sources.map(SourceLibraryViewModel.displayName(for:))

    #expect(names.count == 3)
    #expect(store.saveCount == 0)
    #expect(store.clearCount == 0)
    #expect(store.load() == seeded)
    #expect(viewModel.sources.map(\.label) == ["bilder.example.org", albumID, "Iceland 2021"])
}

// MARK: - Catalog (SourceVocabularyCatalogTests pattern)

// @covers FR-120-13, FR-9000-26
@Test func placeholderKeysAreTranslatedInTheOnboardingKitCatalog() throws {
    let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // OnboardingKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // OnboardingKit
        .appendingPathComponent("Sources/OnboardingKit/Localizable.xcstrings")
    let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])

    func unit(_ key: String, _ language: String) throws -> (state: String?, value: String?) {
        let entry = try #require(strings[key] as? [String: Any], "missing catalog key \"\(key)\"")
        let localizations = try #require(entry["localizations"] as? [String: Any], "\"\(key)\" has no localizations")
        let localization = try #require(localizations[language] as? [String: Any], "\"\(key)\" has no \(language)")
        let stringUnit = try #require(localization["stringUnit"] as? [String: Any])
        return (stringUnit["state"] as? String, stringUnit["value"] as? String)
    }

    let linkEN = try unit("Shared album", "en")
    #expect(linkEN.state == "translated")
    #expect(linkEN.value == "Shared album")
    let linkDE = try unit("Shared album", "de")
    #expect(linkDE.state == "translated")
    // The German value is pinned in the catalog itself (FR-120-13); German stays out of Swift.
    #expect(linkDE.value?.hasSuffix(" Album") == true)
    #expect(linkDE.value != "Shared album")

    let albumEN = try unit("Immich album", "en")
    #expect(albumEN.state == "translated")
    #expect(albumEN.value == "Immich album")
    let albumDE = try unit("Immich album", "de")
    #expect(albumDE.state == "translated")
    #expect(albumDE.value == "Immich-Album")
}

// MARK: - Fakes

private final class CountingSourceLibraryStore: SourceLibraryStore, @unchecked Sendable {
    private var library: SourceLibrary
    private(set) var saveCount = 0
    private(set) var clearCount = 0

    init(library: SourceLibrary) {
        self.library = library
    }

    func load() -> SourceLibrary {
        library
    }

    func save(_ library: SourceLibrary) {
        saveCount += 1
        self.library = library
    }

    func clear() {
        clearCount += 1
        library = SourceLibrary()
    }
}

private struct UnusedDisplayNameResolver: SharedLinkResolving {
    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil)
    }
}
