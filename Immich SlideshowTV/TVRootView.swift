//
//  TVRootView.swift
//  Immich SlideshowTV
//
//  Topic 1000 composition root + routing. Reuses the shared OnboardingKit view models and
//  the backend-neutral engine; only the tvOS views are new. Non-secret config prefills from
//  iCloud key-value storage via ConfigSyncKit (FR-1000-06); secret hydration over CloudKit
//  encrypted fields (FR-1000-12) runs on FRESH installs only (a configured frame's local
//  keychain is never overwritten by stale synced values) and is entitlement-gated via
//  `SecretSyncStoreFactory`, so the manual path always remains complete (US2-3/4). The
//  shared-link path is the primary, lowest-friction tvOS setup (one URL) and is driven by
//  SourceLibraryViewModel's real resolve-first flow (topic 210 semantics).
//

import BrokerSetupKit
import ConfigSyncKit
import HAControlKit
import HAControlMQTT
import ImmichClient
import OnboardingKit
import PowerKit
import SlideshowKit
import SwiftUI
import ThemeKit
import UIKit

@main
struct ImmichSlideshowTVApp: App {
    @State private var model = TVAppModel()

    var body: some Scene {
        WindowGroup {
            TVRootView(model: model)
                .task { await model.start() }
        }
    }
}

struct TVRootView: View {
    @Bindable var model: TVAppModel
    @State private var showBrokerSetup = false

    var body: some View {
        switch model.route {
        case .loading:
            ZStack { Color.black.ignoresSafeArea(); ProgressView().tint(.white) }
        case .slideshow:
            if let slideshow = model.slideshow {
                TVSlideshowView(
                    viewModel: slideshow,
                    screen: model.screen,
                    powerManager: model.powerManager,
                    themeStore: model.themeStore,
                    startHA: { await model.startHA() },
                    stopHA: { await model.stopHA() },
                    isCurrentGeneration: { model.slideshow === slideshow },
                    onSettings: { showBrokerSetup = true }
                )
                .id(ObjectIdentifier(slideshow))
                .fullScreenCover(isPresented: $showBrokerSetup) {
                    TVBrokerSetupView(onDone: { showBrokerSetup = false })
                }
            } else {
                onboarding
            }
        case .resolveFailed:
            TVResolveRetryView(onRetry: { Task { await model.evaluateGate() } })
        case .onboarding:
            onboarding
        }
    }

    @ViewBuilder
    private var onboarding: some View {
        // Intercept the shared-link step with the real resolve-first flow; reuse the shared
        // TVOnboardingView for choice / server / album / confirm.
        if model.onboarding.step == .sharedLinkSetup {
            TVSharedLinkEntryView(model: model)
        } else {
            TVOnboardingView(
                viewModel: model.onboarding,
                onFinished: { Task { await model.finishOnboarding() } },
                onSelectAlbum: { model.selectAlbum($0) }
            )
        }
    }
}

/// A configured frame whose active source failed to resolve (network blip, server down,
/// cold boot before Wi-Fi): calm copy, an auto-retry every 10 s, and a focusable manual
/// retry — never a dead-end black screen, never a bounce into onboarding (FR-1000-04).
struct TVResolveRetryView: View {
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Can't reach your photos right now")
                    .font(.title2.weight(.semibold))
                Text("Check that the Apple TV is online. Retrying automatically…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button("Retry Now", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                onRetry()
            }
        }
    }
}

@MainActor
@Observable
final class TVAppModel {
    enum Route { case loading, onboarding, slideshow, resolveFailed }

    // Persisted config (non-secret) + secrets (keychain) — the same stores the iPad app uses.
    let config = UserDefaultsConfigStore()
    let keychain = KeychainAPIKeyStore()
    let sourceStore = UserDefaultsSourceLibraryStore()
    let secretStore = KeychainSharedLinkSecretStore()
    let sharedLinkResolver = SharedLinkResolver()
    let themeStore = UserDefaultsThemeStore()
    let screen = SoftwareDimScreenController()
    /// Distinct HA identity for the TV frame — own MQTT topics/discovery/unique_id vs the
    /// iPad frame (FR-1000-08). Broker credentials are entered on the TV (TVBrokerSetupView).
    let frameIdentity = FrameIdentity(
        deviceID: (UIDevice.current.identifierForVendor?.uuidString ?? "immich-slideshow") + "-appletv",
        deviceName: "Photo Frame (Apple TV)"
    )
    let brokerProvider: BrokerConfigProvider
    let powerManager: PowerManager

    // Shared onboarding view model (reused unchanged from OnboardingKit).
    let onboarding: OnboardingViewModel

    /// Source library with the app-level switch wired in (`onSwitchActive` persists the
    /// active change and rebuilds a RUNNING slideshow — the same contract the iPad app
    /// fulfills). Lazy so the closure can capture `self`.
    @ObservationIgnored lazy var sourceLibrary: SourceLibraryViewModel = SourceLibraryViewModel(
        store: sourceStore,
        secretStore: secretStore,
        resolver: sharedLinkResolver,
        onSwitchActive: { [weak self] id in self?.activeSourceChanged(id) }
    )

    // iCloud non-secret prefill (FR-1000-06). Secret hydration (FR-1000-12) is fresh-install
    // only and entitlement-gated (see start()).
    private let configConsumer: ConfigConsumer

    private(set) var route: Route = .loading
    private(set) var slideshow: SlideshowViewModel?

    /// App-owned HA coordinator (US4): ownership lives here — not on the view — so a source
    /// switch can fully stop the old coordinator BEFORE the next one starts. Two live
    /// transports would share one MQTT client id, and unordered stop/start lets the old
    /// retained "offline" (or its LWT after client takeover) land after the new "online".
    private var haCoordinator: HAControlCoordinator?
    private var isStartingHA = false

    init() {
        powerManager = PowerManager(screen: screen)
        brokerProvider = BrokerConfigProvider(
            settingsStore: KeychainBrokerSettingsStore(),
            deviceID: frameIdentity.deviceID
        )
        onboarding = OnboardingViewModel(
            api: { ImmichClient(config: $0) },
            config: config,
            keychain: keychain,
            sourceStore: sourceStore
        )
        // NSUbiquitousKeyValueStore is safe to instantiate without iCloud (it simply never
        // syncs); the secret store is entitlement-gated by the factory (CKContainer.default()
        // aborts without the CloudKit entitlement, even with an iCloud account signed in).
        configConsumer = ConfigConsumer(
            configStore: UbiquitousKVSConfigSyncStore(),
            secretStore: SecretSyncStoreFactory.make()
        )
    }

    func start() async {
        // FR-1000-06/12: on a FRESH install only, restore synced non-secret config into the
        // local stores and hydrate secrets from CloudKit into the local keychain — the
        // zero-typing setup path. A configured frame skips both, so its keychain is never
        // clobbered by stale synced values and routing never waits on a CloudKit fetch.
        if sourceStore.load().sources.isEmpty, config.loadBaseURL() == nil {
            restoreSyncedConfig()
            _ = await configConsumer.hydrateSecrets(
                into: TVSecretWriter(keychain: keychain, sharedLinkSecretStore: secretStore)
            )
            // Prefill the onboarding server field from synced config for the manual path too.
            if let synced = configConsumer.prefill(), let base = synced.baseURL {
                onboarding.serverURLInput = base.absoluteString
            }
        }
        // Verification seam: seed the password-free demo shared link so the sim plays real
        // photos end-to-end (proves the resolve → ImmichClient → engine → tvOS render pipeline).
        if ProcessInfo.processInfo.arguments.contains("--tv-demo-sharedlink") {
            await submitSharedLink("https://bilder.kippings.de/s/Iceland2021")
            if route == .slideshow { return }
        }
        await evaluateGate()
    }

    /// Route: a complete config goes straight to the slideshow with the real source;
    /// an incomplete config resumes onboarding at the first missing step (StartupGate,
    /// mirroring the iPad app); a complete config whose source fails to RESOLVE (network
    /// blip, cold boot before Wi-Fi) routes to the auto-retrying error surface — never to
    /// onboarding, whose `.done` step has no UI (FR-1000-04).
    func evaluateGate() async {
        let step = StartupGate(config: config, keychain: keychain, sourceStore: sourceStore).initialStep()
        if step == .done {
            if let built = await buildSlideshow() {
                slideshow = built
                route = .slideshow
            } else {
                route = .resolveFailed
            }
        } else {
            onboarding.step = step
            route = .onboarding
        }
    }

    private func buildSlideshow() async -> SlideshowViewModel? {
        guard let active = sourceStore.load().active else { return nil }
        let resolver = ActiveSourceResolver(
            albumBaseURL: config.loadBaseURL(),
            apiKey: keychain.read(),
            secretStore: secretStore,
            sharedLinkResolver: sharedLinkResolver
        )
        guard let resolved = try? await resolver.resolve(active) else { return nil }
        return SlideshowViewModel(
            source: ImmichClient(config: resolved.serverConfig),
            collectionID: resolved.albumID,
            ticker: RealTicker(),
            settingsStore: themeStore,
            preparer: DecodedImageStore.displayStore()
        )
    }

    /// Shared-link path (US2-5): resolve first, activate the resolved source, then route.
    func submitSharedLink(_ urlString: String) async {
        await sourceLibrary.resolveSharedLink(urlString: urlString, label: "")
        await routeIfResolved()
    }

    /// Password confirmation for a protected link (US2-5: password only when the link needs one).
    func confirmSharedLinkPassword(_ password: String) async {
        await sourceLibrary.confirmSharedLinkPassword(password)
        await routeIfResolved()
    }

    private func routeIfResolved() async {
        guard case let .resolved(sourceID) = sourceLibrary.addState else { return }
        sourceLibrary.setActive(id: sourceID)
        await evaluateGate()
    }

    /// Server + album path: record the picked album and activate it. Reuses an existing
    /// source for the same album and uniquifies a colliding label, so the pick can never
    /// silently fail into a dead-end confirm loop.
    func selectAlbum(_ album: Album) {
        let label = album.name.isEmpty ? album.id : album.name
        sourceLibrary.activateAlbumSource(albumID: album.id, label: label)
    }

    /// US4: build a fresh HA coordinator for the current run — nil without broker
    /// credentials. Distinct device identity (FR-1000-08) via `frameIdentity`; brightness
    /// maps to the software dim; image publishing is omitted (`.currentPhotoImage` not in
    /// the default set). Only sources the TV can actually play right now are offered on the
    /// HA select: album sources need the local server config + API key, which secret
    /// hydration may not have delivered (`.manualRequired`) — offering them would let a
    /// remote pick tear the frame down into onboarding.
    private func makeCoordinator(for slideshow: SlideshowViewModel) async -> HAControlCoordinator? {
        guard let brokerConfig = brokerProvider.load() else { return nil }
        let library = sourceStore.load()
        let playable = library.sources.filter { source in
            switch source.kind {
            case .sharedLink:
                return true
            case .album:
                return config.loadBaseURL() != nil && keychain.read() != nil
            case .photoLibrary:
                return false  // no on-device photo library on tvOS
            }
        }
        let adapter = TVRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: powerManager,
            themeStore: themeStore,
            sources: playable,
            activeSourceID: library.activeID,
            onSelectSource: { [weak self] id in self?.sourceLibrary.setActive(id: id) },
            initialBrightness: screen.brightness
        )
        return HAControlCoordinator(
            transport: NIOMQTTTransport(config: brokerConfig),
            control: adapter,
            settings: adapter,
            photoReporter: adapter,
            configStore: brokerProvider,
            deviceName: frameIdentity.deviceName,
            enabledEntities: HAEntity.defaultEnabled
        )
    }

    // MARK: - HA coordinator lifecycle (US4)

    /// Build a fresh coordinator per run and start it; release it immediately if the
    /// connect failed so a later foreground retries. Idempotent; mirrors the iOS
    /// per-run lifecycle, hoisted onto the model so source switches can sequence it.
    func startHA() async {
        guard haCoordinator == nil, !isStartingHA, let slideshow else { return }
        isStartingHA = true
        defer { isStartingHA = false }
        guard let coordinator = await makeCoordinator(for: slideshow) else { return }
        // The show may have been switched while the coordinator was being built (it
        // fetches state); starting it would bind HA to the outgoing generation.
        guard self.slideshow === slideshow else { return }
        haCoordinator = coordinator
        await coordinator.start()
        if coordinator.connection == .disconnected {
            haCoordinator = nil
            await coordinator.stop()
        }
    }

    func stopHA() async {
        guard let coordinator = haCoordinator else { return }
        haCoordinator = nil
        await coordinator.stop()
    }

    // MARK: - Active-source switching (US1/US4)

    /// The app-level switch contract behind `SourceLibraryViewModel.setActive` (the same
    /// one the iPad app wires): persist the active change, and rebuild a RUNNING slideshow
    /// against the new source. During onboarding only the persist happens — routing stays
    /// with the flow (the confirm step must not be skipped). A rebuild failure (e.g. HA
    /// picked a source whose backend is unreachable) reverts the active change and keeps
    /// the current show playing — a remote pick must never take the frame down.
    private func activeSourceChanged(_ id: String) {
        let previousID = sourceStore.load().activeID
        persistActiveSource(id)
        guard route == .slideshow, id != previousID else { return }
        Task { await rebuildOrRevert(previousID: previousID) }
    }

    private func rebuildOrRevert(previousID: String?) async {
        if let rebuilt = await buildSlideshow() {
            // Fully stop the old coordinator BEFORE the swap: the new view generation's
            // `.task` then starts the next one, so retained availability ends "online".
            await stopHA()
            slideshow = rebuilt
            route = .slideshow
        } else if let previousID {
            persistActiveSource(previousID)
        }
    }

    private func persistActiveSource(_ id: String) {
        var library = sourceStore.load()
        guard library.sources.contains(where: { $0.id == id }) else { return }
        library.setActive(id: id)
        sourceStore.save(library)
    }

    /// On a fresh install with synced config present, restore the local non-secret stores
    /// from iCloud KVS (server URL, source library, display options) so the TV needs no
    /// re-entry (FR-1000-06). Caller guarantees freshness (see `start()`).
    private func restoreSyncedConfig() {
        guard let synced = configConsumer.prefill() else { return }
        if let base = synced.baseURL { config.saveBaseURL(base) }
        if let data = synced.sourceLibrary,
           let library = try? JSONDecoder().decode(SourceLibrary.self, from: data) {
            sourceStore.save(library)
        }
        if let data = synced.theme,
           let settings = try? JSONDecoder().decode(ThemeSettings.self, from: data) {
            themeStore.settings = settings
        }
    }

    func finishOnboarding() async {
        await evaluateGate()
    }
}

/// Writes CloudKit-fetched secrets into the local tvOS keychain (FR-1000-05/12) — on a
/// fresh install only, and never over an existing local value (a key freshly entered on
/// the TV always wins over a stale synced one). MQTT credentials are entered directly via
/// the tvOS broker onboarding, not restored here.
private struct TVSecretWriter: SecretWriting {
    let keychain: KeychainAPIKeyStore
    let sharedLinkSecretStore: KeychainSharedLinkSecretStore
    func writeImmichApiKey(_ apiKey: String) async {
        guard keychain.read() == nil else { return }
        try? keychain.save(apiKey)
    }
    func writeMqttCredentials(_ credentials: Data) async {}
    func writeSharedLinkPassword(_ password: String, forSourceID sourceID: String) async {
        guard sharedLinkSecretStore.readPassword(forSourceID: sourceID) == nil else { return }
        try? sharedLinkSecretStore.savePassword(password, forSourceID: sourceID)
    }
}
