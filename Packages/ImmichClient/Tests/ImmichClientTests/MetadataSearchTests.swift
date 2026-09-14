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
    let request = MetadataSearchRequest(albumIds: ["album-1"], type: "IMAGE", order: "asc", page: 1, size: 1000)

    let data = try JSONEncoder().encode(request)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["albumIds"] as? [String] == ["album-1"])
    #expect(object["type"] as? String == "IMAGE")
    #expect(object["order"] as? String == "asc")
    #expect(object["page"] as? Int == 1)
    #expect(object["size"] as? Int == 1000)
}

// MARK: - T007: the pager follows the nextPage token across pages

// @covers FR-130-02, SC-130-01
@Test func assetsPageThroughMetadataSearchUntilNextPageIsNil() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let response = okResponse(baseURL)
    let page1 = Data(#"{"assets":{"items":[{"id":"a1","type":"IMAGE"}],"nextPage":"2"}}"#.utf8)
    let page2 = Data(#"{"assets":{"items":[{"id":"a2","type":"IMAGE"}],"nextPage":null}}"#.utf8)
    let transport = MockTransport(sequence: [
        .success((albumLookupData(orderJSON: nil), response)),
        .success((page1, response)),
        .success((page2, response)),
    ])
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, apiKey: "secret"), transport: transport)

    let assets = try await client.assets(albumID: "album-1")

    #expect(assets.map(\.id) == ["a1", "a2"])
    let requests = await transport.recordedRequests
    #expect(requests.count == 3)
    let searches = Array(requests.dropFirst())
    #expect(searches.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/search/metadata" })
    #expect(try bodyPage(searches[0]) == 1)
    #expect(try bodyPage(searches[1]) == 2)
}

// MARK: - T008a: a shared-link source lists its assets from POST /api/search/metadata (?key=)

// v3/M2 (validated live against 3.0.2): for an ALBUM share, `/api/shared-links/me` returns
// `assets: []` — the assets are NOT embedded. The share `key` DOES authorize
// `POST /api/search/metadata`, so a shared link pages its album exactly like an API key,
// only authenticating with the `?key=` query instead of the `x-api-key` header.
// @covers FR-110-08
@Test func sharedLinkSourceListsAssetsViaMetadataSearchWithKeyQuery() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let responseData = Data(#"{"assets":{"items":[{"id":"s1","type":"IMAGE"},{"id":"s2","type":"VIDEO"}],"nextPage":null}}"#.utf8)
    let transport = MockTransport(sequence: [
        .success((albumLookupData(orderJSON: nil), okResponse(baseURL))),
        .success((responseData, okResponse(baseURL))),
    ])
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, auth: .shareKey("share-key")), transport: transport)

    let assets = try await client.assets(albumID: "album-42")

    #expect(assets.map(\.id) == ["s1", "s2"])
    let requests = await transport.recordedRequests
    #expect(requests.count == 2)
    let request = try #require(requests.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/search/metadata")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
    #expect(queryValue("key", in: request.url) == "share-key")
    // The resolved album ID is honored, not ignored (the `/me` path silently dropped it).
    let body = try #require(request.httpBody)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["albumIds"] as? [String] == ["album-42"])
}

// MARK: - 130 Phase 9 (#62): sequential plays the album's own order

/// One order case: the album lookup's raw `order` JSON value (`nil` = key absent) and the
/// `order` every metadata-search page must carry.
struct AlbumOrderCase: Sendable, CustomTestStringConvertible {
    let orderJSON: String?
    let expected: String

    var testDescription: String { "order \(orderJSON ?? "absent") -> \(expected)" }

    static let all: [AlbumOrderCase] = [
        AlbumOrderCase(orderJSON: #""asc""#, expected: "asc"),
        AlbumOrderCase(orderJSON: #""desc""#, expected: "desc"),
        AlbumOrderCase(orderJSON: nil, expected: "desc"),
        AlbumOrderCase(orderJSON: "null", expected: "desc"),
        AlbumOrderCase(orderJSON: #""sideways""#, expected: "desc"),
    ]
}

// @covers FR-130-02, FR-500-06
@Test(arguments: AlbumOrderCase.all)
func apiKeyAlbumPagesInTheAlbumsOwnOrder(_ orderCase: AlbumOrderCase) async throws {
    let requests = try await pageTwoPages(auth: .apiKey("secret-api-key"), orderJSON: orderCase.orderJSON)

    #expect(requests.count == 3)
    let lookup = try #require(requests.first)
    #expect(lookup.httpMethod == "GET")
    #expect(lookup.url?.path == "/api/albums/album-1")
    #expect(queryValue("withoutAssets", in: lookup.url) == "true")
    #expect(lookup.value(forHTTPHeaderField: "x-api-key") == "secret-api-key")
    #expect(queryValue("key", in: lookup.url) == nil)

    let searches = Array(requests.dropFirst())
    #expect(searches.count == 2)
    for search in searches {
        #expect(search.url?.path == "/api/search/metadata")
        #expect(try bodyOrder(search) == orderCase.expected)
    }
}

// @covers FR-130-12, FR-500-06
@Test(arguments: AlbumOrderCase.all)
func sharedLinkAlbumPagesInTheAlbumsOwnOrder(_ orderCase: AlbumOrderCase) async throws {
    let requests = try await pageTwoPages(auth: .shareKey("share-key"), orderJSON: orderCase.orderJSON)

    #expect(requests.count == 3)
    let lookup = try #require(requests.first)
    #expect(lookup.httpMethod == "GET")
    #expect(lookup.url?.path == "/api/albums/album-1")
    #expect(queryValue("withoutAssets", in: lookup.url) == "true")
    #expect(queryValue("key", in: lookup.url) == "share-key")
    #expect(lookup.value(forHTTPHeaderField: "x-api-key") == nil)

    let searches = Array(requests.dropFirst())
    #expect(searches.count == 2)
    for search in searches {
        #expect(search.url?.path == "/api/search/metadata")
        #expect(queryValue("key", in: search.url) == "share-key")
        #expect(search.value(forHTTPHeaderField: "x-api-key") == nil)
        #expect(try bodyOrder(search) == orderCase.expected)
    }
}

// A failed order lookup fails the fetch (into 310's retry) — it never silently becomes `desc`.
// @covers FR-130-02, FR-500-06
@Test func albumOrderLookupTransportFailureThrowsAndIssuesNoSearch() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(sequence: [
        .failure(URLError(.timedOut)),
        .success((emptySearchPage(), okResponse(baseURL))),
    ])
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, apiKey: "secret"), transport: transport)

    await #expect(throws: ImmichError.unreachable) {
        _ = try await client.assets(albumID: "album-1")
    }
    let requests = await transport.recordedRequests
    #expect(requests.count == 1)
    #expect(requests.allSatisfy { $0.url?.path != "/api/search/metadata" })
}

// @covers FR-130-12, FR-500-06
@Test func albumOrderLookupNon2xxThrowsAndIssuesNoSearch() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let notFound = try #require(HTTPURLResponse(url: baseURL, statusCode: 404, httpVersion: nil, headerFields: nil))
    let transport = MockTransport(sequence: [
        .success((Data(#"{"message":"Not found"}"#.utf8), notFound)),
        .success((emptySearchPage(), okResponse(baseURL))),
    ])
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, auth: .shareKey("share-key")), transport: transport)

    await #expect(throws: ImmichError.invalidResponse) {
        _ = try await client.assets(albumID: "album-1")
    }
    let requests = await transport.recordedRequests
    #expect(requests.count == 1)
    #expect(requests.allSatisfy { $0.url?.path != "/api/search/metadata" })
}

// @covers FR-130-02, FR-500-06
@Test func albumOrderLookupUndecodableAlbumThrowsAndIssuesNoSearch() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(sequence: [
        .success((Data(#"{"unexpected":"shape"}"#.utf8), okResponse(baseURL))),
        .success((emptySearchPage(), okResponse(baseURL))),
    ])
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, apiKey: "secret"), transport: transport)

    await #expect(throws: ImmichError.invalidResponse) {
        _ = try await client.assets(albumID: "album-1")
    }
    let requests = await transport.recordedRequests
    #expect(requests.count == 1)
    #expect(requests.allSatisfy { $0.url?.path != "/api/search/metadata" })
}

// MARK: - Helpers

/// Scripts album lookup → page 1 (nextPage "2") → page 2 (last) for `album-1`, returns every request.
private func pageTwoPages(auth: ServerConfig.Auth, orderJSON: String?) async throws -> [URLRequest] {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let page1 = Data(#"{"assets":{"items":[{"id":"a1","type":"IMAGE"}],"nextPage":"2"}}"#.utf8)
    let page2 = Data(#"{"assets":{"items":[{"id":"a2","type":"IMAGE"}],"nextPage":null}}"#.utf8)
    let transport = MockTransport(sequence: [
        .success((albumLookupData(orderJSON: orderJSON), okResponse(baseURL))),
        .success((page1, okResponse(baseURL))),
        .success((page2, okResponse(baseURL))),
    ])
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, auth: auth), transport: transport)

    let assets = try await client.assets(albumID: "album-1")

    #expect(assets.map(\.id) == ["a1", "a2"])
    return await transport.recordedRequests
}

/// A v3 `GET /api/albums/{id}?withoutAssets=true` body; `orderJSON` is the raw JSON value of
/// `order`, or `nil` to omit the key.
private func albumLookupData(orderJSON: String?) -> Data {
    let order = orderJSON.map { #", "order": \#($0)"# } ?? ""
    return Data(#"{"id": "album-1", "albumName": "Trip", "assetCount": 2\#(order)}"#.utf8)
}

private func emptySearchPage() -> Data {
    Data(#"{"assets":{"items":[],"nextPage":null}}"#.utf8)
}

private func okResponse(_ url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

private func bodyPage(_ request: URLRequest) throws -> Int? {
    let body = try #require(request.httpBody)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    return object["page"] as? Int
}

private func bodyOrder(_ request: URLRequest) throws -> String? {
    let body = try #require(request.httpBody)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    return object["order"] as? String
}

private func queryValue(_ name: String, in url: URL?) -> String? {
    guard let url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == name }?
        .value
}
