import Foundation
import ImmichClient
import Testing
@testable import OnboardingKit

// @covers FR-210-20
@Test func albumSearchEmptyQueryReturnsAllAlbumsInOriginalOrder() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: "")

    #expect(filtered.map(\.id) == ["munich", "summer-2024", "summer-2023", "archive", "nil-metadata"])
}

@Test func albumSearchWhitespaceOnlyQueryReturnsAllAlbumsInOriginalOrder() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: " \n\t ")

    #expect(filtered.map(\.id) == ["munich", "summer-2024", "summer-2023", "archive", "nil-metadata"])
}

// @covers FR-210-19
@Test func albumSearchMatchesNameSubstringCaseInsensitively() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: "URLAUB")

    #expect(filtered.map(\.id) == ["munich"])
}

// @covers FR-210-19
@Test func albumSearchMatchesNameSubstringDiacriticInsensitively() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: "munchen")

    #expect(filtered.map(\.id) == ["munich"])
}

// @covers FR-210-19
@Test func albumSearchMatchesUTCYearAndExcludesOtherYears() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: "2024")

    #expect(filtered.map(\.id) == ["munich", "summer-2024"])
}

// @covers FR-210-19
@Test func albumSearchMatchesAssetCount() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: "120")

    #expect(filtered.map(\.id) == ["munich"])
}

// @covers FR-210-20
@Test func albumSearchNilDateAndCountStillMatchesByName() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: "loose")

    #expect(filtered.map(\.id) == ["nil-metadata"])
}

@Test func albumSearchNilDateAndCountIsExcludedByNonMatchingQuery() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: "2024")

    #expect(filtered.map(\.id).contains("nil-metadata") == false)
}

@Test func albumSearchNoMatchReturnsEmptyArray() {
    let albums = albumSearchFixtures()

    let filtered = AlbumSearch.filter(albums, query: "does-not-exist")

    #expect(filtered.isEmpty)
}

private func albumSearchFixtures() -> [Album] {
    [
        Album(
            id: "munich",
            name: "München Urlaub",
            assetCount: 120,
            startDate: Date(timeIntervalSince1970: 1_718_452_800),
            endDate: Date(timeIntervalSince1970: 1_718_452_800)
        ),
        Album(
            id: "summer-2024",
            name: "Summer",
            assetCount: 42,
            startDate: Date(timeIntervalSince1970: 1_718_452_800)
        ),
        Album(
            id: "summer-2023",
            name: "Summer",
            assetCount: 24,
            startDate: Date(timeIntervalSince1970: 1_686_830_400)
        ),
        Album(id: "archive", name: "Archive", assetCount: 7),
        Album(id: "nil-metadata", name: "Loose Ends"),
    ]
}
