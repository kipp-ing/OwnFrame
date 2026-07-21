import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

@Test func serverVersionReturnsVersionStringAndSendsGetRequest() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/server/version"))
    let responseData = try #require(#"{"major":1,"minor":119,"patch":0}"#.data(using: .utf8))
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    let version = try await client.serverVersion()

    #expect(!version.isEmpty)
    let requests = await transport.recordedRequests
    let request = try #require(requests.only)
    #expect(request.url?.path == "/api/server/version")
    #expect(request.httpMethod == "GET")
}

// @covers FR-100-07
@Test func serverVersionMapsURLErrorToUnreachable() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(result: .failure(URLError(.timedOut)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    await #expect(throws: ImmichError.unreachable) {
        _ = try await client.serverVersion()
    }
}

@Test func serverVersionMapsInvalidResponseToInvalidResponse() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/server/version"))
    let responseData = Data("{}".utf8)
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 500,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((responseData, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    let client = ImmichClient(config: config, transport: transport)

    await #expect(throws: ImmichError.invalidResponse) {
        _ = try await client.serverVersion()
    }
}

// MARK: - Version gate (130 — v3 baseline)

@Test func serverVersionGateClassifiesMajorVersions() {
    #expect(ServerVersionGate.isSupported("3.0.2") == true)
    #expect(ServerVersionGate.isSupported("10.1.0") == true)
    #expect(ServerVersionGate.isSupported("2.118.0") == false)
    // A numeric major is all that matters; a pre-release suffix is tolerated.
    #expect(ServerVersionGate.isSupported("3.0.0-rc.2") == true)
    #expect(ServerVersionGate.majorVersion(from: "2.118.0") == 2)
    // Unknown/unparseable versions never classify as too-old (FR-130-09).
    #expect(ServerVersionGate.isSupported("nonsense") == nil)
    #expect(ServerVersionGate.isSupported("") == nil)
}

@Test func ensureServerSupportedThrowsServerTooOldForMajorBelowThree() async throws {
    let client = try makeVersionClient(major: 2, minor: 118, patch: 0)

    await #expect(throws: ImmichError.serverTooOld(version: "2.118.0")) {
        try await client.ensureServerSupported()
    }
}

@Test func ensureServerSupportedPassesForMajorThreePlus() async throws {
    let client = try makeVersionClient(major: 3, minor: 0, patch: 2)

    try await client.ensureServerSupported()
}

@Test func ensureServerSupportedPropagatesUnreachableRatherThanTooOld() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(result: .failure(URLError(.timedOut)))
    let client = ImmichClient(config: ServerConfig(baseURL: baseURL, apiKey: "secret"), transport: transport)

    await #expect(throws: ImmichError.unreachable) {
        try await client.ensureServerSupported()
    }
}

private func makeVersionClient(major: Int, minor: Int, patch: Int) throws -> ImmichClient {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let requestURL = try #require(URL(string: "https://photos.example.test/api/server/version"))
    let data = Data(#"{"major":\#(major),"minor":\#(minor),"patch":\#(patch)}"#.utf8)
    let response = try #require(HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((data, response)))
    return ImmichClient(config: ServerConfig(baseURL: baseURL, apiKey: "secret"), transport: transport)
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
