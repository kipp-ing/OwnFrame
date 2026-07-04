import Foundation
import os

public struct SharedLinkResolution: Sendable, Equatable {
    public let key: String
    public let albumID: String
    public let expiresAt: Date?

    public init(key: String, albumID: String, expiresAt: Date?) {
        self.key = key
        self.albumID = albumID
        self.expiresAt = expiresAt
    }
}

public protocol SharedLinkResolving: Sendable {
    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution
}

public struct SharedLinkResolver: SharedLinkResolving {
    private let log = Logger(subsystem: "ing.kipp.Immich-Slideshow", category: "SharedLinkResolver")
    private let transport: HTTPTransport
    private let now: @Sendable () -> Date

    public init(transport: HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = Date.init) {
        self.transport = transport
        self.now = now
    }

    /// Which query parameter identifies the link. A `/share/<X>` URL carries the share `key`;
    /// a custom `/s/<X>` URL carries a `slug`. The stored identifier could be either, so we
    /// resolve `key` first and fall back to `slug`.
    private enum Identifier: String { case key, slug }

    /// Internal signal that the server reported the identifier as not found under the tried
    /// parameter (an "Invalid share key/slug" 401 or a 404) — try the other parameter.
    private struct IdentifierNotFound: Error {}

    public func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        // `/share/<X>` is a key; querying it as `slug=` returns 401 "Invalid share key/slug",
        // which previously surfaced as a false password prompt (FR-210-06/07). Resolve as a
        // key first and fall back to a slug only when the key isn't recognized.
        do {
            return try await attempt(baseURL: baseURL, identifier: slug, as: .key, password: password)
        } catch is IdentifierNotFound {
            do {
                return try await attempt(baseURL: baseURL, identifier: slug, as: .slug, password: password)
            } catch is IdentifierNotFound {
                // Unknown under both `key` and `slug` — the link is invalid/expired/revoked.
                throw ImmichError.invalidShareLink
            }
        }
    }

    private func attempt(
        baseURL: URL,
        identifier: String,
        as parameter: Identifier,
        password: String?
    ) async throws -> SharedLinkResolution {
        let request = makeRequest(baseURL: baseURL, parameter: parameter, identifier: identifier, password: password)

        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ImmichError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                let resolution = try decodeResolution(from: data)
                if let expiresAt = resolution.expiresAt, expiresAt <= now() {
                    throw ImmichError.shareLinkExpired
                }
                return resolution
            case 401:
                // The server returns 401 both for an unknown key/slug AND for a password
                // challenge. Only an "Invalid share key/slug" message is a not-found result;
                // every other 401 is treated as a password issue, so this stays correct
                // regardless of the server's exact password-error wording.
                if isInvalidIdentifier(data) {
                    throw IdentifierNotFound()
                }
                throw password == nil ? ImmichError.passwordRequired : ImmichError.wrongPassword
            case 404:
                throw IdentifierNotFound()
            case 410:
                throw ImmichError.shareLinkExpired
            default:
                log.error("Unexpected HTTP status \(httpResponse.statusCode, privacy: .public) for path \(request.url?.path ?? "<unknown>", privacy: .public)")
                throw ImmichError.invalidResponse
            }
        } catch let error as ImmichError {
            throw error
        } catch is IdentifierNotFound {
            throw IdentifierNotFound()
        } catch is URLError {
            throw ImmichError.unreachable
        }
    }

    /// True when a 401 body is an Immich "Invalid share key" / "Invalid share slug" envelope —
    /// i.e. the identifier was not found, not a password challenge.
    private func isInvalidIdentifier(_ data: Data) -> Bool {
        guard let message = decodeErrorMessage(from: data)?.lowercased() else { return false }
        return message.contains("share key") || message.contains("share slug")
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable { let message: String? }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.message
    }

    private func makeRequest(baseURL: URL, parameter: Identifier, identifier: String, password: String?) -> URLRequest {
        let url = baseURL.appending(path: "api/shared-links/me")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: parameter.rawValue, value: identifier)]
        if let password {
            queryItems.append(URLQueryItem(name: "password", value: password))
        }
        components?.queryItems = queryItems

        var request = URLRequest(url: url)
        if let componentURL = components?.url {
            request.url = componentURL
        }
        request.httpMethod = "GET"
        return request
    }

    private func decodeResolution(from data: Data) throws -> SharedLinkResolution {
        do {
            let response = try JSONDecoder().decode(SharedLinkMeResponse.self, from: data)
            return SharedLinkResolution(
                key: response.key,
                albumID: response.album.id,
                expiresAt: response.expiresAt.flatMap(parseISO8601Date)
            )
        } catch let error as ImmichError {
            throw error
        } catch {
            log.error("Failed to decode SharedLinkResolution: \(error.localizedDescription, privacy: .public)")
            throw ImmichError.invalidResponse
        }
    }

    private func parseISO8601Date(_ string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct SharedLinkMeResponse: Decodable {
    let key: String
    let album: AlbumReference
    let expiresAt: String?

    struct AlbumReference: Decodable {
        let id: String
    }
}
