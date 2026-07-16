// PhotoLibraryGateway.swift — the PhotoKit seam contract; only PHKitGateway (a later task) imports Photos (spec 900).

import Foundation
import PhotoSourceKit

/// The narrow surface `PhotoLibraryProvider` talks to. Everything the provider needs from
/// PhotoKit is expressed here in backend-neutral `PhotoSourceKit` types, so the provider —
/// and its whole test suite — never imports Photos (R4). Exactly one production type,
/// `PHKitGateway`, implements this and is the only file allowed to `import Photos`
/// (enforced forever by `SeamTests`).
public protocol PhotoLibraryGateway: Sendable {
    /// Current `.readWrite` access level, re-read on every readiness check (R5). The legacy
    /// no-argument API reports limited as authorized, so the access-level API is mandatory.
    func authorizationStatus() -> PhotoAuthorizationState

    /// Prompts for `.readWrite` access and returns the resulting level (picker entry, FR-900-04).
    func requestAuthorization() async -> PhotoAuthorizationState

    /// User albums + iCloud Shared Albums as pickable collections (full access only, R9).
    func fetchCollections() throws -> [SourceCollection]

    /// Rotation descriptors for a collection (PHAsset enumeration is windowed internally).
    /// Throws `PhotoLibraryGatewayError.collectionNotFound` when the collection is gone.
    func fetchAssets(in collectionID: String) throws -> [SourceAsset]

    /// The limited-mode granted-assets pool, addressed by `PhotoLibrarySource.selectedPhotosID`.
    func fetchGrantedAssets() throws -> [SourceAsset]

    /// Final-quality image bytes only (R6 — the degraded-delivery guard lives in the adapter).
    func requestImageData(assetID: String, fidelity: ImageFidelity) async throws -> Data

    /// Capture date + coordinates; `placeName` is always `nil` from PhotoKit (R7, no geocoding).
    func fetchMetadata(assetID: String) throws -> AssetMetadata

    /// Registers (or clears with `nil`) the library-change observer that drives engine refresh
    /// (FR-900-09). Consumed by a later wiring slice.
    func setChangeHandler(_ handler: (@Sendable () -> Void)?)

    /// Presents the system's limited-library "manage selection" UI (US3-2). Only meaningful
    /// under `.limited`; a no-op wherever the platform surface is unavailable (fakes, macOS).
    @MainActor func presentManageSelection()
}

/// The `.readWrite` authorization levels the provider gates on (R5). `notDetermined`
/// transitions via `requestAuthorization()`; any level can later move to any other through
/// iOS Settings or the periodic re-prompt, which is why the provider re-reads on every edge.
/// The platform's add-only grant maps to `.denied` here (no read access, FR-900-04).
public enum PhotoAuthorizationState: Sendable {
    case notDetermined
    case full
    case limited
    case denied
}

/// Typed failures a gateway raises that carry a specific neutral meaning. Everything else a
/// gateway throws is opaque to the provider and becomes `SourceFailure.transient`.
public enum PhotoLibraryGatewayError: Error, Sendable {
    /// The requested collection is gone (deleted / unshared / upgraded to the new iCloud
    /// format). The provider maps this to `SourceFailure.notFound` — the vanish state (FR-900-16).
    case collectionNotFound
}
