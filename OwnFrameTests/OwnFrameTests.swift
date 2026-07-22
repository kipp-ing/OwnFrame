//
//  OwnFrameTests.swift
//  OwnFrameTests
//
//  App-hosted integration tests: exercise the ImmichClient public API on the
//  iPad simulator inside the real app's unit-test bundle. The package keeps its
//  own host-level suite (swift test); these prove the framework links and works
//  through the real targets on-device. MockTransport comes from the shared
//  ImmichClientTestSupport product, so no real server is needed (SC-006).
//

import Foundation
import Testing
import ImmichClient
import ImmichClientTestSupport

struct ImmichClientIntegrationTests {

    private let baseURL = URL(string: "https://photos.example.test")!
    private let apiKey = "secret-api-key"

    private func makeClient(
        json: String,
        statusCode: Int = 200,
        path: String = "/api/albums"
    ) throws -> (ImmichClient, MockTransport) {
        let requestURL = try #require(URL(string: "https://photos.example.test\(path)"))
        let data = try #require(json.data(using: .utf8))
        let response = try #require(HTTPURLResponse(
            url: requestURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = MockTransport(result: .success((data, response)))
        let client = ImmichClient(
            config: ServerConfig(baseURL: baseURL, apiKey: apiKey),
            transport: transport
        )
        return (client, transport)
    }

    // SC-002: albumName -> name decoded losslessly through the public API.
    @Test func albumsDecodeAlbumNameAsName() async throws {
        let (client, _) = try makeClient(
            json: #"[{"id":"a1","albumName":"Family"},{"id":"a2","albumName":""}]"#
        )

        let albums = try await client.albums()

        #expect(albums.count == 2)
        #expect(albums[0].id == "a1")
        #expect(albums[0].name == "Family")
        #expect(albums[1].name == "")
    }

    // SC-001: every request carries x-api-key (albums / assets / preview).
    @Test func albumsRequestCarriesAPIKeyHeader() async throws {
        let (client, transport) = try makeClient(json: "[]")

        _ = try await client.albums()

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/albums")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == apiKey)
    }

    // v3 (130): an API-key album lists its images via POST /api/search/metadata, not the
    // removed album `assets` array.
    @Test func assetsFetchImagesViaMetadataSearchWithAPIKey() async throws {
        let (client, transport) = try makeClient(
            json: #"{"assets":{"items":[{"id":"asset-1","type":"IMAGE"}],"nextPage":null}}"#,
            path: "/api/search/metadata"
        )

        let assets = try await client.assets(albumID: "album-1")

        #expect(assets.count == 1)
        #expect(assets[0].id == "asset-1")
        #expect(assets[0].type == "IMAGE")

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/search/metadata")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == apiKey)
    }

    @Test func previewRequestUsesThumbnailPreviewQueryAndReturnsData() async throws {
        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let requestURL = try #require(URL(string: "https://photos.example.test/api/assets/asset-1/thumbnail"))
        let response = try #require(HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = MockTransport(result: .success((imageBytes, response)))
        let client = ImmichClient(
            config: ServerConfig(baseURL: baseURL, apiKey: apiKey),
            transport: transport
        )

        let data = try await client.preview(assetID: "asset-1")

        #expect(data == imageBytes)
        let request = try #require(await transport.recordedRequests.first)
        #expect(request.url?.path == "/api/assets/asset-1/thumbnail")
        #expect(request.url?.query?.contains("size=preview") == true)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == apiKey)
    }

    // SC-005: empty album decodes to [] without error.
    @Test func assetsReturnsEmptyArrayForEmptyAlbum() async throws {
        let (client, _) = try makeClient(
            json: #"{"assets":{"items":[],"nextPage":null}}"#,
            path: "/api/search/metadata"
        )

        let assets = try await client.assets(albumID: "empty")

        #expect(assets.isEmpty)
    }

    // SC-003: 401 -> .unauthorized.
    @Test func unauthorizedStatusMapsToUnauthorizedError() async throws {
        let (client, _) = try makeClient(json: "", statusCode: 401)

        await #expect(throws: ImmichError.unauthorized) {
            _ = try await client.albums()
        }
    }

    // SC-004: transport URLError -> .unreachable.
    @Test func transportFailureMapsToUnreachableError() async throws {
        let transport = MockTransport(result: .failure(URLError(.timedOut)))
        let client = ImmichClient(
            config: ServerConfig(baseURL: baseURL, apiKey: apiKey),
            transport: transport
        )

        await #expect(throws: ImmichError.unreachable) {
            _ = try await client.albums()
        }
    }
}
