import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// MARK: - T006: v3 metadata-search response DTO (POST /api/search/metadata)

@Test func searchResponseDecodesItemsTypeAndNextPageToken() throws {
    let json = """
    {
        "assets": {
            "total": 5,
            "count": 2,
            "items": [
                { "id": "a1", "type": "IMAGE" },
                { "id": "a2", "type": "VIDEO" }
            ],
            "nextPage": "2"
        }
    }
    """
    let decoded = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))

    #expect(decoded.assets.items.map(\.id) == ["a1", "a2"])
    #expect(decoded.assets.items[0].type == "IMAGE")
    #expect(decoded.assets.items[1].type == "VIDEO")
    #expect(decoded.assets.nextPage == "2")
}

@Test func searchResponseDecodesNullNextPageAsNilAndEmptyItems() throws {
    let json = #"{ "assets": { "total": 0, "count": 0, "items": [], "nextPage": null } }"#

    let decoded = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))

    #expect(decoded.assets.items.isEmpty)
    #expect(decoded.assets.nextPage == nil)
}

@Test func metadataSearchRequestEncodesAlbumFilterPagingAndImageType() throws {
    let request = MetadataSearchRequest(albumIds: ["album-1"], type: "IMAGE", order: "desc", page: 1, size: 1000)

    let data = try JSONEncoder().encode(request)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["albumIds"] as? [String] == ["album-1"])
    #expect(object["type"] as? String == "IMAGE")
    #expect(object["order"] as? String == "desc")
    #expect(object["page"] as? Int == 1)
    #expect(object["size"] as? Int == 1000)
}

// MARK: - T007: the pager follows the nextPage token across pages

@Test func assetsPageThroughMetadataSearchUntilNextPageIsNil() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/search/metadata"))
    let response = try #require(HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil))
    let page1 = Data(#"{"assets":{"items":[{"id":"a1","type":"IMAGE"}],"nextPage":"2"}}"#.utf8)
    let page2 = Data(#"{"assets":{"items":[{"id":"a2","type":"IMAGE"}],"nextPage":null}}"#.utf8)
    let transport = MockTransport(sequence: [.success((page1, response)), .success((page2, response))])
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, apiKey: "secret"), transport: transport)

    let assets = try await client.assets(albumID: "album-1")

    #expect(assets.map(\.id) == ["a1", "a2"])
    let requests = await transport.recordedRequests
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/search/metadata" })
    #expect(try bodyPage(requests[0]) == 1)
    #expect(try bodyPage(requests[1]) == 2)
}

// MARK: - T008a: a shared-link source lists its assets from POST /api/search/metadata (?key=)

// v3/M2 (validated live against 3.0.2): for an ALBUM share, `/api/shared-links/me` returns
// `assets: []` — the assets are NOT embedded. The share `key` DOES authorize
// `POST /api/search/metadata`, so a shared link pages its album exactly like an API key,
// only authenticating with the `?key=` query instead of the `x-api-key` header.
@Test func sharedLinkSourceListsAssetsViaMetadataSearchWithKeyQuery() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/search/metadata"))
    let responseData = Data(#"{"assets":{"items":[{"id":"s1","type":"IMAGE"},{"id":"s2","type":"VIDEO"}],"nextPage":null}}"#.utf8)
    let response = try #require(HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil))
    let transport = MockTransport(result: .success((responseData, response)))
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, auth: .shareKey("share-key")), transport: transport)

    let assets = try await client.assets(albumID: "album-42")

    #expect(assets.map(\.id) == ["s1", "s2"])
    let request = try await #require(transport.recordedRequests.only)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/search/metadata")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
    let key = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "key" }?.value
    #expect(key == "share-key")
    // The resolved album ID is honored, not ignored (the `/me` path silently dropped it).
    let body = try #require(request.httpBody)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["albumIds"] as? [String] == ["album-42"])
}

private func bodyPage(_ request: URLRequest) throws -> Int? {
    let body = try #require(request.httpBody)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    return object["page"] as? Int
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
