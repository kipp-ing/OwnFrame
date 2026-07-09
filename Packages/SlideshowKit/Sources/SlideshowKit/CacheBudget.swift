import Foundation

/// The user-selected maximum size of the disk image cache (320, FR-320-04): fixed
/// steps only — no free-form entry for a number nobody should have to think about.
public struct CacheBudget: Sendable, Equatable {
    public var bytes: Int64

    public init(bytes: Int64) {
        self.bytes = bytes
    }

    private static let megabyte: Int64 = 1_000_000

    /// The Settings picker options: 100 MB, 250 MB, 500 MB, 1 GB, 2 GB. Decimal
    /// megabytes so the label matches what `ByteCountFormatter` displays.
    public static let steps: [CacheBudget] = [100, 250, 500, 1_000, 2_000].map {
        CacheBudget(bytes: $0 * megabyte)
    }

    public static let `default` = CacheBudget(bytes: 500 * megabyte)
}

public protocol CacheBudgetStore: Sendable {
    func load() -> CacheBudget
    func save(_ budget: CacheBudget)
}

/// One non-secret integer in UserDefaults (same shape as HAPublishOptions —
/// storage policy is not a display preference, so it stays out of ThemeSettings).
public final class UserDefaultsCacheBudgetStore: CacheBudgetStore, @unchecked Sendable {
    private static let key = "slideshow.cacheBudgetBytes"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> CacheBudget {
        guard let number = defaults.object(forKey: Self.key) as? NSNumber else {
            return .default
        }
        return CacheBudget(bytes: number.int64Value)
    }

    public func save(_ budget: CacheBudget) {
        defaults.set(NSNumber(value: budget.bytes), forKey: Self.key)
    }
}
