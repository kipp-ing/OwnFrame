import Foundation
import os

public struct ImmichClient: ImmichAPI {
    private let log = Logger(subsystem: "ing.kipp.Immich-Slideshow", category: "ImmichClient")
    private let config: ServerConfig
    private let transport: HTTPTransport

    public init(config: ServerConfig, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    public func serverVersion() async throws -> String {
        let request = makeRequest(path: "api/server/version")
        let data = try await responseData(for: request)
        let version = try decode(ServerVersion.self, from: data)
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    public func albums() async throws -> [Album] {
        let request = makeRequest(path: "api/albums")
        let data = try await responseData(for: request)
        return try decode([Album].self, from: data)
    }

    public func assets(albumID: String) async throws -> [Asset] {
        let request = makeRequest(path: "api/albums/\(albumID)")
        let data = try await responseData(for: request)
        return try decode(AlbumDetail.self, from: data).assets
    }

    public func assetInfo(assetID: String) async throws -> AssetInfo {
        let request = makeRequest(path: "api/assets/\(assetID)")
        let data = try await responseData(for: request)
        let detail = try decode(AssetDetail.self, from: data)
        let takenAt = firstParsedDate([
            detail.exifInfo?.dateTimeOriginal,
            detail.localDateTime,
            detail.fileCreatedAt
        ])

        return AssetInfo(
            id: detail.id,
            takenAt: takenAt,
            city: detail.exifInfo?.city,
            state: detail.exifInfo?.state,
            country: detail.exifInfo?.country
        )
    }

    public func preview(assetID: String) async throws -> Data {
        let request = makeRequest(
            path: "api/assets/\(assetID)/thumbnail",
            queryItems: [URLQueryItem(name: "size", value: "preview")]
        )
        return try await responseData(for: request)
    }

    public func thumbnail(assetID: String) async throws -> Data {
        let request = makeRequest(
            path: "api/assets/\(assetID)/thumbnail",
            queryItems: [URLQueryItem(name: "size", value: "thumbnail")]
        )
        return try await responseData(for: request)
    }

    public func original(assetID: String) async throws -> Data {
        let request = makeRequest(path: "api/assets/\(assetID)/original")
        return try await responseData(for: request)
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = []) -> URLRequest {
        let url = config.baseURL.appending(path: path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var requestQueryItems = queryItems
        if case let .shareKey(key) = config.auth {
            requestQueryItems.append(URLQueryItem(name: "key", value: key))
        }
        components?.queryItems = requestQueryItems.isEmpty ? nil : requestQueryItems
        var request = URLRequest(url: url)
        if let componentURL = components?.url {
            request.url = componentURL
        }
        request.httpMethod = "GET"
        if case let .apiKey(apiKey) = config.auth {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        return request
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ImmichError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return data
            case 401:
                throw ImmichError.unauthorized
            default:
                log.error("Unexpected HTTP status \(httpResponse.statusCode, privacy: .public) for path \(request.url?.path ?? "<unknown>", privacy: .public)")
                throw ImmichError.invalidResponse
            }
        } catch let error as ImmichError {
            throw error
        } catch is URLError {
            throw ImmichError.unreachable
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as ImmichError {
            throw error
        } catch {
            log.error("Failed to decode \(String(describing: type), privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw ImmichError.invalidResponse
        }
    }

    private func firstParsedDate(_ candidates: [String?]) -> Date? {
        for candidate in candidates {
            guard let candidate, let date = parseISO8601Date(candidate) else {
                continue
            }
            return date
        }
        return nil
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

private struct ServerVersion: Decodable {
    let major: Int
    let minor: Int
    let patch: Int
}
