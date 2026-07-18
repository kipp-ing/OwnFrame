//
//  CompanionSync.swift
//  Immich Slideshow
//
//  iPad companion writer for the Apple TV port (topic 1000, FR-1000-06/12). Mirrors the
//  non-secret configuration to iCloud key-value storage and secrets to CloudKit encrypted
//  fields so the Apple TV app can prefill onboarding (ConfigConsumer) and hydrate secrets into
//  its local keychain. The publish LOGIC lives in ConfigSyncKit and is unit-tested there
//  (ConfigPublisher); this is the thin iPad-side gather + call.
//
//  Real sync is a device gate: it needs the iCloud KVS + CloudKit entitlements and a
//  signed-in iCloud account. On the simulator (no iCloud) the CloudKit store is not even
//  instantiated (CKContainer.default() would abort without the entitlement), so secret publish
//  degrades to a no-op and KVS simply never syncs — the code lands and stays crash-safe.
//
//  Payload coverage: the non-secret channel carries the server URL, source library, theme
//  (ThemeSettings JSON), cache budget, and MQTT broker host/port; the secret channel carries
//  the Immich API key, the MQTT credentials JSON blob, and per-source shared-link passwords.
//  Every gather is best-effort (`try?`) so a single store hiccup never blocks the publish.
//

import BrokerSetupKit
import ConfigSyncKit
import Foundation
import OnboardingKit
import SlideshowKit
import ThemeKit

@MainActor
struct CompanionSync {
    let config: any ConfigStore
    let sourceStore: any SourceLibraryStore
    let budgetStore: any CacheBudgetStore
    let keychain: any KeychainStore
    let themeStore: UserDefaultsThemeStore
    let brokerStore: any BrokerSettingsStore
    /// Per-source shared-link passwords, keyed by `Source.id` (OnboardingKit keychain store).
    let sharedLinkSecretStore: any SharedLinkSecretStore

    /// Gather the current config + secret and publish them to the sync channels. Best-effort;
    /// never throws (ConfigPublisher swallows transport failures, non-secret save still runs).
    func publish() async {
        let publisher = ConfigPublisher(
            configStore: UbiquitousKVSConfigSyncStore(),
            secretStore: Self.makeSecretStore()
        )
        await publisher.publish(config: snapshotConfig(), secret: snapshotSecret())
    }

    /// CloudKit only when an iCloud account is present — avoids `CKContainer.default()` aborting
    /// without the entitlement/account on the simulator. The CloudKit path is exercised on a
    /// real device with the iCloud entitlement (device-gated, FR-1000-12).
    private static func makeSecretStore() -> any SecretSyncStore {
        if FileManager.default.ubiquityIdentityToken != nil {
            return CloudKitSecretSyncStore()
        }
        return InMemorySecretSyncStore()
    }

    private func snapshotConfig() -> SyncedConfig {
        var snapshot = SyncedConfig()
        snapshot.baseURL = config.loadBaseURL()
        snapshot.sourceLibrary = try? JSONEncoder().encode(sourceStore.load())
        // Theme is opaque JSON owned by ThemeKit (ThemeSettings is Codable additively).
        snapshot.theme = try? JSONEncoder().encode(themeStore.settings)
        snapshot.cacheBudgetBytes = budgetStore.load().bytes
        // MQTT broker host/port are non-secret; the credentials ride the secret channel below.
        if let broker = brokerStore.load() {
            snapshot.brokerHost = broker.host
            snapshot.brokerPort = broker.port
        }
        return snapshot
    }

    private func snapshotSecret() -> SyncedSecret {
        var secret = SyncedSecret(immichApiKey: keychain.read())

        // MQTT credentials as a `{username, password}` JSON blob. The keychain store only
        // exposes decoded `BrokerSettings`, so we re-encode the two credential fields here
        // (matching the store's private `Credentials` shape) rather than reading raw Data.
        if let broker = brokerStore.load() {
            secret.mqttCredentials = try? JSONEncoder().encode(
                MQTTCredentialsPayload(username: broker.username, password: broker.password)
            )
        }

        // Per-source shared-link passwords, keyed by `Source.id`. Only `.sharedLink` sources
        // can have one; sources with no stored password are skipped (never an empty entry).
        var passwords: [String: String] = [:]
        for source in sourceStore.load().sources {
            guard case .sharedLink = source.kind else { continue }
            if let password = sharedLinkSecretStore.readPassword(forSourceID: source.id) {
                passwords[source.id] = password
            }
        }
        secret.sharedLinkPasswords = passwords

        return secret
    }
}

/// The MQTT credential wire shape mirrored onto the CloudKit secret channel. Field order
/// matches `KeychainBrokerSettingsStore`'s private `Credentials` so the blob is interchangeable.
private struct MQTTCredentialsPayload: Encodable {
    let username: String
    let password: String
}
