import Foundation
import ImmichClient

public struct ResolvedSource: Sendable {
    public let serverConfig: ServerConfig
    public let albumID: String

    public init(serverConfig: ServerConfig, albumID: String) {
        self.serverConfig = serverConfig
        self.albumID = albumID
    }
}

public struct ActiveSourceResolver: Sendable {
    // Optional because a shared-link-only setup has no server API key or album base URL — and a
    // shared-link active source resolves without them (FR-210-03/04). Required only to resolve an
    // album active source.
    private let albumBaseURL: URL?
    private let apiKey: String?
    private let secretStore: any SharedLinkSecretStore
    private let sharedLinkResolver: any SharedLinkResolving
    private let resolutionCache: any SharedLinkResolutionStore

    public init(
        albumBaseURL: URL?,
        apiKey: String?,
        secretStore: any SharedLinkSecretStore,
        sharedLinkResolver: any SharedLinkResolving,
        resolutionCache: any SharedLinkResolutionStore = InMemorySharedLinkResolutionStore()
    ) {
        self.albumBaseURL = albumBaseURL
        self.apiKey = apiKey
        self.secretStore = secretStore
        self.sharedLinkResolver = sharedLinkResolver
        self.resolutionCache = resolutionCache
    }

    public func resolve(_ source: Source) async throws -> ResolvedSource {
        switch source.kind {
        case let .album(albumID):
            // An album source needs the server API key + base URL; a shared-link-only setup has
            // neither (but also never has an album active source).
            guard let albumBaseURL, let apiKey else {
                throw ImmichError.unauthorized
            }
            return ResolvedSource(
                serverConfig: ServerConfig(baseURL: albumBaseURL, auth: .apiKey(apiKey)),
                albumID: albumID
            )
        case let .sharedLink(baseURL, slug):
            let password = secretStore.readPassword(forSourceID: source.id)
            let resolution: SharedLinkResolution
            do {
                resolution = try await sharedLinkResolver.resolve(baseURL: baseURL, slug: slug, password: password)
                resolutionCache.save(resolution, forSourceID: source.id)
            } catch ImmichError.unreachable {
                // A cold launch while offline (issue #80) has no network to resolve the slug
                // with — fall back to the last successful resolution rather than stalling the
                // whole slideshow on a black screen. Only for "unreachable": every other
                // failure (wrong password, expired/invalid link) is a real answer from the
                // server and must still surface as one.
                guard let cached = resolutionCache.read(forSourceID: source.id) else {
                    throw ImmichError.unreachable
                }
                resolution = cached
            }
            return ResolvedSource(
                serverConfig: ServerConfig(baseURL: baseURL, auth: .shareKey(resolution.key)),
                albumID: resolution.albumID
            )
        case .photoLibrary:
            // A device photo-library source has no Immich server to resolve against — the app
            // builds its provider directly by SourceKind (900). This Immich-only resolver
            // rejects it calmly rather than fabricating a server config.
            throw ImmichError.unauthorized
        }
    }
}
