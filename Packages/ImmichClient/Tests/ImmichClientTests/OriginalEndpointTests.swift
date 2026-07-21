import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

// @covers FR-100-02, FR-100-13, SC-100-01
@Test func originalSendsGetRequestWithoutSizeQueryAndReturnsRawData() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/assets/asset-1/original"))
    let responseData = Data([0xFF, 0xD8, 0xFF, 0xE0])
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    let original = try await client.original(assetID: "asset-1")

    #expect(original == responseData)

    let requests = await transport.recordedRequests
    let request = try #require(requests.only)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/assets/asset-1/original")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == config.apiKey)
    #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
        .queryItems?
        .contains(where: { $0.name == "size" }) != true)
}

@Test func originalProtocolDefaultDelegatesToPreview() async throws {
    let api = PreviewOnlyImmichAPI(previewData: Data([0x01, 0x02, 0x03]))

    let original = try await api.original(assetID: "asset-1")

    #expect(original == api.previewData)
}

// @covers FR-100-06, SC-100-03
@Test func originalMapsUnauthorizedStatusToUnauthorizedError() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/assets/asset-1/original"))
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 401,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((Data(), response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    await expectImmichError(.unauthorized) {
        _ = try await client.original(assetID: "asset-1")
    }
}

private struct PreviewOnlyImmichAPI: ImmichAPI {
    let previewData: Data

    func serverVersion() async throws -> String {
        "1.0.0"
    }

    func albums() async throws -> [Album] {
        []
    }

    func assets(albumID: String) async throws -> [Asset] {
        []
    }

    func preview(assetID: String) async throws -> Data {
        previewData
    }
}

private func expectImmichError(
    _ expectedError: ImmichError,
    performing operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected \(expectedError), but no error was thrown.")
    } catch let error as ImmichError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Expected \(expectedError), but got \(error).")
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
