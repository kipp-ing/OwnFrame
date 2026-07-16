import Foundation

/// Fixed slideshow plumbing parameters. The per-photo display duration is no longer
/// here — it lives in `ThemeSettings.duration` and is read live by the engine (008).
/// What remains is prefetch/cache tuning that is not user-facing.
public struct SlideshowConfig: Sendable, Equatable {
    /// How many images ahead to prefetch (1–2).
    public var prefetchDepth: Int
    /// Maximum number of images held in the cache at once.
    public var cacheLimit: Int
    /// How often the active source's asset list is re-fetched while foregrounded
    /// (310, FR-310-06). Fixed default by design — deliberately not a setting.
    public var refreshInterval: Duration
    /// Whether a launch-time `.authentication` failure may still play the remembered
    /// snapshot (320 stale-beats-broken). True for server-credential backends (Immich:
    /// an expired key is a server problem). The Photos factory sets false — a photo-access
    /// revocation is a privacy statement, and cached copies must not defy it (900, US3-3/4).
    public var snapshotMasksAuthenticationFailures: Bool

    public init(
        prefetchDepth: Int, cacheLimit: Int, refreshInterval: Duration = .seconds(3600),
        snapshotMasksAuthenticationFailures: Bool = true
    ) {
        precondition(prefetchDepth >= 1, "prefetchDepth must be >= 1")
        precondition(cacheLimit >= prefetchDepth + 1, "cacheLimit must be >= prefetchDepth + 1")
        precondition(refreshInterval > .zero, "refreshInterval must be > 0")
        self.prefetchDepth = prefetchDepth
        self.cacheLimit = cacheLimit
        self.refreshInterval = refreshInterval
        self.snapshotMasksAuthenticationFailures = snapshotMasksAuthenticationFailures
    }

    /// Pinned defaults (data-model.md).
    public static let `default` = SlideshowConfig(
        prefetchDepth: 2,
        cacheLimit: 5
    )
}
