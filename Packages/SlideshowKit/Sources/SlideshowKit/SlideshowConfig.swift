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

    public init(prefetchDepth: Int, cacheLimit: Int, refreshInterval: Duration = .seconds(3600)) {
        precondition(prefetchDepth >= 1, "prefetchDepth must be >= 1")
        precondition(cacheLimit >= prefetchDepth + 1, "cacheLimit must be >= prefetchDepth + 1")
        precondition(refreshInterval > .zero, "refreshInterval must be > 0")
        self.prefetchDepth = prefetchDepth
        self.cacheLimit = cacheLimit
        self.refreshInterval = refreshInterval
    }

    /// Pinned defaults (data-model.md).
    public static let `default` = SlideshowConfig(
        prefetchDepth: 2,
        cacheLimit: 5
    )
}
