//
//  PhotoSourceProviding.swift
//  PhotoSourceKit
//
//  900 — the load-bearing backend-neutral contract (R1). The engine consumes only this;
//  ImmichClient and PhotoLibraryKit are peer conformers (FR-900-01). Every method reports
//  failure as `SourceFailure` so retry/vanish/auth semantics stay identical across backends.
//

import Foundation

public protocol PhotoSourceProviding: Sendable {
    /// Precondition gate (R10): Immich = server-version gate; Photos = authorization.
    /// Throws `SourceFailure.authentication` / `.transient`.
    func ensureReady() async throws

    /// All pickable collections (R9). Immich: albums. Photos: user albums + iCloud
    /// Shared Albums (full access only — throws `.authentication` under limited).
    func collections() async throws -> [SourceCollection]

    /// Rotation content for one collection. `PhotoLibrarySource.selectedPhotosID`
    /// resolves to the granted-assets pool. Throws `.notFound` on vanish (FR-900-16).
    /// Returns fully materialized descriptors (id+kind only — tiny even at 10k assets,
    /// matching today's Immich behavior); "windowed/lazy" in the spec's huge-album edge
    /// case refers to the gateway's internal PHAsset enumeration, never to image data.
    func assets(in collectionID: String) async throws -> [SourceAsset]

    /// Final-quality image bytes (FR-900-07 — never degraded). Network allowed (FR-900-06).
    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data

    /// Overlay/HA metadata (FR-900-10/11). Absent fields are `nil`, never faked.
    func metadata(for assetID: String) async throws -> AssetMetadata
}
