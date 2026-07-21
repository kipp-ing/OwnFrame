import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// US4 (130): v3 slimmed DTOs decode cleanly — removed fields (owner/ownerId on albums,
// deviceId/deviceAssetId on assets, token on shared links) are never required, and the
// simplified error envelope still yields a message where the client reads one.

// @covers FR-100-09, FR-130-08, SC-130-05
@Test func albumDecodesV3ShapeWithoutOwnerOrAssets() throws {
    // v3 AlbumResponseDto: no owner/ownerId/assets; albumUsers + order present instead.
    let json = """
    {
        "id": "al-1",
        "albumName": "Trip",
        "assetCount": 3,
        "albumUsers": [{ "role": "owner" }],
        "order": "desc",
        "startDate": "2026-01-01T00:00:00.000Z",
        "endDate": "2026-01-02T00:00:00.000Z"
    }
    """
    let album = try JSONDecoder().decode(Album.self, from: Data(json.utf8))

    #expect(album.id == "al-1")
    #expect(album.name == "Trip")
    #expect(album.assetCount == 3)
}

// @covers FR-130-08, SC-130-05
@Test func assetDecodesV3ShapeIgnoringRemovedDeviceFields() throws {
    // v3 AssetResponseDto is rich; Asset reads only id + type and ignores everything else.
    let json = """
    {
        "id": "a1",
        "type": "IMAGE",
        "originalFileName": "x.jpg",
        "checksum": "abc",
        "thumbhash": "zz",
        "visibility": "timeline"
    }
    """
    let asset = try JSONDecoder().decode(Asset.self, from: Data(json.utf8))

    #expect(asset.id == "a1")
    #expect(asset.type == "IMAGE")
}

// @covers FR-130-08, SC-130-05
@Test func assetInfoDecodesV3AssetWithoutDeviceFields() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/assets/a1"))
    let json = """
    {
        "id": "a1",
        "type": "IMAGE",
        "fileCreatedAt": "2026-01-01T00:00:00.000Z",
        "localDateTime": "2026-01-01T00:00:00.000Z",
        "exifInfo": {
            "dateTimeOriginal": "2026-01-01T00:00:00.000Z",
            "city": "Berlin", "state": "BE", "country": "DE"
        }
    }
    """
    let response = try #require(HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil))
    let transport = MockTransport(result: .success((Data(json.utf8), response)))
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, apiKey: "k"), transport: transport)

    let info = try await client.assetInfo(assetID: "a1")

    #expect(info.id == "a1")
    #expect(info.city == "Berlin")
    #expect(info.country == "DE")
}

// @covers FR-130-08
@Test func resolverReadsSimplifiedV3ErrorEnvelopeForInvalidIdentifier() async throws {
    // v3 drops the redundant error/statusCode fields; the resolver still reads `message` to tell
    // an invalid-key/slug 401 from a password challenge (110 key↔slug discrimination).
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let resp = HTTPURLResponse(url: baseURL, statusCode: 401, httpVersion: nil, headerFields: nil)!
    let transport = MockTransport(sequence: [
        .success((Data(#"{"message":"Invalid share key"}"#.utf8), resp)),
        .success((Data(#"{"message":"Invalid share slug"}"#.utf8), resp)),
    ])
    let resolver = SharedLinkResolver(transport: transport)

    await #expect(throws: ImmichError.invalidShareLink) {
        _ = try await resolver.resolve(baseURL: baseURL, slug: "nope", password: nil)
    }
}
