import Foundation
import Security

/// Keychain-backed ``FrameIdentityStorage`` — the reason a frame keeps its Home Assistant
/// identity across a delete/reinstall (700 US3 / FR-700-16).
///
/// ## Why the Keychain for something that isn't a secret
///
/// It is chosen for **durability, not confidentiality**. iOS wipes an app's container on delete
/// but leaves its Keychain items, and that outliving is the entire requirement here. Notably this
/// app already relies on that property: the broker password survives a reinstall while host/port
/// (UserDefaults) do not. Identity behaving like the credential it sits beside is what makes a
/// reinstalled frame rejoin Home Assistant as itself.
///
/// The value is not sensitive, so no protection class beyond availability is warranted:
///
/// - `kSecAttrAccessibleAfterFirstUnlock` — a frame must be able to re-register after an
///   unattended reboot (power cut) without someone walking over to unlock it. `WhenUnlocked`
///   would strand exactly the device this app is for. It stays off-device-backup-restorable to
///   another device only in the sense below.
/// - `kSecAttrSynchronizable = false` — **required by FR-700-19**: iCloud Keychain sync would
///   hand two frames the same identity, which is the collision this spec exists to prevent.
///
/// Failures are deliberately non-fatal. If the Keychain is unavailable, `loadIdentity()` returns
/// nil and the resolver mints a working identity for this launch; the frame keeps running and
/// controlling photos, per FR-700-03's "never block the slideshow" posture.
public struct KeychainFrameIdentityStorage: FrameIdentityStorage {
    private static let account = "frame-identity"

    private let service: String

    /// - Parameter service: Keychain service name. Distinct per platform so an iPad and an Apple
    ///   TV restored from the same backup cannot read each other's identity (FR-1000-08).
    public init(service: String = "de.kippings.ImmichSlideshow.frameIdentity") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    public func loadIdentity() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let identity = String(data: data, encoding: .utf8),
              !identity.isEmpty
        else { return nil }

        return identity
    }

    public func saveIdentity(_ identity: String) {
        guard let data = identity.data(using: .utf8) else { return }

        // Delete-then-add rather than update: this runs at most once per frame, and an
        // add over a stale duplicate would fail with errSecDuplicateItem.
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // Ignored on purpose: a Keychain failure must not stop the frame from running. The
        // resolver's value still serves this launch; the next launch retries the write.
        _ = SecItemAdd(attributes as CFDictionary, nil)
    }
}
