// PhotoLibraryProvider.swift — PhotoKit-backed PhotoSourceProviding as pure logic over PhotoLibraryGateway (spec 900).

import Foundation
import PhotoSourceKit

/// The Photos backend's `PhotoSourceProviding` conformance. Holds no PhotoKit — every real
/// operation goes through `PhotoLibraryGateway`, so this whole type is host-testable (R4).
/// Its job is the authorization gate (R5, per the data-model "PhotoAuthorizationState" table)
/// plus mapping gateway failures onto the neutral `SourceFailure` taxonomy (R3).
///
/// Concurrency: a `final class` whose only stored state is two immutable `let`s of `Sendable`
/// type, so it is `Sendable` without a lock — safe to hand to the MainActor engine and call
/// from its async paths. (An actor would force every gateway call cross-actor and buy nothing,
/// since the provider itself owns no mutable state.)
public final class PhotoLibraryProvider: PhotoSourceProviding {

    private let gateway: any PhotoLibraryGateway

    /// The source this provider serves, so `ensureReady()` — which the protocol gives no
    /// argument — can apply the per-source limited-mode gate: a regular album fails under
    /// limited access while `PhotoLibrarySource.selectedPhotosID` keeps working. `nil` is the
    /// enumeration-only shape (the picker calling `collections()`), where the album/selected
    /// distinction does not apply and limited readiness is (correctly) refused.
    private let collectionID: String?

    /// - Parameters:
    ///   - gateway: the PhotoKit seam (only `PHKitGateway` imports Photos).
    ///   - collectionID: the source this provider serves, or `nil` for enumeration-only use.
    public init(gateway: any PhotoLibraryGateway, collectionID: String? = nil) {
        self.gateway = gateway
        self.collectionID = collectionID
    }

    // MARK: - PhotoSourceProviding

    public func ensureReady() async throws {
        // R5: authorization is re-read from the gateway on every readiness check, never cached.
        switch gateway.authorizationStatus() {
        case .full:
            return
        case .limited:
            // Only the granted-assets pool is serviceable under limited access; an album
            // source (or an enumeration-only provider) surfaces the calm auth gate — this is
            // the US3-4 mid-life full→limited downgrade.
            guard collectionID == PhotoLibrarySource.selectedPhotosID else {
                throw SourceFailure.authentication
            }
        case .notDetermined, .denied:
            throw SourceFailure.authentication
        }
    }

    public func collections() async throws -> [SourceCollection] {
        // Enumeration requires full access: limited is not enumerable (platform), and
        // denied / notDetermined obviously so — all three surface as the calm auth gate.
        guard case .full = gateway.authorizationStatus() else {
            throw SourceFailure.authentication
        }
        return try mappingGatewayFailures { try gateway.fetchCollections() }
    }

    public func assets(in collectionID: String) async throws -> [SourceAsset] {
        let authorization = gateway.authorizationStatus()

        if collectionID == PhotoLibrarySource.selectedPhotosID {
            // The granted-assets pool is available under full (equals the whole grant) and
            // limited access alike; it is only unavailable when nothing is granted.
            switch authorization {
            case .full, .limited:
                return try mappingGatewayFailures { try gateway.fetchGrantedAssets() }
            case .notDetermined, .denied:
                throw SourceFailure.authentication
            }
        }

        // A regular album is enumerable only under full access.
        switch authorization {
        case .full:
            return try mappingGatewayFailures { try gateway.fetchAssets(in: collectionID) }
        case .limited, .notDetermined, .denied:
            throw SourceFailure.authentication
        }
    }

    public func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data {
        try await mappingGatewayFailures {
            try await gateway.requestImageData(assetID: assetID, fidelity: fidelity)
        }
    }

    public func metadata(for assetID: String) async throws -> AssetMetadata {
        try mappingGatewayFailures { try gateway.fetchMetadata(assetID: assetID) }
    }

    // MARK: - Change observation

    /// Pass-through for the engine-refresh wiring a later slice consumes (FR-900-09): the
    /// gateway fires this on PhotoKit library changes so the engine re-fetches the source.
    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        gateway.setChangeHandler(handler)
    }

    // MARK: - Error mapping

    private func mappingGatewayFailures<T>(_ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch { throw Self.mapGatewayError(error) }
    }

    private func mappingGatewayFailures<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch { throw Self.mapGatewayError(error) }
    }

    /// Translates a gateway failure into the neutral `SourceFailure` taxonomy (R3): an
    /// already-typed `SourceFailure` passes through verbatim, the gateway's not-found signal
    /// becomes the `.notFound` vanish state, and anything else is treated as `.transient`
    /// (iCloud fetch errors, throttling) so the engine retries with backoff.
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
