//
//  Immich_SlideshowApp.swift
//  Immich Slideshow
//
//  Created by Jan Kipping on 17.06.26.
//

import Foundation
import BrokerSetupKit
import HAControlKit
import HAControlMQTT
import ImmichClient
import OnboardingKit
import PowerKit
import SlideshowKit
import SwiftUI
import ThemeKit

@main
struct Immich_SlideshowApp: App {
    @State private var viewModel: OnboardingViewModel
    // Built lazily at the `.done` route: reads the saved config + Keychain key and
    // constructs an authenticated slideshow. Returns nil only if state is somehow
    // incomplete (the StartupGate normally prevents reaching `.done` without it).
    // Bundled into one `Sendable` value so SwiftUI's `@Sendable` WindowGroup content
    // closure captures a single Sendable struct rather than individual closure
    // properties (which trip a per-function-value data-race warning when read off
    // the App). `@MainActor` keeps the factories' captured stores main-actor-isolated.
    private let factories: Factories

    struct Factories: Sendable {
        // Built lazily at the `.done` route: reads the saved config + Keychain key,
        // resolves the **active source** (album or shared link) into a ServerConfig +
        // album, and constructs an authenticated slideshow. `async` because resolving a
        // shared link hits the network (120). Returns nil only if state is incomplete
        // or the active source fails to resolve. The shared ThemeSettingsStore is
        // injected so the engine reads live display preferences (008); the same
        // instance backs the settings UI.
        let makeSlideshow: @MainActor @Sendable (any ThemeSettingsStore) async -> SlideshowViewModel?
        // The authenticated Immich client for UI that browses beyond the active
        // album (the album-browser sheet). Built from the active source (120).
        let makeAPI: @MainActor @Sendable () async -> (any ImmichAPI)?
        // The server API-key client, independent of the active source — used by the
        // Settings source manager's album picker, which always lists the server's
        // albums even when the active source is a shared link (120, US2).
        let makeServerAPI: @MainActor @Sendable () async -> (any ImmichAPI)?
        // Persist a new active source and report how the running slideshow should
        // restart: album→album swaps the album on the same client; anything involving a
        // shared link rebuilds (120, US1). nil = no restart (unknown or already active).
        let switchActiveSource: @MainActor @Sendable (String) -> SourceRestartStrategy?
        // Builds the Settings source manager's view model (120, US2). The caller passes
        // an `onSwitchActive` that restarts the running slideshow (RootView.switchSource).
        let makeSourceLibraryViewModel: @MainActor @Sendable (@escaping (String) -> Void) -> SourceLibraryViewModel
        // Keeps the display awake during the slideshow and can control brightness.
        // Backed by the live screen in production, a fake under `--uitest` so the
        // hermetic test never touches real device brightness.
        let makePowerManager: @MainActor @Sendable () -> PowerManager
        let makeCoordinator: @MainActor @Sendable (SlideshowViewModel, PowerManager, UserDefaultsThemeStore) async -> HAControlCoordinator?
        // Builds the in-app connection editor view model (009): same config/Keychain
        // seams as the slideshow, validating against a freshly built ImmichClient.
        let makeConnectionSettingsViewModel: @MainActor @Sendable () -> ConnectionSettingsViewModel?
        // Persists a newly chosen album to the config after a connection change left the
        // previously selected album absent (009, FR-013), without re-onboarding.
        let saveSelectedAlbum: @MainActor @Sendable (String) -> Void
        // Consume a pending shared link handed in by the Share Extension via the App Group
        // (210, US2). Returns the non-secret URL once, then clears it; nil if none.
        let takePendingLink: @MainActor @Sendable () -> URL?
        // The current source library, used to route an incoming link (unconfigured ⇒ prefill
        // onboarding; configured ⇒ switch/add+activate) without touching a secret (210, US2).
        let loadLibrary: @MainActor @Sendable () -> SourceLibrary
        // The persistence tier (320): ONE disk cache + snapshot store + budget
        // store for the app's lifetime, created here because the slideshow view
        // model is rebuilt on connection/source changes and Settings must act on
        // the same instances the engine writes to (research R6).
        let diskCache: any DiskImageStoring
        let snapshotStore: any SourceSnapshotStoring
        let cacheBudgetStore: any CacheBudgetStore
    }

    init() {
        #if DEBUG
        // Hermetic seam for XCUITests: when launched with `--uitest`, drive both the
        // onboarding flow and the slideshow against in-memory stubs — no network, no
        // real keychain — so the UI walkthrough is deterministic and CI-safe. The
        // production path below is untouched.
        if UITestSupport.isActive {
            // One shared set of in-memory stores backs both onboarding and the slideshow,
            // so a source added during onboarding flows into the running show (120, US2).
            let config = InMemoryConfigStore()
            let keychain = InMemoryKeychainStore()
            let sourceStore = InMemorySourceLibraryStore()
            let secretStore = InMemorySharedLinkSecretStore()
            let resolver = UITestSharedLinkResolver()
            // 210 US2: seed a pending shared link (as the Share Extension would) so the host's
            // incoming-link consumption is testable without the system Share Sheet. The value
            // is the launch argument following `--uitest-pending-link`.
            let pendingLinkStore = InMemoryPendingSharedLinkStore(pendingURL: UITestSupport.pendingLinkURL)
            // 320: REAL file-backed stores in the sandbox tmp dir so the hermetic
            // build exercises the production disk paths. They persist across
            // relaunches within a test; `--uitest-reset-storage` starts clean.
            let storage = UITestSupport.makeStorageStores()

            let uitestViewModel = OnboardingViewModel(
                api: { _ in StubImmichAPI() },
                config: config,
                keychain: keychain,
                sourceStore: sourceStore
            )
            // Optional fast path for manual/visual verification and the Settings/chrome
            // tests: seed a complete state (key + base URL + one active album source) and
            // jump straight into the stubbed slideshow. The default `--uitest` path leaves
            // the stores empty so onboarding drives the first source itself.
            if ProcessInfo.processInfo.arguments.contains("--uitest-slideshow") {
                config.save(AppConfiguration(baseURL: URL(string: "https://photos.example.test")!, selectedAlbumID: "a1"))
                try? keychain.save("uitest-key")
                sourceStore.save(UITestSupport.seededLibrary())
                uitestViewModel.step = .done
            } else if ProcessInfo.processInfo.arguments.contains("--uitest-onboarding-source") {
                // Visual-verification seam: jump straight to the add-source step with the
                // connection already validated (the step loads the stub albums itself).
                config.saveBaseURL(URL(string: "https://photos.example.test")!)
                try? keychain.save("uitest-key")
                uitestViewModel.step = .source
            } else if ProcessInfo.processInfo.arguments.contains("--uitest-onboarding-choice") {
                // 210 US1: a blank install opens on the first-run choice screen. Stores
                // stay empty so the shared-link path drives the first (and only) source.
                uitestViewModel.step = .choice
            } else if ProcessInfo.processInfo.arguments.contains("--uitest-shared-link-only") {
                // 210 US1: jump straight to the shared-link-only entry screen (no API key).
                uitestViewModel.step = .sharedLinkSetup
            }
            _viewModel = State(initialValue: uitestViewModel)
            let switchActiveSource: @MainActor @Sendable (String) -> SourceRestartStrategy? = { id in
                var library = sourceStore.load()
                let previous = library.active
                guard previous?.id != id, library.sources.contains(where: { $0.id == id }) else { return nil }
                library.setActive(id: id)
                sourceStore.save(library)
                guard let next = library.active else { return nil }
                return SourceLibrary.restartStrategy(from: previous, to: next)
            }
            factories = Factories(
                makeSlideshow: { @MainActor @Sendable store in
                    UITestSupport.makeSlideshowViewModel(
                        settingsStore: store, library: sourceStore.load(),
                        diskCache: storage.diskCache, snapshots: storage.snapshotStore
                    )
                },
                makeAPI: { @MainActor @Sendable in StubImmichAPI() },
                makeServerAPI: { @MainActor @Sendable in StubImmichAPI() },
                switchActiveSource: switchActiveSource,
                makeSourceLibraryViewModel: { @MainActor @Sendable onSwitchActive in
                    SourceLibraryViewModel(store: sourceStore, secretStore: secretStore, resolver: resolver, onSwitchActive: onSwitchActive)
                },
                makePowerManager: { @MainActor @Sendable in UITestSupport.makePowerManager() },
                makeCoordinator: { @MainActor @Sendable _, _, _ in nil },
                makeConnectionSettingsViewModel: { @MainActor @Sendable in UITestSupport.makeConnectionSettingsViewModel() },
                saveSelectedAlbum: { @MainActor @Sendable _ in },
                takePendingLink: { pendingLinkStore.takePendingURL() },
                loadLibrary: { sourceStore.load() },
                diskCache: storage.diskCache,
                snapshotStore: storage.snapshotStore,
                cacheBudgetStore: storage.budgetStore
            )
            return
        }
        #endif

        let config = UserDefaultsConfigStore()
        let keychain = KeychainAPIKeyStore()
        // Source library (120): the persisted list of slideshow sources and the active
        // one. `load()` migrates a legacy `selectedAlbumID` into a one-entry album
        // library on first read, so existing installs keep working unchanged.
        let sourceStore = UserDefaultsSourceLibraryStore()
        let secretStore = KeychainSharedLinkSecretStore()
        let sharedLinkResolver = SharedLinkResolver()
        // The Share Extension writes an incoming share URL here (App Group, URL only); the
        // host consumes it on launch/foreground/open-URL (210, US2).
        let pendingLinkStore = AppGroupPendingSharedLinkStore()
        let brokerStore = KeychainBrokerSettingsStore()
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "immich-slideshow-device"
        let brokerProvider = BrokerConfigProvider(settingsStore: brokerStore, deviceID: deviceID)
        // Persistence tier (320): images under Caches (iOS may purge — tolerated,
        // FR-320-10), snapshots under Application Support (backup-excluded by the
        // store), budget in UserDefaults. One shared instance each (research R6).
        let cacheBudgetStore = UserDefaultsCacheBudgetStore()
        let diskCache = DiskImageCache(
            root: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ImageCache", isDirectory: true),
            budget: cacheBudgetStore.load().bytes
        )
        let snapshotStore = FileSourceSnapshotStore(
            root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SourceSnapshots", isDirectory: true)
        )
        let viewModel = OnboardingViewModel(
            api: { serverConfig in ImmichClient(config: serverConfig) },
            config: config,
            keychain: keychain,
            sourceStore: sourceStore
        )

        // Resume at the first missing step on launch; a complete state (key + base URL +
        // an active source) routes straight to the slideshow (FR-001/FR-011, 120).
        viewModel.step = StartupGate(config: config, keychain: keychain, sourceStore: sourceStore).initialStep()

        _viewModel = State(initialValue: viewModel)

        // Resolve the active source into a ServerConfig (auth) + album. The API key and
        // any shared-link password stay in the Keychain and are only handed to the
        // client here; they are never logged or persisted elsewhere (Konstitution III).
        // nil when state is incomplete or the active source fails to resolve.
        let resolveActiveSource: @MainActor @Sendable () async -> ResolvedSource? = {
            // A shared-link active source resolves with no API key / album base URL — a
            // shared-link-only setup has neither (FR-210-03/04). The album credentials are
            // passed through (optional) and only required for an album active source.
            guard let active = sourceStore.load().active else { return nil }
            let resolver = ActiveSourceResolver(
                albumBaseURL: config.loadBaseURL(),
                apiKey: keychain.read(),
                secretStore: secretStore,
                sharedLinkResolver: sharedLinkResolver
            )
            return try? await resolver.resolve(active)
        }

        let makeSlideshow: @MainActor @Sendable (any ThemeSettingsStore) async -> SlideshowViewModel? = { settingsStore in
            guard let resolved = await resolveActiveSource() else { return nil }
            return SlideshowViewModel(
                api: ImmichClient(config: resolved.serverConfig),
                albumID: resolved.albumID,
                ticker: RealTicker(),
                diskCache: diskCache,
                snapshots: snapshotStore,
                settingsStore: settingsStore
            )
        }

        // Authenticated client for the album browser, built from the active source;
        // nil only if state is incomplete or resolve fails (same guard as the slideshow).
        let makeAPI: @MainActor @Sendable () async -> (any ImmichAPI)? = {
            guard let resolved = await resolveActiveSource() else { return nil }
            return ImmichClient(config: resolved.serverConfig)
        }

        // Server API-key client, independent of the active source — the Settings source
        // manager lists the server's albums even when the active source is a shared link.
        let makeServerAPI: @MainActor @Sendable () async -> (any ImmichAPI)? = {
            guard let baseURL = config.loadBaseURL(), let apiKey = keychain.read() else { return nil }
            return ImmichClient(config: ServerConfig(baseURL: baseURL, apiKey: apiKey))
        }

        // Switch the active source and persist it; report how the running slideshow
        // should restart (120, US1). Returns nil when the id is unknown or already
        // active, so callers skip an unnecessary restart.
        let switchActiveSource: @MainActor @Sendable (String) -> SourceRestartStrategy? = { id in
            var library = sourceStore.load()
            let previous = library.active
            guard previous?.id != id, library.sources.contains(where: { $0.id == id }) else { return nil }
            library.setActive(id: id)
            sourceStore.save(library)
            guard let next = library.active else { return nil }
            return SourceLibrary.restartStrategy(from: previous, to: next)
        }

        let makeSourceLibraryViewModel: @MainActor @Sendable (@escaping (String) -> Void) -> SourceLibraryViewModel = { onSwitchActive in
            SourceLibraryViewModel(
                store: sourceStore,
                secretStore: secretStore,
                resolver: sharedLinkResolver,
                onSwitchActive: onSwitchActive
            )
        }

        // Production: drive the real device screen. The PowerManager gates all
        // effects to the foreground itself (Konstitution V).
        let makePowerManager: @MainActor @Sendable () -> PowerManager = {
            PowerManager(screen: UIScreenController())
        }
        let makeCoordinator: @MainActor @Sendable (SlideshowViewModel, PowerManager, UserDefaultsThemeStore) async -> HAControlCoordinator? = { slideshow, powerManager, themeStore in
            guard let brokerConfig = brokerProvider.load() else { return nil }

            // Build the API client once (best-effort): serves both the HA album
            // select list and the adapter's current-photo metadata/image fetches.
            let client: (any ImmichAPI)? = {
                guard let appConfig = config.load(), let apiKey = keychain.read() else { return nil }
                return ImmichClient(config: ServerConfig(baseURL: appConfig.baseURL, apiKey: apiKey))
            }()

            // Empty album list on failure so pause/play and brightness still work
            // (FR-003 — the broker is never blocking).
            var albums: [Album] = []
            if let client {
                albums = (try? await client.albums()) ?? []
            }

            // Photo publishing prefs (image off by default, FR-710-07). The same
            // store gates both the adapter's image fetch and the image entity's
            // discovery below.
            let publishOptions = HAPublishOptionsStoreFactory.make()

            let adapter = SlideshowRemoteControlAdapter(
                slideshow: slideshow,
                powerManager: powerManager,
                albums: albums,
                currentAlbumID: config.load()?.selectedAlbumID,
                themeStore: themeStore,
                api: client,
                metadataCache: MetadataCache(limit: 64),
                publishOptions: publishOptions
            )
            let transport = NIOMQTTTransport(config: brokerConfig)

            var enabledEntities: Set<HAEntity> = HAEntity.defaultEnabled
            if publishOptions.options.imageEnabled {
                enabledEntities.insert(.currentPhotoImage)
            }

            return HAControlCoordinator(
                transport: transport,
                control: adapter,
                settings: adapter,
                photoReporter: adapter,
                configStore: brokerProvider,
                deviceName: "Photo Frame",
                enabledEntities: enabledEntities
            )
        }

        // The connection editor reuses the same config + Keychain stores and builds a
        // standard, TLS-validated ImmichClient for its validation call (009).
        let makeConnectionSettingsViewModel: @MainActor @Sendable () -> ConnectionSettingsViewModel? = {
            ConnectionSettingsViewModel(
                api: { ImmichClient(config: $0) },
                config: config,
                keychain: keychain
            )
        }
        let saveSelectedAlbum: @MainActor @Sendable (String) -> Void = { albumID in
            guard let appConfig = config.load() else { return }
            config.save(AppConfiguration(baseURL: appConfig.baseURL, selectedAlbumID: albumID))
            // Keep the source library in sync: the 009 album re-selection repoints the
            // active album source so the resolved slideshow picks up the new album.
            var library = sourceStore.load()
            library.updateActiveAlbumID(albumID)
            sourceStore.save(library)
        }

        factories = Factories(
            makeSlideshow: makeSlideshow,
            makeAPI: makeAPI,
            makeServerAPI: makeServerAPI,
            switchActiveSource: switchActiveSource,
            makeSourceLibraryViewModel: makeSourceLibraryViewModel,
            makePowerManager: makePowerManager,
            makeCoordinator: makeCoordinator,
            makeConnectionSettingsViewModel: makeConnectionSettingsViewModel,
            saveSelectedAlbum: saveSelectedAlbum,
            takePendingLink: { pendingLinkStore.takePendingURL() },
            loadLibrary: { sourceStore.load() },
            diskCache: diskCache,
            snapshotStore: snapshotStore,
            cacheBudgetStore: cacheBudgetStore
        )
    }

    var body: some Scene {
        // Capture as locals so the (Sendable) WindowGroup content closure captures
        // these values directly instead of `self`.
        let onboarding = viewModel
        let factories = factories
        return WindowGroup {
            RootView(onboarding: onboarding, factories: factories)
        }
    }
}

/// Routes between onboarding and the running slideshow. Holds the slideshow view
/// model for the lifetime of the `.done` state so its timer/prefetch survive
/// re-renders; reset tears it down and returns to onboarding (002/US3).
private struct RootView: View {
    let onboarding: OnboardingViewModel
    let factories: Immich_SlideshowApp.Factories

    @State private var slideshow: SlideshowViewModel?
    @State private var powerManager: PowerManager?
    @State private var api: (any ImmichAPI)?
    @Environment(\.scenePhase) private var scenePhase
    // A shared link handed in while unconfigured pre-fills the onboarding setup field;
    // handed into the configured app it drives the resolve-and-activate sheet (210, US2).
    @State private var incomingPrefill = ""
    @State private var incomingSheet: IncomingSheetContext?
    // One shared settings store for the lifetime of the slideshow: the engine reads
    // live preferences from it and the settings UI binds the same concrete instance
    // (008). UI tests run against an isolated, cleared suite so a fresh launch starts
    // from the calm defaults regardless of prior runs.
    @State private var themeStore = RootView.makeThemeStore()
    // Bumped on a successful connection change so the SlideshowView is rebuilt and
    // its `.task` re-runs `start()` against the new client — a live reconnect without
    // re-onboarding (009). The album re-selection sheet handles the album-missing case.
    @State private var connectionGeneration = 0
    @State private var showAlbumReselect = false

    var body: some View {
        content
            // Consume a pending shared link on launch, when returning to the foreground, and
            // when the Share Extension opens the host scheme (210, US2). Each path takes the
            // URL once and routes it; a no-op when there is none.
            .task { consumePendingLink() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { consumePendingLink() }
            }
            .onOpenURL { _ in consumePendingLink() }
            .sheet(item: $incomingSheet) { context in
                IncomingLinkSheet(sourceLibrary: context.viewModel, url: context.url) {
                    incomingSheet = nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if onboarding.step == .done {
            if let slideshow, let powerManager, let api {
                SlideshowView(viewModel: slideshow, powerManager: powerManager, api: api,
                              themeStore: themeStore,
                              makeCoordinator: { await factories.makeCoordinator(slideshow, powerManager, themeStore) },
                              onReset: {
                    self.slideshow = nil
                    self.powerManager = nil
                    self.api = nil
                    onboarding.reset()
                },
                              makeConnectionViewModel: { factories.makeConnectionSettingsViewModel() },
                              onConnectionChanged: handleConnectionChange,
                              makeSourceLibraryViewModel: { factories.makeSourceLibraryViewModel { id in switchSource(id: id) } },
                              makeServerAPI: { await factories.makeServerAPI() },
                              diskCache: factories.diskCache,
                              snapshotStore: factories.snapshotStore,
                              budgetStore: factories.cacheBudgetStore)
                .id(connectionGeneration)
                .sheet(isPresented: $showAlbumReselect) {
                    AlbumBrowserView(api: api, currentAlbumID: nil) { albumID, _ in
                        factories.saveSelectedAlbum(albumID)
                        showAlbumReselect = false
                        rebuildSlideshow()
                    }
                }
            } else {
                Color.black
                    .ignoresSafeArea()
                    .task {
                        slideshow = await factories.makeSlideshow(themeStore)
                        powerManager = factories.makePowerManager()
                        api = await factories.makeAPI()
                    }
            }
        } else {
            // Onboarding's source/confirm steps write the same persisted library the app
            // resolves the active source from. No running slideshow yet, so the switch
            // callback is a no-op (120, US2).
            OnboardingFlowView(
                viewModel: onboarding,
                sharedLinkPrefill: incomingPrefill,
                makeSourceLibrary: { factories.makeSourceLibraryViewModel { _ in } }
            )
        }
    }

    /// React to a successful connection change (009). The editor has already persisted
    /// the validated connection; here we adopt it in the running app. `.albumMissing`
    /// first prompts for a new album (the old selection no longer exists), then rebuilds;
    /// `.success` rebuilds straight away. Failure outcomes never reach here.
    private func handleConnectionChange(_ outcome: ConnectionValidationOutcome) {
        if case .albumMissing = outcome {
            Task { api = await factories.makeAPI() }
            showAlbumReselect = true
        } else {
            rebuildSlideshow()
        }
    }

    /// Switch the active source (120, US1): persist it and restart the running show —
    /// `switchAlbum` when only the album changes, a full rebuild when the client/auth
    /// changes (album↔shared link). No-op when the id is unknown or already active.
    func switchSource(id: String) {
        guard let strategy = factories.switchActiveSource(id) else { return }
        switch strategy {
        case let .switchAlbum(albumID):
            Task { await slideshow?.switchAlbum(albumID) }
        case .rebuild:
            rebuildSlideshow()
        }
    }

    /// Rebuild the slideshow view model (and the API client) from the updated stores and
    /// bump the generation so SlideshowView is recreated and its `.task` re-runs `start()`
    /// against the new connection/source — no return to onboarding.
    private func rebuildSlideshow() {
        Task {
            slideshow = await factories.makeSlideshow(themeStore)
            api = await factories.makeAPI()
            connectionGeneration += 1
        }
    }

    /// Take any pending shared link and route it (210, US2). Unconfigured ⇒ pre-fill the
    /// onboarding setup field; configured ⇒ switch to the matching source instantly, or open
    /// the resolve-and-activate sheet (which also surfaces an invalid link as an error). The
    /// URL only — no secret — ever crosses this boundary (Constitution III).
    private func consumePendingLink() {
        guard let url = factories.takePendingLink() else { return }
        let library = factories.loadLibrary()

        guard library.active != nil else {
            // Unconfigured: route into the shared-link setup, pre-filled. A malformed link
            // still pre-fills so its error surfaces when the user taps Start.
            incomingPrefill = url.absoluteString
            onboarding.step = .sharedLinkSetup
            return
        }

        switch IncomingSharedLink.route(url, library: library, isConfigured: true) {
        case let .switchToExisting(sourceID):
            switchSource(id: sourceID)
        case .addAndActivate, .invalid:
            // Resolve-and-activate over the running slideshow; the sheet's engine validates
            // the link, asks for a password only when required, then switches the active
            // source. An invalid link errors inside the sheet — nothing is persisted.
            incomingSheet = IncomingSheetContext(
                url: url.absoluteString,
                viewModel: factories.makeSourceLibraryViewModel { id in switchSource(id: id) }
            )
        case .prefillOnboarding:
            // Unreachable while configured; pre-fill defensively.
            incomingPrefill = url.absoluteString
            onboarding.step = .sharedLinkSetup
        }
    }

    /// Identifies a presented incoming-link sheet. The per-presentation SourceLibraryViewModel
    /// drives the resolve engine and restarts the slideshow on activation (via `switchSource`).
    struct IncomingSheetContext: Identifiable {
        let id = UUID()
        let url: String
        let viewModel: SourceLibraryViewModel
    }

    private static func makeThemeStore() -> UserDefaultsThemeStore {
        #if DEBUG
        if UITestSupport.isActive {
            // Hermetic UI-test store in a dedicated suite. It persists across launches
            // (so persistence checks work); pass `--uitest-reset-theme` to start from
            // the calm defaults for a defaults check.
            let suite = "uitest.theme"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            if ProcessInfo.processInfo.arguments.contains("--uitest-reset-theme") {
                defaults.removePersistentDomain(forName: suite)
            }
            let store = UserDefaultsThemeStore(defaults: defaults)
            if ProcessInfo.processInfo.arguments.contains("--uitest-kenburns") {
                store.settings.kenBurns = true
            }
            // Seed a specific duration (e.g. a non-preset value Home Assistant can push)
            // so the settings picker's handling of off-preset selections is testable.
            if let arg = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("--uitest-duration-seconds=") }),
               let seconds = Int(arg.dropFirst("--uitest-duration-seconds=".count)) {
                store.settings.duration = .seconds(seconds)
            }
            // Seed a transition style so each style's swap is visually verifiable
            // (simulator recording) without driving the settings UI first.
            if let arg = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("--uitest-transition=") }),
               let transition = Transition(rawValue: String(arg.dropFirst("--uitest-transition=".count))) {
                store.settings.transition = transition
            }
            return store
        }
        #endif
        return UserDefaultsThemeStore()
    }
}

#if DEBUG
// MARK: - UI test seam (DEBUG only)
//
// Activated solely by the `--uitest` launch argument that the XCUITest target
// passes. Keeps the app fully offline: a stubbed ImmichAPI plus in-memory
// config/keychain. Never compiled into Release; never touches the network or
// the real Keychain.

enum UITestSupport {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest")
    }

    /// The shared link seeded as "pending" for the incoming-link test (210, US2): the launch
    /// argument immediately following `--uitest-pending-link`. nil when the flag is absent.
    static var pendingLinkURL: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--uitest-pending-link"),
              flagIndex + 1 < args.count else { return nil }
        return URL(string: args[flagIndex + 1])
    }

    /// 60 stub albums with date + count metadata for the searchable-picker UI test (210,
    /// US3). Includes a diacritic name ("München Trip") so a folded-search assertion is
    /// meaningful, and varied years/counts so name/year/count search all narrow the list.
    nonisolated static func manyAlbums() -> [Album] {
        func midYear(_ year: Int) -> Date {
            Date(timeIntervalSince1970: TimeInterval(year - 1970) * 31_557_600 + 15_552_000)
        }
        var albums = [
            Album(id: "album-munich", name: "München Trip", assetCount: 99,
                  startDate: midYear(2024), endDate: midYear(2024))
        ]
        for index in 1...59 {
            let year = 2018 + (index % 7) // 2018…2024
            albums.append(
                Album(id: "album-\(index)", name: "Album \(index)", assetCount: index * 3,
                      startDate: midYear(year), endDate: midYear(year))
            )
        }
        return albums
    }

    /// One album source ("Wohnzimmer" → album a1), active. The Sources-manager UITest
    /// mutates this; the stub `albums()` also offers album a2 ("Urlaub 2026") to add.
    static func seededLibrary() -> SourceLibrary {
        var library = SourceLibrary()
        library.add(Source(id: "src-a1", label: "Wohnzimmer", kind: .album(albumID: "a1")))
        return library
    }

    static func makeSlideshowViewModel(
        settingsStore: any ThemeSettingsStore,
        library: SourceLibrary = UITestSupport.seededLibrary(),
        diskCache: (any DiskImageStoring)? = nil,
        snapshots: (any SourceSnapshotStoring)? = nil
    ) -> SlideshowViewModel {
        // Resolve the active source to a stub album id (shared links → a2 like the stub
        // resolver) so switching the active source visibly changes the photos.
        let albumID: String
        switch library.active?.kind {
        case let .album(id): albumID = id
        case .sharedLink: albumID = "a2"
        case nil: albumID = "a1"
        }
        return SlideshowViewModel(
            api: StubImmichAPI(),
            albumID: albumID,
            ticker: RealTicker(),
            diskCache: diskCache,
            snapshots: snapshots,
            settingsStore: settingsStore
        )
    }

    /// Real file-backed 320 stores rooted in the sandbox tmp dir (320, T013):
    /// the hermetic build exercises the production disk paths without touching
    /// real caches. State persists across relaunches within a UI test (the
    /// persistence checks need it); `--uitest-reset-storage` starts clean.
    struct StorageStores {
        let diskCache: DiskImageCache
        let snapshotStore: FileSourceSnapshotStore
        let budgetStore: UserDefaultsCacheBudgetStore
    }

    static func makeStorageStores() -> StorageStores {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-storage", isDirectory: true)
        let suite = "uitest.storage"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset-storage") {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let budgetStore = UserDefaultsCacheBudgetStore(defaults: defaults)
        return StorageStores(
            diskCache: DiskImageCache(
                root: root.appendingPathComponent("ImageCache", isDirectory: true),
                budget: budgetStore.load().bytes
            ),
            snapshotStore: FileSourceSnapshotStore(
                root: root.appendingPathComponent("SourceSnapshots", isDirectory: true)
            ),
            budgetStore: budgetStore
        )
    }

    @MainActor
    static func makeConnectionSettingsViewModel() -> ConnectionSettingsViewModel {
        let config = InMemoryConfigStore()
        config.save(AppConfiguration(
            baseURL: URL(string: "https://photos.example.test")!,
            selectedAlbumID: "a1"
        ))
        let keychain = InMemoryKeychainStore()
        try? keychain.save("uitest-key")
        return ConnectionSettingsViewModel(
            api: { _ in StubImmichAPI() },
            config: config,
            keychain: keychain
        )
    }

    @MainActor
    static func makePowerManager() -> PowerManager {
        // In-memory screen so the hermetic UI test never dims/locks the real device.
        PowerManager(screen: StubScreenController())
    }
}

@MainActor
private final class StubScreenController: ScreenControlling {
    var brightness: Double = 0.5
    var isIdleTimerDisabled = false
}

/// Thread-safe counter for the stub's failure seams (the engine fetches from
/// detached retry tasks — explicitly nonisolated against the target's
/// MainActor default isolation).
private nonisolated final class FailureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}

private struct StubImmichAPI: ImmichAPI {
    /// 310 resilience seams (release-gate UI tests):
    /// `--uitest-assets-fail=unreachable|unauthorized` makes `assets()` throw;
    /// `--uitest-assets-recover-after=N` clears the failure after N failed
    /// fetches, so the auto-retry's unattended recovery is observable in the
    /// UI without a real server. Counter is shared across the stub's value
    /// copies (one hermetic app process per test).
    private static let failedFetches = FailureCounter()

    private func assetsFailure() -> ImmichError? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.first(where: { $0.hasPrefix("--uitest-assets-fail=") }) else {
            return nil
        }

        if let recoverArg = arguments.first(where: { $0.hasPrefix("--uitest-assets-recover-after=") }),
           let threshold = Int(recoverArg.split(separator: "=").last ?? ""),
           Self.failedFetches.count >= threshold {
            return nil
        }

        Self.failedFetches.increment()
        return flag.hasSuffix("unauthorized") ? .unauthorized : .unreachable
    }

    func serverVersion() async throws -> String { "3.0.2" }

    func albums() async throws -> [Album] {
        // 210 US3: a large, metadata-bearing list drives the searchable-picker UI test.
        if ProcessInfo.processInfo.arguments.contains("--uitest-albums-many") {
            return UITestSupport.manyAlbums()
        }
        return [Album(id: "a1", name: "Wohnzimmer"), Album(id: "a2", name: "Urlaub 2026")]
    }

    func assets(albumID: String) async throws -> [Asset] {
        if let failure = assetsFailure() {
            throw failure
        }

        // Per-album assets so switching the active source (a1 → a2) visibly changes the
        // photos in the running slideshow (120, US2 source switch).
        switch albumID {
        case "a2":
            return [
                Asset(id: "asset-4", type: "IMAGE"),
                Asset(id: "asset-5", type: "IMAGE"),
                Asset(id: "asset-6", type: "IMAGE"),
            ]
        default:
            return [
                Asset(id: "asset-1", type: "IMAGE"),
                Asset(id: "asset-2", type: "IMAGE"),
                Asset(id: "asset-3", type: "IMAGE"),
            ]
        }
    }

    func preview(assetID: String) async throws -> Data { Self.renderPortrait(for: assetID) }

    func assetInfo(assetID: String) async throws -> AssetInfo {
        // Deterministic EXIF for the photo-info overlay (15 June 2024, 14:30 UTC).
        AssetInfo(
            id: assetID,
            takenAt: Date(timeIntervalSince1970: 1_718_462_400),
            city: "Berlin",
            state: "Berlin",
            country: "Germany"
        )
    }

    // Renders a portrait (3:4) test image per asset: a landscape screen letterboxes
    // it left/right, which makes the centering fix visually verifiable. The white
    // inset border marks the image bounds and the centered dot marks its midpoint.
    private static func renderPortrait(for assetID: String) -> Data {
        let size = CGSize(width: 810, height: 1080)
        let colors: [String: UIColor] = [
            "asset-1": .systemRed,
            "asset-2": .systemGreen,
            "asset-3": .systemBlue,
            "asset-4": .systemOrange,
            "asset-5": .systemTeal,
            "asset-6": .systemPink,
        ]
        let color = colors[assetID] ?? .systemPurple
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setStroke()
            let border = UIBezierPath(rect: CGRect(x: 20, y: 20, width: size.width - 40, height: size.height - 40))
            border.lineWidth = 16
            border.stroke()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: size.width / 2 - 60, y: size.height / 2 - 60, width: 120, height: 120)).fill()
        }
        return image.pngData() ?? Data()
    }
}

private final class InMemoryConfigStore: ConfigStore, @unchecked Sendable {
    private let lock = NSLock()
    private var baseURL: URL?
    private var selectedAlbumID: String?

    func load() -> AppConfiguration? {
        lock.withLock {
            guard let baseURL, let selectedAlbumID, !selectedAlbumID.isEmpty else { return nil }
            return AppConfiguration(baseURL: baseURL, selectedAlbumID: selectedAlbumID)
        }
    }
    func loadBaseURL() -> URL? { lock.withLock { baseURL } }
    func save(_ configuration: AppConfiguration) {
        lock.withLock { baseURL = configuration.baseURL; selectedAlbumID = configuration.selectedAlbumID }
    }
    func saveBaseURL(_ baseURL: URL) { lock.withLock { self.baseURL = baseURL } }
    func clear() { lock.withLock { baseURL = nil; selectedAlbumID = nil } }
}

private final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    func save(_ apiKey: String) throws { lock.withLock { stored = apiKey } }
    func read() -> String? { lock.withLock { stored } }
    func delete() { lock.withLock { stored = nil } }
}

// Resolves any shared link to album a2 so the hermetic Sources-manager test can add a
// shared-link source and see the stub slideshow switch to a different album's photos.
// Two reserved slugs drive the 210 shared-link onboarding paths deterministically:
// `protected` requires the password "letmein" (otherwise `passwordRequired`/`wrongPassword`)
// and `missing` is an invalid link.
private struct UITestSharedLinkResolver: SharedLinkResolving {
    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        switch slug {
        case "protected":
            guard let password else { throw ImmichError.passwordRequired }
            guard password == "letmein" else { throw ImmichError.wrongPassword }
        case "missing":
            throw ImmichError.invalidShareLink
        default:
            break
        }
        return SharedLinkResolution(key: "uitest-key", albumID: "a2", expiresAt: nil)
    }
}
#endif
