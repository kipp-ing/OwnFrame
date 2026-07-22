import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// @covers FR-100-02, FR-100-05, SC-100-01
@Test func previewSendsGetRequestWithPreviewSizeQueryAndReturnsRawData() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/assets/asset-1/thumbnail?size=preview"))
    let responseData = Data([0x89, 0x50, 0x4E, 0x47])
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    let preview = try await client.preview(assetID: "asset-1")

    #expect(preview == responseData)

    let requests = await transport.recordedRequests
    let request = try #require(requests.only)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/assets/asset-1/thumbnail")
    #expect(request.url?.path.hasSuffix("/thumbnail") == true)
    #expect(request.url?.path.contains("asset-1") == true)
    #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
        .queryItems?
        .contains(URLQueryItem(name: "size", value: "preview")) == true)
    #expect(request.value(forHTTPHeaderField: "x-api-key") == config.apiKey)
}

// @covers FR-100-02, FR-100-14, SC-100-01
@Test func thumbnailSendsGetRequestWithThumbnailSizeQueryAndReturnsRawData() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/assets/asset-1/thumbnail?size=thumbnail"))
    let responseData = Data([0x89, 0x50, 0x4E, 0x47])
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    let thumbnail = try await client.thumbnail(assetID: "asset-1")

    #expect(thumbnail == responseData)

    let requests = await transport.recordedRequests
    let request = try #require(requests.only)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/assets/asset-1/thumbnail")
    #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
        .queryItems?
        .contains(URLQueryItem(name: "size", value: "thumbnail")) == true)
    #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
        .queryItems?
        .contains(URLQueryItem(name: "size", value: "preview")) == false)
    #expect(request.value(forHTTPHeaderField: "x-api-key") == config.apiKey)
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
