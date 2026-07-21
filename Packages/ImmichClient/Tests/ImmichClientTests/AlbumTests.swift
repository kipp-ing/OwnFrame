import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// @covers FR-100-09
@Test func albumJSONDecodesAlbumNameAsName() throws {
    let json = """
    [
        {
            "id": "album-1",
            "albumName": "Family"
        },
        {
            "id": "album-2",
            "albumName": ""
        }
    ]
    """
    let data = try #require(json.data(using: .utf8))

    let albums = try JSONDecoder().decode([Album].self, from: data)

    #expect(albums.count == 2)
    #expect(albums[0].id == "album-1")
    #expect(albums[0].name == "Family")
    #expect(albums[1].id == "album-2")
    #expect(albums[1].name == "")
}

// @covers FR-100-02
@Test func albumsSendsGetRequestWithAPIKeyHeader() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/albums"))
    let responseData = try #require("[]".data(using: .utf8))
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    _ = try await client.albums()

    let requests = await transport.recordedRequests
    let request = try #require(requests.only)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/albums")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == config.apiKey)
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
