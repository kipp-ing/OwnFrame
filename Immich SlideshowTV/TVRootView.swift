//
//  TVRootView.swift
//  Immich SlideshowTV
//
//  Topic 1000 composition root + routing. Reuses the shared OnboardingKit view models and
//  the backend-neutral engine; only the tvOS views are new. Non-secret config prefills from
//  iCloud key-value storage via ConfigSyncKit (FR-1000-06); secret hydration over CloudKit
//  encrypted fields (FR-1000-12) is a real-hardware device gate (no CloudKit on the sim), so
//  the manual path always remains complete (US2-3/4). The shared-link path is the primary,
//  lowest-friction tvOS setup (one URL) and is driven by SourceLibraryViewModel's real
//  resolve-first flow (topic 210 semantics).
//

import ConfigSyncKit
import ImmichClient
import OnboardingKit
import PowerKit
import SlideshowKit
import SwiftUI
import ThemeKit

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
                    themeStore: model.themeStore
                )
            } else {
                onboarding
            }
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

@MainActor
@Observable
final class TVAppModel {
    enum Route { case loading, onboarding, slideshow }

    // Persisted config (non-secret) + secrets (keychain) — the same stores the iPad app uses.
    let config = UserDefaultsConfigStore()
    let keychain = KeychainAPIKeyStore()
    let sourceStore = UserDefaultsSourceLibraryStore()
    let secretStore = KeychainSharedLinkSecretStore()
    let sharedLinkResolver = SharedLinkResolver()
    let themeStore = UserDefaultsThemeStore()
    let screen = SoftwareDimScreenController()
    let powerManager: PowerManager

    // Shared onboarding view models (reused unchanged from OnboardingKit).
    let onboarding: OnboardingViewModel
    let sourceLibrary: SourceLibraryViewModel

    // iCloud non-secret prefill (FR-1000-06). Secret hydration (FR-1000-12) is device-gated.
    private let configConsumer: ConfigConsumer

    private(set) var route: Route = .loading
    private(set) var slideshow: SlideshowViewModel?

    init() {
        powerManager = PowerManager(screen: screen)
        onboarding = OnboardingViewModel(
            api: { ImmichClient(config: $0) },
            config: config,
            keychain: keychain,
            sourceStore: sourceStore
        )
        sourceLibrary = SourceLibraryViewModel(
            store: sourceStore,
            secretStore: secretStore,
            resolver: sharedLinkResolver
        )
        // NSUbiquitousKeyValueStore is safe to instantiate without iCloud (it simply never
        // syncs); the CloudKit secret store is device-gated, so an empty in-memory secret
        // store stands in on the simulator — hydration degrades to the manual path.
        configConsumer = ConfigConsumer(
            configStore: UbiquitousKVSConfigSyncStore(),
            secretStore: InMemorySecretSyncStore()
        )
    }

    func start() async {
        // FR-1000-06: prefill onboarding from synced non-secret config when present.
        if let synced = configConsumer.prefill(), let base = synced.baseURL {
            onboarding.serverURLInput = base.absoluteString
        }
        // Verification seam: seed the password-free demo shared link so the sim plays real
        // photos end-to-end (proves the resolve → ImmichClient → engine → tvOS render pipeline).
        if ProcessInfo.processInfo.arguments.contains("--tv-demo-sharedlink") {
            await submitSharedLink("https://bilder.kippings.de/s/Iceland2021")
            if route == .slideshow { return }
        }
        await evaluateGate()
    }

    /// Route: a complete config goes straight to the slideshow with the real source; otherwise
    /// resume onboarding at the first missing step (StartupGate, mirroring the iPad app).
    func evaluateGate() async {
        let step = StartupGate(config: config, keychain: keychain, sourceStore: sourceStore).initialStep()
        if step == .done {
            slideshow = await buildSlideshow()
            route = slideshow != nil ? .slideshow : .onboarding
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
            settingsStore: themeStore
        )
    }

    /// Shared-link path (US2-5): resolve first, activate the resolved source, then route.
    func submitSharedLink(_ urlString: String) async {
        await sourceLibrary.resolveSharedLink(urlString: urlString, label: "")
        if case let .resolved(sourceID) = sourceLibrary.addState {
            sourceLibrary.setActive(id: sourceID)
            await evaluateGate()
        }
    }

    /// Password confirmation for a protected link (US2-5: password only when the link needs one).
    func confirmSharedLinkPassword(_ password: String) async {
        await sourceLibrary.confirmSharedLinkPassword(password)
        if case let .resolved(sourceID) = sourceLibrary.addState {
            sourceLibrary.setActive(id: sourceID)
            await evaluateGate()
        }
    }

    /// Server + album path: record the picked album and activate it.
    func selectAlbum(_ album: Album) {
        let label = album.name.isEmpty ? album.id : album.name
        sourceLibrary.addAlbumSource(albumID: album.id, label: label)
        if let added = sourceLibrary.sources.last(where: { $0.kind == .album(albumID: album.id) }) {
            sourceLibrary.setActive(id: added.id)
        }
    }

    func finishOnboarding() async {
        await evaluateGate()
    }
}
