// ImageDeliveryRules.swift — the pure degraded-delivery decision, extracted from PHKitGateway
// so it is host-testable (R4, FR-900-07). Deliberately imports nothing from Photos: the seam
// guard (SeamTests) keeps `import Photos` confined to PHKitGateway, and this file must stay on
// the neutral side of that seam.

/// How to treat one PhotoKit image callback. `PHImageManager` may fire more than once per
/// request (a degraded progressive preview before the final frame); this collapses the two
/// signals PhotoKit hands back — the degraded flag and whether a payload arrived — into the
/// single action the gateway takes.
enum ImageDeliveryRules {

    /// The action for a single image callback.
    enum Decision: Equatable {
        /// A degraded progressive preview — drop it and wait for the final callback (FR-900-07:
        /// never show a non-final frame). Also the outcome for a degraded callback with no bytes.
        case ignore
        /// Final-quality bytes — hand them to the frame.
        case deliver
        /// The final callback carried no payload — surface a transient failure so the engine
        /// retries with backoff (FR-900-06).
        case fail
    }

    /// Degraded dominates: any degraded callback is ignored regardless of payload. Otherwise a
    /// payload is delivered and its absence is a failure. With `.highQualityFormat` requests the
    /// final callback is the only non-degraded one, so this covers the whole callback surface.
    static func decision(isDegraded: Bool, hasPayload: Bool) -> Decision {
        if isDegraded { return .ignore }
        return hasPayload ? .deliver : .fail
    }
}
