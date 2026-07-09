//
//  SlideshowView.swift
//  Immich Slideshow
//
//  Fullscreen slideshow of the selected album. Shows one image at a time with a
//  gentle cross-fade between images (FR-002/FR-004). Empty/error states surface
//  a calm hint instead of a blank screen (FR-009/FR-010). Reset lives in Settings
//  (FR-300-28), keeping the quiet default free of a destructive chrome action
//  (Konstitution VII).
//

import HAControlKit
import ImmichClient
import OnboardingKit
import PowerKit
import SlideshowKit
import SwiftUI
import ThemeKit

struct SlideshowView: View {
    let viewModel: SlideshowViewModel
    let powerManager: PowerManager
    let api: any ImmichAPI
    // The shared, concrete settings store. Render-time preferences (transition, fit,
    // Ken Burns, clock) are read from it directly; the settings sheet binds it (008).
    let themeStore: UserDefaultsThemeStore
    var makeCoordinator: () async -> HAControlCoordinator? = { nil }
    var onReset: () -> Void = {}
    // Connection editor seams (009): build a fresh editor view model on demand, and
    // report a successful change so the app can reconnect the running slideshow.
    var makeConnectionViewModel: () -> ConnectionSettingsViewModel? = { nil }
    var onConnectionChanged: (ConnectionValidationOutcome) -> Void = { _ in }
    // Source manager seams (120, US2): build the Settings source-library view model
    // (its set-active already restarts the running slideshow), and a server API-key
    // client for the add-source album picker.
    var makeSourceLibraryViewModel: () -> SourceLibraryViewModel? = { nil }
    var makeServerAPI: () async -> (any ImmichAPI)? = { nil }

    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: HAControlCoordinator?
    @State private var isStartingCoordinator = false

    // Reveal-on-tap chrome (Slice A). Hidden by default; a tap reveals it and an
    // idle timer hides it again. The status bar follows it so the calm default
    // stays overlay-free.
    // Default hidden; `--uitest-chrome` starts revealed AND pins the chrome (no
    // auto-hide) so screenshot/feature UI tests have stable controls. Reveal +
    // auto-hide behaviour stays covered by their own tests.
    @State private var chromeVisible = ProcessInfo.processInfo.arguments.contains("--uitest-chrome")
    @State private var autoHideTask: Task<Void, Never>?
    private let pinChrome = ProcessInfo.processInfo.arguments.contains("--uitest-chrome")
    // `--uitest-broker` opens settings directly with the MQTT section pre-expanded
    // (broker setup folded into settings — 010), replacing the old standalone sheet.
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("--uitest-settings")
        || ProcessInfo.processInfo.arguments.contains("--uitest-broker")
    @State private var showAlbumBrowser = ProcessInfo.processInfo.arguments.contains("--uitest-albums")
    // Auto-open the source manager for screenshots/visual verification (120, US2),
    // mirroring the other --uitest-* auto-open seams.
    @State private var showSources = ProcessInfo.processInfo.arguments.contains("--uitest-sources")
    @State private var showInfo = ProcessInfo.processInfo.arguments.contains("--uitest-info")
    // Connection editor reached from the error state (009, US2), separate from the
    // one in the settings sheet so a broken connection is fixable without chrome.
    @State private var errorConnectionViewModel: ConnectionSettingsViewModel?
    @State private var showErrorConnection = false

    private static let chromeAutoHide: Duration = .seconds(4.5)

    var body: some View {
        // The chrome owns the layout and is laid out against a stable full-screen frame; the
        // letterboxed/filled image rides along as its `.background`. A `.background` is sized
        // to the host and never feeds its size back up, so switching the image between fit and
        // fill framing (the latter forced by Ken Burns) can't drag the chrome's layout around
        // (FR-300-33). The image still owns the gestures and covers the whole screen, incl.
        // under the hidden status bar, via `.ignoresSafeArea()`.
        chromeOverlay
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                phaseContent
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    // Tap toggles the chrome; a horizontal swipe advances without revealing it.
                    .onTapGesture { toggleChrome() }
                    .gesture(swipeGesture)
            }
        // Status bar + home indicator stay hidden for the whole slideshow — even while the
        // chrome is revealed. The chrome owns its own transport controls, so there's no need
        // for the system clock/battery; keeping them tied to the chrome made them pop back on
        // every tap and, worse, toggled the safe-area insets, which re-laid-out the photo (a
        // visible jump) and reset the Ken Burns pan/zoom. Pinning both hidden keeps the calm
        // photo-frame look and a stable frame (300/US4-AS1).
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // The image swap is animated per the chosen transition; "none" disables the
        // animation entirely so there is no residual fade (008/US2, review R5).
        .animation(swapAnimation, value: viewModel.currentAssetID)
        .task {
            // Entering the slideshow: keep the display awake while it runs in the
            // foreground (FR-001). Idle timer is normalized again on disappear.
            powerManager.activate()
            await viewModel.start()
            await startCoordinator()
        }
        .onDisappear {
            // Leaving the slideshow: restore the idle timer and any app-changed
            // brightness to its baseline (FR-002/FR-011).
            powerManager.deactivate()
            autoHideTask?.cancel()
            Task { await stopCoordinator() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Foreground-only effects (Konstitution V, FR-003/FR-004/FR-012): iOS hands
            // control back in the background, so pause the auto-advance and release the
            // keep-awake; resume and re-acquire on return.
            switch newPhase {
            case .active:
                viewModel.resume()
                powerManager.willEnterForeground()
                Task { await startCoordinator() }
            default:
                viewModel.pause()
                powerManager.didEnterBackground()
                Task { await stopCoordinator() }
            }
        }
        .sheet(isPresented: $showAlbumBrowser) {
            AlbumBrowserView(
                api: api,
                currentAlbumID: viewModel.albumID,
                onSelect: { albumID, assetID in
                    Task {
                        // Switch source album only when it actually changes, then jump
                        // to the tapped photo. One album is active at a time.
                        if albumID != viewModel.albumID {
                            await viewModel.switchAlbum(albumID)
                        }
                        await viewModel.jump(to: assetID)
                    }
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SlideshowSettingsView(
                powerManager: powerManager,
                themeStore: themeStore,
                makeConnectionViewModel: makeConnectionViewModel,
                onConnectionChanged: onConnectionChanged,
                makeSourceLibraryViewModel: makeSourceLibraryViewModel,
                makeServerAPI: makeServerAPI,
                onReset: onReset
            )
            // Present the settings as a larger page-sized sheet on iPad so the folded-in
            // Connection/MQTT sections aren't cut off behind a cramped form-sheet card
            // (010/US3). All sections remain reachable by scrolling regardless (FR-015).
            .pageSizedSheet()
        }
        .sheet(isPresented: $showErrorConnection) {
            if let errorConnectionViewModel {
                NavigationStack {
                    ConnectionSettingsView(viewModel: errorConnectionViewModel) { outcome in
                        showErrorConnection = false
                        onConnectionChanged(outcome)
                    }
                }
            }
        }
        .sheet(isPresented: $showSources) {
            if let sourceLibraryViewModel = makeSourceLibraryViewModel() {
                NavigationStack {
                    SourceLibraryView(viewModel: sourceLibraryViewModel, makeServerAPI: makeServerAPI)
                }
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        ZStack {
            Color.black

            switch viewModel.phase {
            case .loading:
                ProgressView()
                    .tint(.white)
                    .accessibilityIdentifier("slideshow.loading")

            case .playing:
                currentImage
                    .accessibilityElement()
                    .accessibilityLabel("Slideshow image")
                    // The current asset id is exposed as the accessibility value so UI
                    // tests can assert the photo actually swapped on a source switch (120).
                    .accessibilityValue(viewModel.currentAssetID ?? "")
                    .accessibilityIdentifier("slideshow.image")

            case .empty:
                SlideshowEmptyView()

            case .failed:
                SlideshowErrorView(
                    reason: viewModel.failureReason,
                    onRetry: { Task { await viewModel.retry() } },
                    onFixConnection: {
                        errorConnectionViewModel = makeConnectionViewModel()
                        showErrorConnection = errorConnectionViewModel != nil
                    }
                )
            }
        }
    }

    // MARK: - Chrome reveal + auto-hide

    private func toggleChrome() {
        if chromeVisible { hideChrome() } else { revealChrome() }
    }

    private func revealChrome() {
        chromeVisible = true
        scheduleAutoHide()
    }

    private func hideChrome() {
        chromeVisible = false
        showInfo = false
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    /// (Re)arm the idle countdown that hides the chrome again. Called on reveal
    /// and on every control interaction so the chrome stays up while in use.
    private func scheduleAutoHide() {
        guard !pinChrome else { return }
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: Self.chromeAutoHide)
            guard !Task.isCancelled else { return }
            hideChrome()
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                // Horizontal swipe advances next/prev without revealing the chrome.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 {
                    Task { await viewModel.showNext() }
                } else {
                    Task { await viewModel.showPrevious() }
                }
            }
    }

    @ViewBuilder
    private var chromeOverlay: some View {
        SlideshowChrome(
            viewModel: viewModel,
            onInfo: { showInfo.toggle(); scheduleAutoHide() },
            onAlbums: { showAlbumBrowser = true },
            onSettings: { showSettings = true },
            onInteraction: { scheduleAutoHide() }
        )
        .overlay(alignment: .top) {
            if showInfo, let assetID = viewModel.currentAssetID {
                PhotoInfoView(api: api, assetID: assetID)
                    .padding(.top, 100)
                    .transition(.opacity)
            }
        }
        .opacity(chromeVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: chromeVisible)
        .allowsHitTesting(chromeVisible)
    }

    private func startCoordinator() async {
        // One coordinator/transport per run: build fresh on start, fully tear down on stop.
        // That keeps the MQTT client re-connectable across background/foreground (the old
        // reused-client path stayed offline after the first background cycle).
        // `isStartingCoordinator` guards the await gap (building now fetches the album
        // list) against a second appear/scenePhase call building a duplicate. All on the
        // main actor, so the flag check/set is race-free.
        guard coordinator == nil, !isStartingCoordinator else { return }
        isStartingCoordinator = true
        defer { isStartingCoordinator = false }

        guard let coordinator = await makeCoordinator() else { return }
        self.coordinator = coordinator
        await coordinator.start()
        // Connect failed: release it so a later appear/foreground retries instead of being
        // stuck. stop() fully tears the transport down (disconnect + shutdown).
        if coordinator.connection == .disconnected {
            self.coordinator = nil
            await coordinator.stop()
        }
    }

    private func stopCoordinator() async {
        guard let coordinator else { return }
        self.coordinator = nil
        await coordinator.stop()
    }

    @ViewBuilder
    private var currentImage: some View {
        if let data = viewModel.currentImageData, let image = UIImage(data: data) {
            // Fit (letterbox) the image into the full screen and center it. Applying
            // `.ignoresSafeArea()` directly to a `scaledToFit` image expands its frame
            // asymmetrically by the safe-area insets, which pushed the picture off-center
            // in landscape; instead the whole ZStack ignores the safe area and the image
            // fills + centers within it. Fill (or Ken Burns, which implies fill-style
            // framing) crops to fill with no bars.
            let base = Image(uiImage: image).resizable()
            Group {
                if fillsScreen {
                    base.scaledToFill()
                } else {
                    base.scaledToFit()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .kenBurns(isActive: kenBurnsActive, durationSeconds: photoDurationSeconds)
            .id(viewModel.currentAssetID)
            .transition(imageTransition)
        } else {
            Color.black
        }
    }

    // MARK: - Render-time settings (008)

    /// Fill framing when the user chose Fill, or while Ken Burns is on (so the pan/zoom
    /// never reveals a letterbox gap).
    private var fillsScreen: Bool {
        themeStore.settings.fit == .fill || themeStore.settings.kenBurns
    }

    private var kenBurnsActive: Bool {
        themeStore.settings.kenBurns && viewModel.phase == .playing && !viewModel.isPaused
    }

    private var photoDurationSeconds: Double {
        Double(themeStore.settings.duration.components.seconds)
    }

    private var imageTransition: AnyTransition {
        switch themeStore.settings.transition.descriptor.style {
        case .crossfade:
            return .opacity
        case .slide:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .dissolve:
            return .scale(scale: 1.08).combined(with: .opacity)
        case .none:
            return .identity
        }
    }

    private var swapAnimation: Animation? {
        themeStore.settings.transition.descriptor.animates ? .easeInOut(duration: 0.6) : nil
    }
}
