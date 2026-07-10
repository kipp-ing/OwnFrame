import Foundation

public struct Album: Codable, Sendable {
    public let id: String
    public let name: String
    // Advisory metadata from `GET /api/albums`, used only for the searchable picker
    // subtitle (210). All optional: older servers and the shared-link `me` album
    // reference may carry only `id` + `albumName`.
    public let assetCount: Int?
    public let startDate: Date?
    public let endDate: Date?

    public init(
        id: String,
        name: String,
        assetCount: Int? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.assetCount = assetCount
        self.startDate = startDate
        self.endDate = endDate
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name = "albumName"
        case assetCount
        case startDate
        case endDate
    }

    // Decode dates from ISO8601 strings so the album list keeps decoding with a plain
    // `JSONDecoder()` (matching `ImmichClient.albums()`), tolerating absent/null fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        assetCount = try container.decodeIfPresent(Int.self, forKey: .assetCount)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
            .flatMap(Album.parseISO8601Date)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
            .flatMap(Album.parseISO8601Date)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(assetCount, forKey: .assetCount)
        try container.encodeIfPresent(startDate.map(Album.formatISO8601Date), forKey: .startDate)
        try container.encodeIfPresent(endDate.map(Album.formatISO8601Date), forKey: .endDate)
    }

    private static func parseISO8601Date(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private static func formatISO8601Date(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct Asset: Codable, Sendable {
    public let id: String
    public let type: String

    public init(id: String, type: String) {
        self.id = id
        self.type = type
    }
}

// MARK: - Immich API v3 (130)

/// Request body for `POST /api/search/metadata` — the v3 replacement for the removed album
/// `assets` array. `albumIds` filters to one album; `type` filters to images server-side;
/// `order` mirrors the album's own sort (`asc`/`desc` by date); `page`/`size` drive paging.
struct MetadataSearchRequest: Encodable, Sendable {
    let albumIds: [String]
    let type: String?
    let order: String?
    let page: Int
    let size: Int
}

/// Response of `POST /api/search/metadata`. Assets live under `assets.items`; `assets.nextPage`
/// is a string page token (`nil` when the last page has been returned).
struct SearchResponse: Decodable, Sendable {
    let assets: AssetsPage

    struct AssetsPage: Decodable, Sendable {
        let items: [Asset]
        let nextPage: String?
    }
}

/// Request body for `POST /api/shared-links/login` — the password moves out of the URL query
/// and into the body in v3 (FR-130-03). The link identifier stays a `?key=`/`?slug=` query.
struct SharedLinkLoginRequest: Encodable, Sendable {
    let password: String
}

/// Assets carried by a `SharedLinkResponseDto` (`GET /api/shared-links/me` or
/// `POST /api/shared-links/login`). A shared-link source lists its assets from here — v3 does
/// not accept the `?key=` credential on `/api/search/metadata`, and the album `assets` array is
/// gone (FR-130-12). Optional so a link without an embedded list decodes to an empty result.
struct SharedLinkMeAssetsResponse: Decodable, Sendable {
    let assets: [Asset]?
}

public struct AssetInfo: Sendable, Equatable {
    public let id: String
    public let takenAt: Date?
    public let city: String?
    public let state: String?
    public let country: String?

    public init(id: String, takenAt: Date?, city: String?, state: String?, country: String?) {
        self.id = id
        self.takenAt = takenAt
        self.city = city
        self.state = state
        self.country = country
    }
}

struct AssetDetail: Decodable, Sendable {
    let id: String
    let localDateTime: String?
    let fileCreatedAt: String?
    let exifInfo: ExifInfo?

    struct ExifInfo: Decodable, Sendable {
        let dateTimeOriginal: String?
        let city: String?
        let state: String?
        let country: String?
    }
}
