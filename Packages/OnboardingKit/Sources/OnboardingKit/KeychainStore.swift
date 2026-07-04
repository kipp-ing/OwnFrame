import Foundation
import Security

public protocol KeychainStore: Sendable {
    func save(_ apiKey: String) throws
    func read() -> String?
    func delete()
}

/// Real `KeychainStore` implementation using the Security API
/// (`kSecClassGenericPassword`, fixed service/account). The API key is never
/// stored in UserDefaults or logs (Constitution III).
public struct KeychainAPIKeyStore: KeychainStore {
    public enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    private let service: String
    private let account: String

    public init(
        service: String = "de.kippings.ImmichSlideshow.apiKey",
        account: String = "immich-api-key"
    ) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func save(_ apiKey: String) throws {
        // Atomic overwrite: update in place, only falling back to add when no item exists yet.
        // Avoids the delete-then-add gap where a crash between the two calls loses the key.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: Data(apiKey.utf8)] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = Data(apiKey.utf8)
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        guard updateStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
