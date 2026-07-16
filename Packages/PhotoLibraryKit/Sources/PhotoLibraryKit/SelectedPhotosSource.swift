// SelectedPhotosSource.swift — the limited-mode "Selected Photos" pseudo-collection (spec 900, T028). Zero PhotoKit.

import Foundation
import PhotoSourceKit

/// The limited-mode "Selected Photos" pseudo-collection (US3-2): the granted-assets pool
/// presented to the picker as one pickable source. It is not a real PhotoKit collection —
/// enumeration still goes through the same `PhotoLibraryGateway` seam (`fetchGrantedAssets`),
/// so this surface, like the provider, never imports Photos (R4).
public enum SelectedPhotosSource {

    /// Builds the single pickable pseudo-collection the picker offers under limited access
    /// (and under full, where it equals the whole grant).
    ///
    /// - id = `PhotoLibrarySource.selectedPhotosID`, title = "Selected Photos".
    /// - assetCount = the granted-pool size the gateway reports — all kinds; the engine, not
    ///   this surface, filters to still images later (FR-900-08).
    /// - coverAssetID = the first granted asset, or `nil` for an empty grant (the row is still
    ///   offered so the user can manage the selection).
    ///
    /// Authorization is re-read on every call (R5): `.denied` / `.notDetermined` throw the calm
    /// `SourceFailure.authentication` gate without touching the gateway; `.limited` / `.full`
    /// fetch the pool. Gateway failures map onto the neutral taxonomy exactly as
    /// `PhotoLibraryProvider` does (R3) — an opaque error becomes `.transient` (retryable).
    public static func collection(using gateway: any PhotoLibraryGateway) throws -> SourceCollection {
        switch gateway.authorizationStatus() {
        case .limited, .full:
            break
        case .notDetermined, .denied:
            throw SourceFailure.authentication
        }

        let assets: [SourceAsset]
        do { assets = try gateway.fetchGrantedAssets() }
        catch { throw mapGatewayError(error) }

        return SourceCollection(
            id: PhotoLibrarySource.selectedPhotosID,
            title: "Selected Photos",
            assetCount: assets.count,
            coverAssetID: assets.first?.id
        )
    }

    /// Mirrors `PhotoLibraryProvider.mapGatewayError` (R3): an already-typed `SourceFailure`
    /// passes through verbatim, the gateway's not-found signal becomes `.notFound`, and
    /// anything opaque (iCloud fetch errors, throttling) becomes `.transient` for backoff.
    private static func mapGatewayError(_ error: any Error) -> SourceFailure {
        if let failure = error as? SourceFailure {
            return failure
        }
        if let gatewayError = error as? PhotoLibraryGatewayError {
            switch gatewayError {
            case .collectionNotFound:
                return .notFound
            }
        }
        return .transient(underlying: error)
    }
}
