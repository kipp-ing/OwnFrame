import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

@Test func albumsMapsUnauthorizedStatusToUnauthorizedError() async throws {
    let client = try makeClient(
        responseData: Data(),
        statusCode: 401
    )

    await expectImmichError(.unauthorized) {
        _ = try await client.albums()
    }
}

@Test func albumsMapsURLErrorToUnreachableError() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(result: .failure(URLError(.timedOut)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    await expectImmichError(.unreachable) {
        _ = try await client.albums()
    }
}

@Test func albumsMapsNonSuccessStatusToInvalidResponseError() async throws {
    let responseData = try #require("[]".data(using: .utf8))
    let client = try makeClient(
        responseData: responseData,
        statusCode: 500
    )

    await expectImmichError(.invalidResponse) {
        _ = try await client.albums()
    }
}

@Test func albumsMapsUndecodableBodyToInvalidResponseError() async throws {
    let responseData = try #require(#"{"unexpected":"shape"}"#.data(using: .utf8))
    let client = try makeClient(
        responseData: responseData,
        statusCode: 200
    )

    await expectImmichError(.invalidResponse) {
        _ = try await client.albums()
    }
}

@Test func serverTooOldCarriesVersionAndIsDistinctFromOtherCases() {
    let tooOld = ImmichError.serverTooOld(version: "2.118.0")
    #expect(tooOld == .serverTooOld(version: "2.118.0"))
    #expect(tooOld != .serverTooOld(version: "3.0.0"))
    #expect(tooOld != .invalidResponse)
    #expect(tooOld != .unreachable)
    #expect(tooOld != .unauthorized)
}

private func makeClient(responseData: Data, statusCode: Int) throws -> ImmichClient {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/albums"))
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    return ImmichClient(config: config, transport: transport)
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
