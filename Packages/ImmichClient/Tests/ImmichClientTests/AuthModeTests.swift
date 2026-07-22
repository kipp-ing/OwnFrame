import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// @covers FR-100-02
@Test func apiKeyAuthSetsHeaderAndDoesNotAppendKeyQuery() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    // v3 (130): an API-key album lists assets via POST /api/search/metadata.
    let transport = MockTransport(result: .success((try searchData(), response(url: baseURL))))
    let client = ImmichClient(
        config: ServerConfig(baseURL: baseURL, auth: .apiKey("secret-api-key")),
        transport: transport
    )

    _ = try await client.assets(albumID: "album-1")

    let request = try await #require(transport.recordedRequests.only)
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret-api-key")
    #expect(queryValue("key", in: request.url) == nil)
}

@Test func shareKeyAuthAppendsKeyQueryAndDoesNotSetAPIKeyHeader() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    // v3 (130/M2): a shared-link album lists assets via POST /api/search/metadata (?key=), same
    // pager as the API-key path — just authenticated by the key query instead of the header.
    let transport = MockTransport(result: .success((try searchData(), response(url: baseURL))))
    let client = ImmichClient(
        config: ServerConfig(baseURL: baseURL, auth: .shareKey("shared-bearer-key")),
        transport: transport
    )

    _ = try await client.assets(albumID: "album-1")

    let request = try await #require(transport.recordedRequests.only)
    #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
    #expect(queryValue("key", in: request.url) == "shared-bearer-key")
}

@Test func shareKeyAuthPreservesEndpointQueryItems() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(result: .success((Data([1, 2, 3]), response(url: baseURL))))
    let client = ImmichClient(
        config: ServerConfig(baseURL: baseURL, auth: .shareKey("shared-bearer-key")),
        transport: transport
    )

    _ = try await client.preview(assetID: "asset-1")

    let request = try await #require(transport.recordedRequests.only)
    #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
    #expect(queryValue("key", in: request.url) == "shared-bearer-key")
    #expect(queryValue("size", in: request.url) == "preview")
}

// @covers FR-110-08
@Test func shareKeyAuthAppliesToAlbumsAssetInfoAndOriginalRequests() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))

    try await assertShareKeyRequest(
        baseURL: baseURL,
        responseData: try #require("[]".data(using: .utf8)),
        expectedPath: "/api/albums"
    ) { client in
        _ = try await client.albums()
    }

    try await assertShareKeyRequest(
        baseURL: baseURL,
        responseData: try #require(#"{"id":"asset-1"}"#.data(using: .utf8)),
        expectedPath: "/api/assets/asset-1"
    ) { client in
        _ = try await client.assetInfo(assetID: "asset-1")
    }

    try await assertShareKeyRequest(
        baseURL: baseURL,
        responseData: Data([1, 2, 3]),
        expectedPath: "/api/assets/asset-1/original"
    ) { client in
        _ = try await client.original(assetID: "asset-1")
    }
}

// v3 empty page for the metadata-search branch of assets() (both API-key and shared-link).
private func searchData() throws -> Data {
    try #require(#"{"assets":{"items":[],"nextPage":null}}"#.data(using: .utf8))
}

private func response(url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

private func queryValue(_ name: String, in url: URL?) -> String? {
    guard let url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == name }?
        .value
}

private func assertShareKeyRequest(
    baseURL: URL,
    responseData: Data,
    expectedPath: String,
    operation: (ImmichClient) async throws -> Void
) async throws {
    let transport = MockTransport(result: .success((responseData, response(url: baseURL))))
    let client = ImmichClient(
        config: ServerConfig(baseURL: baseURL, auth: .shareKey("shared-bearer-key")),
        transport: transport
    )

    try await operation(client)

    let request = try await #require(transport.recordedRequests.only)
    #expect(request.url?.path == expectedPath)
    #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
    #expect(queryValue("key", in: request.url) == "shared-bearer-key")
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
