import Foundation
import ImmichClient
import Testing
@testable import OnboardingKit

@Test func activeSourceResolverMapsAlbumSourceToAPIKeyConfigAndAlbumID() async throws {
    let source = Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1"))
    let baseURL = URL(string: "https://photos.example.test")!
    let resolver = ActiveSourceResolver(
        albumBaseURL: baseURL,
        apiKey: "secret-api-key",
        secretStore: InMemorySharedLinkSecretStore(),
        sharedLinkResolver: StubSharedLinkResolver()
    )

    let resolved = try await resolver.resolve(source)

    #expect(resolved.serverConfig.baseURL == baseURL)
    #expect(resolved.serverConfig.auth == .apiKey("secret-api-key"))
    #expect(resolved.albumID == "album-1")
}

@Test func activeSourceResolverMapsSharedLinkSourceToShareKeyConfigAndResolvedAlbumID() async throws {
    let source = Source(
        id: "source-1",
        label: "Shared",
        kind: .sharedLink(baseURL: URL(string: "https://shared.example.test")!, slug: "summer")
    )
    let secretStore = InMemorySharedLinkSecretStore()
    try secretStore.savePassword("shared-password", forSourceID: "source-1")
    let sharedLinkResolver = StubSharedLinkResolver(
        result: .success(SharedLinkResolution(key: "share-key", albumID: "resolved-album", expiresAt: nil))
    )
    let resolver = ActiveSourceResolver(
        albumBaseURL: URL(string: "https://photos.example.test")!,
        apiKey: "secret-api-key",
        secretStore: secretStore,
        sharedLinkResolver: sharedLinkResolver
    )

    let resolved = try await resolver.resolve(source)

    #expect(sharedLinkResolver.requests == [
        StubSharedLinkResolver.Request(
            baseURL: URL(string: "https://shared.example.test")!,
            slug: "summer",
            password: "shared-password"
        ),
    ])
    #expect(resolved.serverConfig.baseURL == URL(string: "https://shared.example.test")!)
    #expect(resolved.serverConfig.auth == .shareKey("share-key"))
    #expect(resolved.albumID == "resolved-album")
}

// FR-210-03/04 (device black-screen bug): a shared-link active source is a complete config on
// its own — it MUST resolve with no album API key / base URL (a shared-link-only setup has
// neither).
@Test func activeSourceResolverResolvesSharedLinkWithoutAlbumCredentials() async throws {
    let source = Source(
        id: "source-1",
        label: "Shared",
        kind: .sharedLink(baseURL: URL(string: "https://shared.example.test")!, slug: "summer")
    )
    let resolver = ActiveSourceResolver(
        albumBaseURL: nil,
        apiKey: nil,
        secretStore: InMemorySharedLinkSecretStore(),
        sharedLinkResolver: StubSharedLinkResolver(
            result: .success(SharedLinkResolution(key: "share-key", albumID: "resolved-album", expiresAt: nil))
        )
    )

    let resolved = try await resolver.resolve(source)

    #expect(resolved.serverConfig.baseURL == URL(string: "https://shared.example.test")!)
    #expect(resolved.serverConfig.auth == .shareKey("share-key"))
    #expect(resolved.albumID == "resolved-album")
}

// An album source still needs the server credentials; without them it fails rather than
// silently producing a bad config.
@Test func activeSourceResolverThrowsForAlbumSourceWithoutCredentials() async {
    let source = Source(id: "source-1", label: "Family", kind: .album(albumID: "album-1"))
    let resolver = ActiveSourceResolver(
        albumBaseURL: nil,
        apiKey: nil,
        secretStore: InMemorySharedLinkSecretStore(),
        sharedLinkResolver: StubSharedLinkResolver()
    )

    await #expect(throws: ImmichError.unauthorized) {
        _ = try await resolver.resolve(source)
    }
}

@Test func activeSourceResolverPropagatesSharedLinkResolverImmichError() async {
    let source = Source(
        id: "source-1",
        label: "Shared",
        kind: .sharedLink(baseURL: URL(string: "https://shared.example.test")!, slug: "summer")
    )
    let resolver = ActiveSourceResolver(
        albumBaseURL: URL(string: "https://photos.example.test")!,
        apiKey: "secret-api-key",
        secretStore: InMemorySharedLinkSecretStore(),
        sharedLinkResolver: StubSharedLinkResolver(result: .failure(ImmichError.wrongPassword))
    )

    await #expect(throws: ImmichError.wrongPassword) {
        _ = try await resolver.resolve(source)
    }
}

private final class StubSharedLinkResolver: SharedLinkResolving, @unchecked Sendable {
    struct Request: Equatable {
        let baseURL: URL
        let slug: String
        let password: String?
    }

    private let result: Result<SharedLinkResolution, Error>
    private(set) var requests: [Request] = []

    init(result: Result<SharedLinkResolution, Error> = .success(SharedLinkResolution(key: "share-key", albumID: "album-1", expiresAt: nil))) {
        self.result = result
    }

    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        requests.append(Request(baseURL: baseURL, slug: slug, password: password))
        return try result.get()
    }
}
