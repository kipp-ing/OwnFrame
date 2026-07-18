import CloudKit
import Foundation

/// Real `SecretSyncStore` over CloudKit's private database. Every value is written through
/// `record.encryptedValues[...]` (never plaintext `record[...]`) — no custom crypto.
///
/// Thin adapter, correct by construction: tests exercise `InMemorySecretSyncStore`. Account /
/// network conditions map to `.iCloudUnavailable` so the consumer degrades silently to manual
/// entry (US2-3/4).
public final class CloudKitSecretSyncStore: SecretSyncStore, @unchecked Sendable {
    private let database: CKDatabase

    private let recordType = "FrameSecrets"
    private let recordID = CKRecord.ID(recordName: "frame-secrets")

    private enum Field {
        static let immichApiKey = "immichApiKey"
        static let mqttCredentials = "mqttCredentials"
        static let sharedLinkPasswords = "sharedLinkPasswords"
    }

    public init(container: CKContainer = .default()) {
        self.database = container.privateCloudDatabase
    }

    public func publish(_ secret: SyncedSecret) async throws {
        do {
            let record = try await fetchOrCreateRecord()
            apply(secret, to: record)
            _ = try await database.save(record)
        } catch let error as SecretSyncError {
            throw error
        } catch let error as CKError {
            throw Self.map(error)
        } catch {
            throw SecretSyncError.transport(error)
        }
    }

    public func fetch() async throws -> SyncedSecret? {
        do {
            let record = try await database.record(for: recordID)
            return decode(record)
        } catch let error as CKError {
            if error.code == .unknownItem { return nil }  // no record synced yet
            throw Self.map(error)
        } catch {
            throw SecretSyncError.transport(error)
        }
    }

    // MARK: - Record <-> SyncedSecret

    private func fetchOrCreateRecord() async throws -> CKRecord {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: recordType, recordID: recordID)
        }
    }

    private func apply(_ secret: SyncedSecret, to record: CKRecord) {
        record.encryptedValues[Field.immichApiKey] = secret.immichApiKey
        record.encryptedValues[Field.mqttCredentials] = secret.mqttCredentials
        record.encryptedValues[Field.sharedLinkPasswords] = Self.encodePasswords(secret.sharedLinkPasswords)
    }

    private func decode(_ record: CKRecord) -> SyncedSecret {
        SyncedSecret(
            immichApiKey: record.encryptedValues[Field.immichApiKey] as? String,
            mqttCredentials: record.encryptedValues[Field.mqttCredentials] as? Data,
            sharedLinkPasswords: Self.decodePasswords(record.encryptedValues[Field.sharedLinkPasswords] as? Data)
        )
    }

    private static func encodePasswords(_ passwords: [String: String]) -> Data? {
        guard !passwords.isEmpty else { return nil }
        return try? JSONEncoder().encode(passwords)
    }

    private static func decodePasswords(_ data: Data?) -> [String: String] {
        guard let data, let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    // MARK: - Error mapping

    private static func map(_ error: CKError) -> SecretSyncError {
        switch error.code {
        case .notAuthenticated,
             .accountTemporarilyUnavailable,
             .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .zoneBusy,
             .requestRateLimited:
            return .iCloudUnavailable
        case .unknownItem:
            return .notFound
        default:
            return .transport(error)
        }
    }
}
