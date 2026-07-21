//
//  ImmichPhotoSourceTests.swift
//  ImmichClientTests
//
//  900 (T007) — ImmichClient's conformance to the backend-neutral `PhotoSourceProviding`
//  contract (slice B): happy-path mapping for all five methods + the complete
//  ImmichError → SourceFailure error table. MockTransport-driven; every failure assertion
//  switches the returned `SourceFailure` exhaustively (no string matching).
//
//  Error-mapping table as verified here (see also the header of ImmichPhotoSource.swift):
//
//    ImmichError.unauthorized        → .authentication
//    ImmichError.invalidShareLink    → .authentication
//    ImmichError.shareLinkExpired    → .authentication
//    ImmichError.wrongPassword       → .authentication
//    ImmichError.passwordRequired    → .authentication
//    ImmichError.unreachable         → .transient(underlying:)
//    ImmichError.invalidResponse     → .transient(underlying:)   (see note below)
//    ImmichError.serverTooOld        → .permanent(underlying:)   (terminal; mirrors
//                                       RetryPolicy's `.unsupportedServer` isTerminal)
//    raw URLError (defensive)        → .transient(underlying:)
//    any other error (defensive)     → .permanent(underlying:)
//
//  Note on `.invalidResponse`: ImmichClient collapses non-2xx/non-401 HTTP statuses
//  (404, 5xx, ...) AND JSON-decode failures into the single `.invalidResponse` case, so a
//  404 (album deleted) and a decode/contract violation are indistinguishable at this
//  boundary. Both surface as `.transient` — the behavior-preserving choice (RetryPolicy
//  classifies `.invalidResponse` as `.transient` today, so a temporary 5xx keeps retrying
//  instead of becoming a terminal `.permanent`). Reaching the finer `.notFound` (404) and
//  `.permanent` (decode) arms requires the frozen client to expose the HTTP status /
//  distinct decode error — out of scope for this slice.
//

import Foundation
import Testing
@testable import ImmichClient
import ImmichClientTestSupport
import PhotoSourceKit

// MARK: - Happy-path mapping

// @covers FR-100-03
@Test func collectionsMapsAlbumsToSourceCollections() async throws {
    let json = """
    [
        { "id": "album-1", "albumName": "Family", "assetCount": 42 },
        { "id": "album-2", "albumName": "Trip" }
    ]
    """
    let (source, _) = try makeSource(data: Data(json.utf8), statusCode: 200)

    let collections = try await source.collections()

    #expect(collections == [
        SourceCollection(id: "album-1", title: "Family", assetCount: 42, coverAssetID: nil),
        // Absent assetCount collapses to 0; ImmichClient's Album carries no cover field,
        // so coverAssetID is always nil.
        SourceCollection(id: "album-2", title: "Trip", assetCount: 0, coverAssetID: nil),
    ])
}

// @covers FR-100-04
@Test func assetsMapsImmichAssetsWithMediaKindPassthrough() async throws {
    // Immich `type` string flows through `MediaKind(rawValue:) ?? .other`: IMAGE/VIDEO map
    // directly, an unknown string (AUDIO) degrades to `.other`.
    let json = #"{"assets":{"items":[{"id":"a1","type":"IMAGE"},{"id":"v1","type":"VIDEO"},{"id":"x1","type":"AUDIO"}],"nextPage":null}}"#
    let (source, _) = try makeSource(data: Data(json.utf8), statusCode: 200)

    let assets = try await source.assets(in: "album-1")

    #expect(assets == [
        SourceAsset(id: "a1", kind: .image),
        SourceAsset(id: "v1", kind: .video),
        SourceAsset(id: "x1", kind: .other),
    ])
}

// @covers FR-100-14
@Test func imageDataThumbnailHitsThumbnailEndpoint() async throws {
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    let (source, transport) = try makeSource(data: bytes, statusCode: 200)

    let data = try await source.imageData(for: "asset-1", fidelity: .thumbnail)

    #expect(data == bytes)
    let request = try #require(await transport.recordedRequests.only)
    #expect(request.url?.path == "/api/assets/asset-1/thumbnail")
    #expect(sizeQuery(of: request) == "thumbnail")
}

@Test func imageDataPreviewHitsPreviewEndpoint() async throws {
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    let (source, transport) = try makeSource(data: bytes, statusCode: 200)

    let data = try await source.imageData(for: "asset-1", fidelity: .preview)

    #expect(data == bytes)
    let request = try #require(await transport.recordedRequests.only)
    #expect(request.url?.path == "/api/assets/asset-1/thumbnail")
    #expect(sizeQuery(of: request) == "preview")
}

// @covers FR-100-13
@Test func imageDataOriginalHitsOriginalEndpoint() async throws {
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    let (source, transport) = try makeSource(data: bytes, statusCode: 200)

    let data = try await source.imageData(for: "asset-1", fidelity: .original)

    #expect(data == bytes)
    let request = try #require(await transport.recordedRequests.only)
    #expect(request.url?.path == "/api/assets/asset-1/original")
    #expect(sizeQuery(of: request) == nil)
}

@Test func metadataComposesPlaceNameFromCityAndCountry() async throws {
    let json = """
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
    """
    let (source, _) = try makeSource(data: Data(json.utf8), statusCode: 200)

    let metadata = try await source.metadata(for: "asset-1")

    #expect(metadata == AssetMetadata(
        capturedAt: try expectedDate("2024-06-15T14:30:00.000Z"),
        // ImmichClient's AssetInfo/ExifInfo surface carries no coordinates today, so
        // latitude/longitude stay nil (absent → nil, never faked).
        latitude: nil,
        longitude: nil,
        // Same composition as PhotoInfoView: [city, country] joined by ", ".
        placeName: "Berlin, Germany"
    ))
}

@Test func metadataUsesCityOnlyWhenCountryMissing() async throws {
    let json = """
    {
        "id": "asset-1",
        "type": "IMAGE",
        "localDateTime": "2024-06-15T14:30:00.000Z",
        "exifInfo": { "city": "Berlin" }
    }
    """
    let (source, _) = try makeSource(data: Data(json.utf8), statusCode: 200)

    let metadata = try await source.metadata(for: "asset-1")

    #expect(metadata.placeName == "Berlin")
}

@Test func metadataCollapsesMissingLocationToNilPlaceName() async throws {
    let json = """
    {
        "id": "asset-1",
        "type": "IMAGE",
        "localDateTime": "2024-06-15T14:30:00.000Z"
    }
    """
    let (source, _) = try makeSource(data: Data(json.utf8), statusCode: 200)

    let metadata = try await source.metadata(for: "asset-1")

    #expect(metadata.capturedAt == (try expectedDate("2024-06-15T14:30:00.000Z")))
    #expect(metadata.placeName == nil)
    #expect(metadata.latitude == nil)
    #expect(metadata.longitude == nil)
}

// MARK: - ensureReady (server-version gate)

@Test func ensureReadySucceedsForSupportedServer() async throws {
    let json = #"{"major":3,"minor":0,"patch":2}"#
    let (source, _) = try makeSource(data: Data(json.utf8), statusCode: 200)

    try await source.ensureReady()
}

@Test func ensureReadyMapsTooOldServerToPermanent() async throws {
    let json = #"{"major":2,"minor":118,"patch":0}"#
    let (source, _) = try makeSource(data: Data(json.utf8), statusCode: 200)

    let failure = try await captureFailure { try await source.ensureReady() }
    #expect(arm(of: failure) == .permanent)
    // The version gate error is carried for a future SourceFailure-aware classifier.
    #expect(underlyingImmichError(of: failure) == .serverTooOld(version: "2.118.0"))
}

// MARK: - Error mapping through the source surface (MockTransport-driven)

@Test func unauthorizedStatusMapsToAuthentication() async throws {
    let (source, _) = try makeSource(data: Data(), statusCode: 401)

    let failure = try await captureFailure { _ = try await source.collections() }
    #expect(arm(of: failure) == .authentication)
}

@Test func urlErrorMapsToTransient() async throws {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let transport = MockTransport(result: .failure(URLError(.timedOut)))
    let source: any PhotoSourceProviding = ImmichClient(
        config: ServerConfig(baseURL: baseURL, apiKey: "secret-api-key"),
        transport: transport
    )

    let failure = try await captureFailure { _ = try await source.collections() }
    #expect(arm(of: failure) == .transient)
}

@Test func serverErrorStatusMapsToTransient() async throws {
    let (source, _) = try makeSource(data: Data("[]".utf8), statusCode: 500)

    let failure = try await captureFailure { _ = try await source.collections() }
    #expect(arm(of: failure) == .transient)
}

@Test func undecodableBodyMapsToTransient() async throws {
    // 200 + wrong shape → ImmichClient throws `.invalidResponse` (decode failure), which
    // this boundary cannot separate from a 5xx → `.transient`. Documents the collapse.
    let (source, _) = try makeSource(data: Data(#"{"unexpected":"shape"}"#.utf8), statusCode: 200)

    let failure = try await captureFailure { _ = try await source.collections() }
    #expect(arm(of: failure) == .transient)
}

@Test func notFoundStatusMapsToTransientBecauseClientCollapsesStatus() async throws {
    // A deleted album (404) would ideally be `.notFound`, but ImmichClient collapses every
    // non-2xx/non-401 status into `.invalidResponse`, so it currently surfaces as
    // `.transient`. Locks in the documented limitation until the client exposes the status.
    let (source, _) = try makeSource(data: Data(), statusCode: 404)

    let failure = try await captureFailure { _ = try await source.collections() }
    #expect(arm(of: failure) == .transient)
}

// MARK: - The full ImmichError → SourceFailure table (direct, exhaustive)

@Test func immichErrorMappingTableIsExhaustiveAndStable() {
    let table: [(ImmichError, FailureArm)] = [
        (.unauthorized, .authentication),
        (.invalidShareLink, .authentication),
        (.shareLinkExpired, .authentication),
        (.wrongPassword, .authentication),
        (.passwordRequired, .authentication),
        (.unreachable, .transient),
        (.invalidResponse, .transient),
        (.serverTooOld(version: "2.118.0"), .permanent),
    ]
    for (error, expected) in table {
        #expect(arm(of: ImmichSourceFailureMapping.failure(for: error)) == expected,
                "ImmichError \(error) should map to \(expected)")
    }
}

@Test func rawURLErrorMapsToTransientDefensively() {
    let failure = ImmichSourceFailureMapping.failure(for: URLError(.notConnectedToInternet))
    #expect(arm(of: failure) == .transient)
}

@Test func unexpectedErrorTypeMapsToPermanentDefensively() {
    struct Surprise: Error {}
    let failure = ImmichSourceFailureMapping.failure(for: Surprise())
    #expect(arm(of: failure) == .permanent)
}

@Test func transientAndPermanentPreserveTheUnderlyingError() {
    let transient = ImmichSourceFailureMapping.failure(for: ImmichError.unreachable)
    #expect(underlyingImmichError(of: transient) == .unreachable)

    let permanent = ImmichSourceFailureMapping.failure(for: ImmichError.serverTooOld(version: "1.0.0"))
    #expect(underlyingImmichError(of: permanent) == .serverTooOld(version: "1.0.0"))
}

// MARK: - Helpers

/// The four `SourceFailure` arms, flattened for exhaustive-switch assertions (no string
/// matching, no associated-value comparison where the arm alone is what's under test).
private enum FailureArm: Equatable {
    case transient
    case authentication
    case notFound
    case permanent
}

private func arm(of failure: SourceFailure) -> FailureArm {
    switch failure {
    case .transient: return .transient
    case .authentication: return .authentication
    case .notFound: return .notFound
    case .permanent: return .permanent
    }
}

/// Extracts the `underlying` ImmichError from `.transient`/`.permanent`, or nil for the
/// payload-free arms.
private func underlyingImmichError(of failure: SourceFailure) -> ImmichError? {
    switch failure {
    case let .transient(underlying): return underlying as? ImmichError
    case let .permanent(underlying): return underlying as? ImmichError
    case .authentication, .notFound: return nil
    }
}

private func captureFailure(
    _ operation: () async throws -> Void
) async throws -> SourceFailure {
    do {
        try await operation()
        Issue.record("Expected a SourceFailure, but the call succeeded.")
    } catch let failure as SourceFailure {
        return failure
    } catch {
        Issue.record("Expected a SourceFailure, but got \(error).")
    }
    throw CancellationError()
}

private func makeSource(
    data: Data,
    statusCode: Int
) throws -> (any PhotoSourceProviding, MockTransport) {
    let baseURL = try #require(URL(string: "https://photos.example.test"))
    let response = try #require(HTTPURLResponse(
        url: baseURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    ))
    let transport = MockTransport(result: .success((data, response)))
    let config = ServerConfig(baseURL: baseURL, apiKey: "secret-api-key")
    return (ImmichClient(config: config, transport: transport), transport)
}

private func sizeQuery(of request: URLRequest) -> String? {
    guard let url = request.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "size" }?
        .value
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
