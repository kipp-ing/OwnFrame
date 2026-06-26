import Foundation
import Testing
@testable import ImmichClient

@Test func albumDecodesAssetCountAndDateRange() throws {
    let json = """
    [
        {
            "id": "album-1",
            "albumName": "Family",
            "assetCount": 42,
            "startDate": "2024-06-01T00:00:00.000Z",
            "endDate": "2024-08-31T23:59:59.000Z"
        }
    ]
    """
    let data = try #require(json.data(using: .utf8))

    let albums = try JSONDecoder().decode([Album].self, from: data)

    let album = try #require(albums.first)
    #expect(album.id == "album-1")
    #expect(album.name == "Family")
    #expect(album.assetCount == 42)
    #expect(album.startDate == ISO8601DateFormatter().date(from: "2024-06-01T00:00:00Z"))
    #expect(album.endDate == ISO8601DateFormatter().date(from: "2024-08-31T23:59:59Z"))
}

@Test func albumToleratesMissingMetadata() throws {
    // Older servers / the shared-link `me` album reference may carry only id + name.
    let json = """
    [
        {
            "id": "album-2",
            "albumName": "Travel"
        }
    ]
    """
    let data = try #require(json.data(using: .utf8))

    let albums = try JSONDecoder().decode([Album].self, from: data)

    let album = try #require(albums.first)
    #expect(album.assetCount == nil)
    #expect(album.startDate == nil)
    #expect(album.endDate == nil)
}

@Test func albumToleratesNullMetadata() throws {
    // Immich emits explicit nulls for albums with no asset date range.
    let json = """
    [
        {
            "id": "album-3",
            "albumName": "Empty",
            "assetCount": 0,
            "startDate": null,
            "endDate": null
        }
    ]
    """
    let data = try #require(json.data(using: .utf8))

    let albums = try JSONDecoder().decode([Album].self, from: data)

    let album = try #require(albums.first)
    #expect(album.assetCount == 0)
    #expect(album.startDate == nil)
    #expect(album.endDate == nil)
}

@Test func albumKeepsBackCompatibleInit() {
    let album = Album(id: "x", name: "Y")
    #expect(album.assetCount == nil)
    #expect(album.startDate == nil)
    #expect(album.endDate == nil)
}
