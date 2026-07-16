// PhotoLibraryProvider.swift — PhotoKit-backed PhotoSourceProviding as pure logic over PhotoLibraryGateway (spec 900).

import Foundation
import PhotoSourceKit

/// The Photos backend's `PhotoSourceProviding` conformance. Holds no PhotoKit — every real
/// operation goes through `PhotoLibraryGateway`, so this whole type is host-testable (R4).
/// Its job is the authorization gate (R5, per the data-model "PhotoAuthorizationState" table)
/// plus mapping gateway failures onto the neutral `SourceFailure` taxonomy (R3).
///
/// Concurrency: a `final class` marked `@unchecked Sendable`. Its two configuration inputs are
/// immutable `let`s; the change-observer registration state (`storedHandler`,
/// `forwardedToGateway`) is mutable and guarded by `changeHandlerLock` (house `NSLock` pattern).
/// That deferral state exists so registering the real PhotoKit observer — which fires the TCC
/// prompt when access was never granted — is held back until access is actually granted
/// (FR-900-04): the prompt must only ever appear at the picker moment. All gateway calls happen
/// outside the lock, so the lock never nests with the gateway's own synchronization.
public final class PhotoLibraryProvider: PhotoSourceProviding, @unchecked Sendable {

    private let gateway: any PhotoLibraryGateway

    /// The source this provider serves, so `ensureReady()` — which the protocol gives no
    /// argument — can apply the per-source limited-mode gate: a regular album fails under
    /// limited access while `PhotoLibrarySource.selectedPhotosID` keeps working. `nil` is the
    /// enumeration-only shape (the picker calling `collections()`), where the album/selected
    /// distinction does not apply and limited readiness is (correctly) refused.
    private let collectionID: String?

    /// Guards the deferred change-observer registration state below (house `NSLock` pattern).
    private let changeHandlerLock = NSLock()

    /// The change handler the app registered, retained until it can be forwarded prompt-free.
    private var storedHandler: (@Sendable () -> Void)?

    /// Whether `storedHandler` has already been handed to the gateway (the real observer is
    /// live). Prevents a second registration when `ensureReady()` runs again, and tells
    /// `setChangeHandler(nil)` whether an unregister actually needs to reach the gateway.
    private var forwardedToGateway = false

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
            break
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
        // Reached only on a success path — access is now granted, so registering the observer
        // can no longer prompt. Bring a handler that was deferred at registration time (auth was
        // then `.notDetermined`/`.denied`) alive exactly once. `ensureReady()` runs at engine
        // start, every refresh, and manual retry, so the observer wakes right after the grant.
        forwardPendingChangeHandler()
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

    /// Registers (or clears with `nil`) the engine-refresh wiring (FR-900-09): the gateway fires
    /// the handler on PhotoKit library changes so the engine re-fetches the source.
    ///
    /// Registration is auth-gated so it can never fire the system permission prompt (FR-900-04):
    /// the gateway registers a real `PHPhotoLibraryChangeObserver`, which triggers TCC when
    /// access was never granted. The handler is forwarded immediately only under a granted level
    /// (`.full`/`.limited`, where registration is prompt-free); under `.notDetermined`/`.denied`
    /// it is stored and deferred until `ensureReady()` sees access granted. Clearing with `nil`
    /// forwards the unregister only if a handler was actually forwarded, then resets the state.
    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        guard let handler else {
            let shouldUnregister: Bool = changeHandlerLock.withLock {
                storedHandler = nil
                defer { forwardedToGateway = false }
                return forwardedToGateway
            }
            if shouldUnregister {
                gateway.setChangeHandler(nil)
            }
            return
        }

        // Any granted level makes registering the observer prompt-free; only then forward now.
        let isGranted: Bool
        switch gateway.authorizationStatus() {
        case .full, .limited: isGranted = true
        case .notDetermined, .denied: isGranted = false
        }

        let toForward: (@Sendable () -> Void)? = changeHandlerLock.withLock {
            storedHandler = handler
            forwardedToGateway = isGranted
            return isGranted ? handler : nil
        }
        if let toForward {
            gateway.setChangeHandler(toForward)
        }
    }

    /// Forwards a stored-but-not-yet-forwarded handler to the gateway exactly once, from an
    /// `ensureReady()` success path (access is granted, so registration can no longer prompt).
    private func forwardPendingChangeHandler() {
        let toForward: (@Sendable () -> Void)? = changeHandlerLock.withLock {
            guard let handler = storedHandler, !forwardedToGateway else { return nil }
            forwardedToGateway = true
            return handler
        }
        if let toForward {
            gateway.setChangeHandler(toForward)
        }
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
