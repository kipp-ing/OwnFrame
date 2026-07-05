import Foundation

public struct CachedMetadata: Sendable, Equatable {
    public var takenAt: Date?
    public var city: String?
    public var state: String?
    public var country: String?

    public init(takenAt: Date?, city: String?, state: String?, country: String?) {
        self.takenAt = takenAt
        self.city = city
        self.state = state
        self.country = country
    }
}

public final class MetadataCache: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var storage: [String: CachedMetadata] = [:]
    private var leastToMostRecent: [String] = []

    public init(limit: Int) {
        precondition(limit >= 1, "limit must be >= 1")
        self.limit = limit
    }

    public func metadata(for assetID: String) -> CachedMetadata? {
        lock.withLock {
            guard let metadata = storage[assetID] else {
                return nil
            }

            markRecentlyUsed(assetID)
            return metadata
        }
    }

    public func store(_ metadata: CachedMetadata, for assetID: String) {
        lock.withLock {
            storage[assetID] = metadata
            markRecentlyUsed(assetID)

            while storage.count > limit, let evicted = leastToMostRecent.first {
                leastToMostRecent.removeFirst()
                storage[evicted] = nil
            }
        }
    }

    public var count: Int {
        lock.withLock {
            storage.count
        }
    }

    private func markRecentlyUsed(_ assetID: String) {
        leastToMostRecent.removeAll { $0 == assetID }
        leastToMostRecent.append(assetID)
    }
}

extension NSLock {
    @discardableResult
    fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
