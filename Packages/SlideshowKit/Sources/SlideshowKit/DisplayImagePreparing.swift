import Foundation

/// Decode-ahead seam: the engine hands an asset's display bytes over BEFORE the
/// photo swap so the bitmap can decode off the display path. Without it the view
/// builds a lazily-decoded image whose first render stalls the main thread at
/// the exact moment both photo copies are animating through the cross-fade —
/// the swap-boundary hitch in the Ken Burns drift.
public protocol DisplayImagePreparing: Sendable {
    /// Idempotent; implementations decide caching/eviction. Called for the
    /// current photo on show and for every prefetched photo as its bytes land.
    func prepare(assetID: String, data: Data) async
}
