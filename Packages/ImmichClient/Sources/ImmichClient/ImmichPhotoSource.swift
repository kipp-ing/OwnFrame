//
//  ImmichPhotoSource.swift
//  ImmichClient
//
//  900 (T008) — ImmichClient's conformance to the backend-neutral `PhotoSourceProviding`
//  contract (slice B). ImmichClient stays a peer conformer alongside PhotoLibraryKit; the
//  engine consumes only the neutral surface. Retro-conformance via `extension` because none
//  of the protocol's selectors clash with the existing `ImmichAPI` surface (`assets(in:)`
//  vs `assets(albumID:)`, `collections()` vs `albums()`, etc.), so no wrapper is needed.
//
//  Every thrown error is funneled through `ImmichSourceFailureMapping` so the engine reacts
//  through the closed `SourceFailure` taxonomy identically across backends:
//
//    .unauthorized / .invalidShareLink / .shareLinkExpired / .wrongPassword /
//                                            .passwordRequired → .authentication
//    .unreachable / .invalidResponse                          → .transient(underlying:)
//    .serverTooOld                                            → .permanent(underlying:)
//    raw URLError (defensive)                                 → .transient(underlying:)
//    any other error (defensive)                              → .permanent(underlying:)
//
//  `.serverTooOld` → `.permanent` mirrors RetryPolicy's terminal `.unsupportedServer`
//  classification (no backoff, manual recovery). `.invalidResponse` collapses non-2xx/non-401
//  statuses (incl. 404) AND decode failures into one case, so `.notFound` (404) and
//  `.permanent` (decode) are not separable here; both fall to `.transient`, preserving the
//  engine's current retry behavior. Narrowing that would require the (frozen) client to
//  surface the HTTP status.
//

import Foundation
import PhotoSourceKit

extension ImmichClient: PhotoSourceProviding {
    public func ensureReady() async throws {
        try await mapping { try await ensureServerSupported() }
    }

    public func collections() async throws -> [SourceCollection] {
        try await mapping {
            try await albums().map { album in
                SourceCollection(
                    id: album.id,
                    title: album.name,
                    // Advisory/estimated count is allowed (R9); absent → 0.
                    assetCount: album.assetCount ?? 0,
                    // Immich's album model exposes no cover asset id here → placeholder.
                    coverAssetID: nil
                )
            }
        }
    }

    public func assets(in collectionID: String) async throws -> [SourceAsset] {
        try await mapping {
            try await assets(albumID: collectionID).map { asset in
                // Immich `type` string passthrough; unknown strings degrade to `.other`.
                SourceAsset(id: asset.id, kind: MediaKind(rawValue: asset.type) ?? .other)
            }
        }
    }

    public func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data {
        try await mapping {
            switch fidelity {
            case .thumbnail: return try await thumbnail(assetID: assetID)
            case .preview: return try await preview(assetID: assetID)
            case .original: return try await original(assetID: assetID)
            }
        }
    }

    public func metadata(for assetID: String) async throws -> AssetMetadata {
        try await mapping {
            let info = try await assetInfo(assetID: assetID)
            // Same composition as PhotoInfoView: [city, country], drop empties, join ", ".
            let parts = [info.city, info.country].compactMap { $0 }.filter { !$0.isEmpty }
            let placeName = parts.isEmpty ? nil : parts.joined(separator: ", ")
            // ImmichClient's AssetInfo/ExifInfo carries no coordinates today → lat/lon nil.
            return AssetMetadata(
                capturedAt: info.takenAt,
                latitude: nil,
                longitude: nil,
                placeName: placeName
            )
        }
    }

    /// Runs `body`, translating any thrown error into a `SourceFailure` so callers only ever
    /// see the neutral taxonomy.
    private func mapping<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw ImmichSourceFailureMapping.failure(for: error)
        }
    }
}

/// Translates ImmichClient's error surface into the backend-neutral `SourceFailure` taxonomy.
/// Internal (not public) so it stays testable via `@testable import` without widening the
/// module's API. The `ImmichError` switch is exhaustive on purpose — a new case is a
/// deliberate taxonomy decision, not a silent fall-through.
enum ImmichSourceFailureMapping {
    static func failure(for error: any Error) -> SourceFailure {
        switch error {
        case let immich as ImmichError:
            return failure(for: immich)
        case let urlError as URLError:
            // ImmichClient converts URLError → `.unreachable`, but a raw URLError escaping
            // any future path is still a network hiccup → retry with backoff.
            return .transient(underlying: urlError)
        default:
            // The client contractually throws only ImmichError; anything else is an
            // unexpected contract violation → calm error, manual recovery.
            return .permanent(underlying: error)
        }
    }

    static func failure(for error: ImmichError) -> SourceFailure {
        switch error {
        case .unauthorized, .invalidShareLink, .shareLinkExpired, .wrongPassword, .passwordRequired:
            return .authentication
        case .unreachable, .invalidResponse:
            return .transient(underlying: error)
        case .serverTooOld:
            return .permanent(underlying: error)
        }
    }
}
