import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// v3 (130): an API-key album lists its assets from POST /api/search/metadata; the removed album
// `assets` array is gone. See MetadataSearchTests for paging and the shared-link branch.

// @covers FR-100-02
@Test func assetsFetchesImagesViaMetadataSearchWithAPIKeyHeader() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/search/metadata"))
    let responseData = try #require("""
    {
        "assets": {
            "total": 2, "count": 2, "nextPage": null,
            "items": [
                { "id": "asset-1", "type": "IMAGE" },
                { "id": "asset-2", "type": "IMAGE" }
            ]
        }
    }
    """.data(using: .utf8))
    let response = try #require(HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    let assets = try await client.assets(albumID: "album-1")

    #expect(assets.map(\.id) == ["asset-1", "asset-2"])

    let request = try await #require(transport.recordedRequests.only)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/search/metadata")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == config.apiKey)

    let body = try #require(request.httpBody)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["albumIds"] as? [String] == ["album-1"])
    #expect(object["page"] as? Int == 1)
}

// @covers FR-100-08
@Test func assetsReturnsEmptyArrayForAlbumWithoutAssets() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/search/metadata"))
    let responseData = try #require(#"{"assets":{"total":0,"count":0,"items":[],"nextPage":null}}"#.data(using: .utf8))
    let response = try #require(HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    let assets = try await client.assets(albumID: "empty-album")

    #expect(assets.isEmpty)
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
