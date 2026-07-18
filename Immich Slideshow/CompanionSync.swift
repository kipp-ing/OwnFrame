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
//  Coverage note: theme (ThemeSettings is not Codable — needs a DTO), MQTT credentials, and
//  per-source shared-link passwords are follow-ups (TODO); the primary server URL, source
//  library, cache budget, and Immich API key are mirrored here.
//

import ConfigSyncKit
import Foundation
import OnboardingKit
import SlideshowKit

@MainActor
struct CompanionSync {
    let config: any ConfigStore
    let sourceStore: any SourceLibraryStore
    let budgetStore: any CacheBudgetStore
    let keychain: any KeychainStore

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
        snapshot.cacheBudgetBytes = budgetStore.load().bytes
        return snapshot
    }

    private func snapshotSecret() -> SyncedSecret {
        SyncedSecret(immichApiKey: keychain.read())
    }
}
