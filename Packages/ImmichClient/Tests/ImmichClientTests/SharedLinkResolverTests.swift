import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport

@Test func resolverRequestsSharedLinkMeWithKeyFirstAndPasswordAndReturnsResolution() async throws {
    // A `/share/<X>` identifier is the share KEY; the resolver must query `key=` first
    // (querying `slug=` on a key returns 401 "Invalid share key" — the false-password bug).
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    // expiresAt is far-future on purpose: the fixture must never expire.
    let responseData = try #require("""
    {
        "key": "shared-bearer-key",
        "album": {
            "id": "album-1"
        },
        "expiresAt": "2126-01-01T12:00:00.000Z"
    }
    """.data(using: .utf8))
    let transport = MockTransport(result: .success((responseData, httpResponse(url: baseURL, statusCode: 200))))
    let resolver = SharedLinkResolver(transport: transport)

    let resolution = try await resolver.resolve(baseURL: baseURL, slug: "summer", password: "secret-password")

    #expect(resolution.key == "shared-bearer-key")
    #expect(resolution.albumID == "album-1")
    #expect(resolution.expiresAt == isoDate("2126-01-01T12:00:00.000Z"))

    let request = try await #require(transport.recordedRequests.only)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/shared-links/me")
    #expect(queryValue("key", in: request.url) == "summer")
    #expect(queryValue("slug", in: request.url) == nil)
    #expect(queryValue("password", in: request.url) == "secret-password")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
}

// FR-210-06/07 (Finding 1): an "Invalid share key/slug" 401 means the identifier was not
// found — NOT that a password is required. A non-protected `/share/<key>` link must never
// prompt for a password.
@Test func resolverMapsInvalidShareKeyOrSlug401ToInvalidShareLinkNotPasswordRequired() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(sequence: [
        .success((errorBody("Invalid share key"), httpResponse(url: baseURL, statusCode: 401))),
        .success((errorBody("Invalid share slug"), httpResponse(url: baseURL, statusCode: 401))),
    ])
    let resolver = SharedLinkResolver(transport: transport)

    await #expect(throws: ImmichError.invalidShareLink) {
        _ = try await resolver.resolve(baseURL: baseURL, slug: "not-a-real-link", password: nil)
    }
}

// A custom `/s/<slug>` link: the key attempt 401s "Invalid share key"; the resolver falls
// back to `slug=` and resolves.
@Test func resolverFallsBackToSlugWhenKeyIsInvalid() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let okBody = try #require("""
    { "key": "real-key", "album": { "id": "album-7" }, "expiresAt": null }
    """.data(using: .utf8))
    let transport = MockTransport(sequence: [
        .success((errorBody("Invalid share key"), httpResponse(url: baseURL, statusCode: 401))),
        .success((okBody, httpResponse(url: baseURL, statusCode: 200))),
    ])
    let resolver = SharedLinkResolver(transport: transport)

    let resolution = try await resolver.resolve(baseURL: baseURL, slug: "my-trip", password: nil)
    #expect(resolution.key == "real-key")
    #expect(resolution.albumID == "album-7")

    let requests = await transport.recordedRequests
    #expect(requests.count == 2)
    #expect(queryValue("key", in: requests.first?.url) == "my-trip")
    #expect(queryValue("slug", in: requests.last?.url) == "my-trip")
}

// A genuine password challenge (401 whose message is not an invalid-identifier message) is
// still classified as password-required, regardless of the exact server wording.
@Test func resolverMapsPasswordChallenge401ToPasswordRequired() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(result: .success((errorBody("Invalid password"), httpResponse(url: baseURL, statusCode: 401))))
    let resolver = SharedLinkResolver(transport: transport)

    await #expect(throws: ImmichError.passwordRequired) {
        _ = try await resolver.resolve(baseURL: baseURL, slug: "protected", password: nil)
    }
}

@Test func resolverMapsMissingPasswordUnauthorizedToPasswordRequired() async throws {
    try await expectResolverError(statusCode: 401, password: nil, expectedError: .passwordRequired)
}

@Test func resolverMapsWrongPasswordUnauthorizedToWrongPassword() async throws {
    try await expectResolverError(statusCode: 401, password: "wrong", expectedError: .wrongPassword)
}

@Test func resolverMapsNotFoundToInvalidShareLink() async throws {
    try await expectResolverError(statusCode: 404, password: nil, expectedError: .invalidShareLink)
}

@Test func resolverMapsServerSignalledExpiryToShareLinkExpired() async throws {
    try await expectResolverError(statusCode: 410, password: nil, expectedError: .shareLinkExpired)
}

@Test func resolverMapsPastExpiresAtToShareLinkExpired() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let responseData = try #require("""
    {
        "key": "shared-bearer-key",
        "album": {
            "id": "album-1"
        },
        "expiresAt": "2000-01-01T00:00:00.000Z"
    }
    """.data(using: .utf8))
    let transport = MockTransport(result: .success((responseData, httpResponse(url: baseURL, statusCode: 200))))
    let resolver = SharedLinkResolver(transport: transport)

    await #expect(throws: ImmichError.shareLinkExpired) {
        _ = try await resolver.resolve(baseURL: baseURL, slug: "expired", password: nil)
    }
}

@Test func resolverMapsTransportFailureToUnreachable() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(result: .failure(URLError(.timedOut)))
    let resolver = SharedLinkResolver(transport: transport)

    await #expect(throws: ImmichError.unreachable) {
        _ = try await resolver.resolve(baseURL: baseURL, slug: "summer", password: nil)
    }
}

private func expectResolverError(
    statusCode: Int,
    password: String?,
    expectedError: ImmichError
) async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(result: .success((Data(), httpResponse(url: baseURL, statusCode: statusCode))))
    let resolver = SharedLinkResolver(transport: transport)

    await #expect(throws: expectedError) {
        _ = try await resolver.resolve(baseURL: baseURL, slug: "summer", password: password)
    }
}

private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

/// An Immich error envelope (`{"message": ...}`) — the body the resolver inspects to tell an
/// invalid-identifier 401 from a password 401.
private func errorBody(_ message: String) -> Data {
    (try? JSONSerialization.data(withJSONObject: ["message": message, "error": "Unauthorized", "statusCode": 401])) ?? Data()
}

private func queryValue(_ name: String, in url: URL?) -> String? {
    guard let url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == name }?
        .value
}

private func isoDate(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
