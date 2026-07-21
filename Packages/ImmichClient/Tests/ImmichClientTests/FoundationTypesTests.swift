import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// @covers FR-100-01
@Test func serverConfigStoresBaseURLAndAPIKey() throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let apiKey = "test-api-key"

    let config = ServerConfig(baseURL: baseURL, apiKey: apiKey)

    #expect(config.baseURL == baseURL)
    #expect(config.apiKey == apiKey)
}

@Test func immichErrorCasesAreEquatableAndPairwiseDistinct() {
    #expect(ImmichError.unauthorized == .unauthorized)
    #expect(ImmichError.unreachable == .unreachable)
    #expect(ImmichError.invalidResponse == .invalidResponse)

    #expect(ImmichError.unauthorized != .unreachable)
    #expect(ImmichError.unauthorized != .invalidResponse)
    #expect(ImmichError.unreachable != .invalidResponse)
}

@Test func mockTransportReturnsConfiguredResponseAndRecordsRequest() async throws {
    let url = try #require(URL(string: "https://photos.example.test/api/albums"))
    let responseData = try #require("{}".data(using: .utf8))
    let response = try #require(HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let request = URLRequest(url: url)

    let (data, urlResponse) = try await transport.data(for: request)

    #expect(data == responseData)
    #expect(urlResponse.url == response.url)
    #expect(await transport.recordedRequests == [request])
}

@Test func mockTransportThrowsConfiguredErrorAndRecordsRequest() async throws {
    let url = try #require(URL(string: "https://photos.example.test/api/albums"))
    let expectedError = URLError(.timedOut)
    let transport = MockTransport(result: .failure(expectedError))
    let request = URLRequest(url: url)

    do {
        _ = try await transport.data(for: request)
        Issue.record("Expected MockTransport to throw")
    } catch let error as URLError {
        #expect(error.code == expectedError.code)
    }

    #expect(await transport.recordedRequests == [request])
}
