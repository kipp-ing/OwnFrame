//
//  SourceModels.swift
//  PhotoSourceKit
//
//  900 — the backend-neutral value types the engine rotates over (R1). Wire-format
//  constraints from R2/R8: `SourceAsset` encodes byte-identically to the shipped
//  `[Asset]` snapshot (`{id, type}`), so fielded 320 snapshots decode without migration,
//  and unknown wire kinds degrade to `.other` instead of throwing.
//

import Foundation

/// Media class of a `SourceAsset`. Raw values reuse Immich's wire strings so snapshot
/// JSON stays byte-compatible (R2/R8). Unknown wire strings never map here directly —
/// `SourceAsset`'s decoder folds them into `.other` (see `init(from:)`).
public enum MediaKind: String, Sendable, Codable {
    case image = "IMAGE"
    case video = "VIDEO"
    case other = "OTHER"
}

/// The engine's unit of rotation and the snapshot store's persisted element.
///
/// Codable shape is `{"id": "...", "type": "IMAGE"}` — `type` is `kind`'s coding key,
/// byte-identical to the shipped `[Asset]` snapshot. Unknown `type` strings decode to
/// `.other` (forward-compat, R8); on re-encode an `.other` value writes `"OTHER"`, i.e.
/// the original unknown string is normalized away — the engine only needs to know the
/// asset is not a still image so it can skip it.
public struct SourceAsset: Sendable, Codable, Equatable {
    /// Backend-scoped identifier (Immich UUID / PhotoKit local identifier). Opaque to
    /// the engine; the image cache key stays `"\(id)#\(fidelity)"`.
    public let id: String
    /// Rotation gate: the engine keeps only `.image` assets (FR-300-13 + FR-900-08).
    public let kind: MediaKind

    public init(id: String, kind: MediaKind) {
        self.id = id
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind = "type"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let rawKind = try container.decode(String.self, forKey: .kind)
        // Unknown wire kinds degrade rather than fail the whole decode (R8).
        kind = MediaKind(rawValue: rawKind) ?? .other
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind.rawValue, forKey: .kind)
    }
}

/// A pickable collection (Immich album / PhotoKit collection). Minimal by design —
/// only what the picker (210 pattern) and album browser consume (R9).
public struct SourceCollection: Sendable, Equatable {
    /// Album UUID (Immich) / collection local identifier (PhotoKit).
    public let id: String
    /// Picker display + search key.
    public let title: String
    /// Picker display only; lazy/estimated counts are allowed (R9).
    public let assetCount: Int
    /// Album-browser thumbnail; `nil` renders a placeholder.
    public let coverAssetID: String?

    public init(id: String, title: String, assetCount: Int, coverAssetID: String?) {
        self.id = id
        self.title = title
        self.assetCount = assetCount
        self.coverAssetID = coverAssetID
    }
}

/// Info-overlay + HA metadata payload (FR-900-10/11). Absent fields are `nil`, never
/// faked; the overlay renders nothing for a `nil` field (FR-300-24). No geocoding in v1
/// (R7), so `placeName` is always `nil` from the Photos backend.
public struct AssetMetadata: Sendable, Equatable {
    public let capturedAt: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let placeName: String?

    public init(capturedAt: Date?, latitude: Double?, longitude: Double?, placeName: String?) {
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
    }
}

/// Neutral quality tier the engine requests; each backend maps it to endpoints/target
/// sizes (R6). Raw values are cache-key components (`"\(id)#\(fidelity)"`), so they are
/// deliberately stable lowercase strings — changing one silently invalidates on-disk caches.
public enum ImageFidelity: String, Sendable {
    case thumbnail
    case preview
    case original
}

/// Well-known identifiers for the Photos backend (R11). The limited-mode granted-assets
/// pool resolves through `selectedPhotosID` instead of a real collection identifier.
public enum PhotoLibrarySource {
    public static let selectedPhotosID = "selected-photos"
}
