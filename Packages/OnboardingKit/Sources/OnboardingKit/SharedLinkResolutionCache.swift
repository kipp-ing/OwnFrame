import Foundation
import ImmichClient
import Security

/// The last resolution a shared-link source's slug successfully resolved to (share key +
/// album id). `ActiveSourceResolver` falls back to this when the live resolve fails because
/// the network is unreachable, so a cold launch while offline (issue #80) still reaches the
/// slideshow instead of stalling on a black screen forever.
///
/// The share key grants server access exactly like an API key, so this lives in the Keychain —
/// never UserDefaults (Constitution III).
public protocol SharedLinkResolutionStore: Sendable {
    func save(_ resolution: SharedLinkResolution, forSourceID id: String)
    func read(forSourceID id: String) -> SharedLinkResolution?
    /// Like a link password, a cached share key never outlives its source (FR-120-14).
    func delete(forSourceID id: String)
}

public struct KeychainSharedLinkResolutionStore: SharedLinkResolutionStore {
    private let service: String

    public init(service: String = "de.kippings.ImmichSlideshow.sharedLinkResolution") {
        self.service = service
    }

    private func baseQuery(forSourceID id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
    }

    public func save(_ resolution: SharedLinkResolution, forSourceID id: String) {
        guard let data = try? JSONEncoder().encode(resolution) else { return }
        let query = baseQuery(forSourceID: id)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func read(forSourceID id: String) -> SharedLinkResolution? {
        var query = baseQuery(forSourceID: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SharedLinkResolution.self, from: data)
    }

    public func delete(forSourceID id: String) {
        SecItemDelete(baseQuery(forSourceID: id) as CFDictionary)
    }
}

public final class InMemorySharedLinkResolutionStore: SharedLinkResolutionStore, @unchecked Sendable {
    private var resolutionsBySourceID: [String: SharedLinkResolution]

    public init(resolutionsBySourceID: [String: SharedLinkResolution] = [:]) {
        self.resolutionsBySourceID = resolutionsBySourceID
    }

    public func save(_ resolution: SharedLinkResolution, forSourceID id: String) {
        resolutionsBySourceID[id] = resolution
    }

    public func read(forSourceID id: String) -> SharedLinkResolution? {
        resolutionsBySourceID[id]
    }

    public func delete(forSourceID id: String) {
        resolutionsBySourceID[id] = nil
    }
}
