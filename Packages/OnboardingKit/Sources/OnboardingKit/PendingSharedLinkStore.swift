import Foundation

public protocol PendingSharedLinkStore: Sendable {
    func savePendingURL(_ url: URL)
    func takePendingURL() -> URL?
}

public struct AppGroupPendingSharedLinkStore: PendingSharedLinkStore, @unchecked Sendable {
    public static let defaultSuiteName = "group.ing.kipp.Immich-Slideshow"
    public static let pendingURLKey = "pendingSharedLinkURL"

    private let defaults: UserDefaults?

    public init(suiteName: String = Self.defaultSuiteName) {
        guard !suiteName.isEmpty else {
            defaults = nil
            return
        }

        defaults = UserDefaults(suiteName: suiteName)
    }

    public func savePendingURL(_ url: URL) {
        defaults?.set(url.absoluteString, forKey: Self.pendingURLKey)
    }

    public func takePendingURL() -> URL? {
        guard let defaults else {
            return nil
        }

        let raw = defaults.string(forKey: Self.pendingURLKey)
        defaults.removeObject(forKey: Self.pendingURLKey)
        guard let raw else {
            return nil
        }

        return URL(string: raw)
    }
}

public final class InMemoryPendingSharedLinkStore: PendingSharedLinkStore, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingURL: URL?

    public init(pendingURL: URL? = nil) {
        self.pendingURL = pendingURL
    }

    public func savePendingURL(_ url: URL) {
        lock.withLock {
            pendingURL = url
        }
    }

    public func takePendingURL() -> URL? {
        lock.withLock {
            let url = pendingURL
            pendingURL = nil
            return url
        }
    }
}
