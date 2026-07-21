import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// @covers FR-100-02
@Test func assetInfoSendsGetRequestWithAPIKeyHeaderAndReturnsDecodedInfo() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/assets/asset-1"))
    let responseData = try #require("""
    {
        "id": "asset-1",
        "type": "IMAGE",
        "localDateTime": "2024-06-15T14:30:00.000Z",
        "fileCreatedAt": "2024-06-15T12:30:00.000Z",
        "exifInfo": {
            "dateTimeOriginal": "2024-06-15T14:30:00.000Z",
            "city": "Berlin",
            "state": "Berlin",
            "country": "Germany"
        }
    }
    """.data(using: .utf8))
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    let info = try await client.assetInfo(assetID: "asset-1")
    let expectedTakenAt = try expectedDate("2024-06-15T14:30:00.000Z")

    #expect(info.id == "asset-1")
    #expect(info.takenAt == expectedTakenAt)
    #expect(info.city == "Berlin")
    #expect(info.country == "Germany")

    let requests = await transport.recordedRequests
    let request = try #require(requests.only)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/assets/asset-1")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == config.apiKey)
}

@Test func assetInfoWithoutExifFallsBackToLocalDateTimeAndNilLocation() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/assets/asset-1"))
    let responseData = try #require("""
    {
        "id": "asset-1",
        "type": "IMAGE",
        "localDateTime": "2024-06-15T14:30:00.000Z",
        "fileCreatedAt": "2024-06-15T12:30:00.000Z"
    }
    """.data(using: .utf8))
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    let info = try await client.assetInfo(assetID: "asset-1")
    let expectedTakenAt = try expectedDate("2024-06-15T14:30:00.000Z")

    #expect(info.id == "asset-1")
    #expect(info.takenAt == expectedTakenAt)
    #expect(info.city == nil)
    #expect(info.state == nil)
    #expect(info.country == nil)
}

private func expectedDate(_ string: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return try #require(formatter.date(from: string))
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
