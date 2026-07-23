//
//  SlideshowView.swift
//  OwnFrame
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
import PhotoLibraryKit
import PowerKit
import PurchaseKit
import SlideshowKit
import SwiftUI
import ThemeKit

struct SlideshowView: View {
    let viewModel: SlideshowViewModel
    let powerManager: PowerManager
    // nil for a Photos-library source (900, US1): there is no Immich behind it, so the
    // Immich-backed surfaces (photo info, album browser) hide until T031/T032 bring
    // source-neutral parity.
    let api: (any ImmichAPI)?
    // 900 US3: the active source is a Photos-library source — switches the error state's
    // auth copy/fix to the photo-access wording and the iOS Settings path.
    var isPhotoLibrarySource = false
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
    // 900 / US1: the PhotoKit seam for the sources manager's Photos-album tab.
    var makePhotoGateway: () -> any PhotoLibraryGateway = { PHKitGateway() }
    // Storage stores (320): shared with the engine; the settings sheet surfaces
    // usage/budget/Clear against the same instances the slideshow writes to.
    var diskCache: (any DiskImageStoring)?
    var snapshotStore: (any SourceSnapshotStoring)?
    var budgetStore: (any CacheBudgetStore)?

    @Environment(\.scenePhase) private var scenePhase
    // 1100: what the frame owns. Optional because SwiftUI previews and unit hosts render this
    // view without the app's environment; absent resolves to unentitled, so the gate fails
    // CLOSED — a wiring mistake can never hand out a paid feature. The `--uitest-entitlements`
    // XCUITests are what protect the opposite direction (a paying frame losing its features).
    @Environment(EntitlementStore.self) private var entitlements: EntitlementStore?
    // The per-photo ambience latch (FR-1100-12). nil until the first boundary, so the very first
    // render still reflects the live entitlement instead of flashing an ungated frame.
    @State private var latchedAmbience: AmbienceGate?
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
    // Presented via .sheet(item:) — an isPresented flag plus a captured optional
    // @State raced SwiftUI's first sheet render and showed an empty card (310 UI bug).
    @State private var errorConnectionViewModel: ConnectionSettingsViewModel?

    // 510: the clock overlay's Random place picker. Seeded deterministically under
    // `--uitest-clock-seed=<n>` for stable UI tests; otherwise from the system generator.
    // It relocates at most once per its 6-min cadence, only on a photo-advance boundary.
    @State private var clockRelocation = ClockRelocation(
        picker: RandomPlacePicker(rng: SplitMix64(seed: SlideshowView.clockSeed))
    )
    @State private var clockEpoch = ContinuousClock().now
    @State private var resolvedRandomPlace: ClockPlace = .bottomTrailing
    @State private var randomResolved = false

    private static let chromeAutoHide: Duration = .seconds(4.5)

    private static var clockSeed: UInt64 {
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--uitest-clock-seed=") }),
           let seed = UInt64(arg.dropFirst("--uitest-clock-seed=".count)) {
            return seed
        }
        return UInt64.random(in: .min ... .max)
    }

    var body: some View {
        // The chrome owns the layout and is laid out against a stable full-screen frame; the
        // letterboxed/filled image rides along as its `.background`. A `.background` is sized
        // to the host and never feeds its size back up, so switching the image between fit and
        // fill framing (the latter forced by Ken Burns) can't drag the chrome's layout around
        // (FR-300-33). The image still owns the gestures and covers the whole screen, incl.
        // under the hidden status bar, via `.ignoresSafeArea()`.
        ZStack {
            // Ambient clock layer (510): a sibling of the chrome branch, above the photo
            // background. Present while the clock is on and a photo is showing; it fades
            // out on its own whenever the chrome is up (FR-510-02).
            if effectiveClock, viewModel.phase == .playing {
                ClockOverlayView(
                    settings: themeStore.settings.clock,
                    place: clockRenderPlace,
                    idiom: clockIdiom,
                    chromeVisible: chromeVisible
                )
            }
            if chromeVisible {
                chromeOverlay
                    .transition(.opacity)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: chromeVisible)
            .background {
                phaseContent
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    // Tap toggles the chrome; a horizontal swipe advances without revealing it.
                    // In the failed state the container gestures are masked off so the error
                    // card's buttons reliably receive their taps (310 UI bug: the screen-wide
                    // tap gesture could swallow button taps and toggle the chrome instead);
                    // the chrome is pinned visible there via onChange below.
                    .gesture(TapGesture().onEnded { toggleChrome() }, including: containerGestureMask)
                    .gesture(swipeGesture, including: containerGestureMask)
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
        .onChange(of: viewModel.phase) { _, newPhase in
            // Failed state: pin the chrome visible (Settings/Albums stay one tap
            // away next to the error card's own actions); auto-hide resumes once
            // playback recovers.
            switch newPhase {
            case .failed:
                chromeVisible = true
                autoHideTask?.cancel()
                autoHideTask = nil
            case .playing:
                if chromeVisible {
                    scheduleAutoHide()
                }
            default:
                break
            }
        }
        .onChange(of: viewModel.currentAssetID) { _, _ in
            // Photo-advance boundary: the only moment a Random clock may relocate.
            relocateRandomClockIfNeeded()
            // …and the only moment the ambience gate may change what renders. Doing it here
            // rather than reactively is what keeps a revocation from freezing a pan
            // mid-photo (FR-1100-12).
            relatchAmbience()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Foreground-only effects (Konstitution V, FR-003/FR-004/FR-012): iOS hands
            // control back in the background, so pause the auto-advance and release the
            // keep-awake; resume and re-acquire on return.
            switch newPhase {
            case .active:
                viewModel.resume()
                powerManager.willEnterForeground()
                // The second latch boundary (FR-1100-12): a purchase or refund that landed
                // while backgrounded takes effect now, not mid-photo.
                relatchAmbience()
                // FR-900-09 (T025): shared-album remote posts carry no notification
                // guarantee, so a Photos source refetches immediately on foreground —
                // the periodic refresh stays the upper bound.
                if isPhotoLibrarySource {
                    Task { await viewModel.refreshNow() }
                }
                Task { await startCoordinator() }
            default:
                viewModel.pause()
                powerManager.didEnterBackground()
                Task { await stopCoordinator() }
            }
        }
        .sheet(isPresented: $showAlbumBrowser) {
            if let api {
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
        }
        .sheet(isPresented: $showSettings) {
            SlideshowSettingsView(
                powerManager: powerManager,
                themeStore: themeStore,
                makeConnectionViewModel: makeConnectionViewModel,
                onConnectionChanged: onConnectionChanged,
                makeSourceLibraryViewModel: makeSourceLibraryViewModel,
                makeServerAPI: makeServerAPI,
                makePhotoGateway: makePhotoGateway,
                isPhotoLibrarySource: isPhotoLibrarySource,
                onReset: onReset,
                diskCache: diskCache,
                snapshotStore: snapshotStore,
                budgetStore: budgetStore
            )
            // Present the settings as a larger page-sized sheet on iPad so the folded-in
            // Connection/MQTT sections aren't cut off behind a cramped form-sheet card
            // (010/US3). All sections remain reachable by scrolling regardless (FR-015).
            .pageSizedSheet()
        }
        .sheet(item: $errorConnectionViewModel) { connectionViewModel in
            NavigationStack {
                ConnectionSettingsView(viewModel: connectionViewModel) { outcome in
                    errorConnectionViewModel = nil
                    onConnectionChanged(outcome)
                }
            }
        }
        .sheet(isPresented: $showSources) {
            if let sourceLibraryViewModel = makeSourceLibraryViewModel() {
                NavigationStack {
                    SourceLibraryView(
                        viewModel: sourceLibraryViewModel,
                        makeServerAPI: makeServerAPI,
                        makePhotoGateway: makePhotoGateway,
                        // 1200/US1: the album tab's no-server guidance routes into the shared
                        // connection editor (FR-210-29/30). Dismiss the sources sheet, then
                        // present the editor — two separate sheet anchors, one off / one on.
                        onAddServer: {
                            showSources = false
                            errorConnectionViewModel = makeConnectionViewModel()
                        }
                    )
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
                    // The connection editor is the Immich fix; a Photos source gets the
                    // iOS Settings path inside the error view instead (900, US3).
                    onFixConnection: isPhotoLibrarySource ? nil : {
                        errorConnectionViewModel = makeConnectionViewModel()
                    },
                    isPhotoLibrarySource: isPhotoLibrarySource
                )
            }
        }
    }

    // MARK: - Chrome reveal + auto-hide

    private func toggleChrome() {
        if chromeVisible { hideChrome() } else { revealChrome() }
    }

    /// Screen-wide chrome gestures run everywhere except the failed state, where
    /// only the subviews (the error card's buttons) may handle touches.
    private var containerGestureMask: GestureMask {
        viewModel.phase == .failed ? .subviews : .all
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
    /// While the show is failed the chrome stays pinned — with the container
    /// gestures masked off there, a hidden chrome would be unreachable.
    private func scheduleAutoHide() {
        guard !pinChrome, viewModel.phase != .failed else { return }
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

    /// The chrome is inserted/removed structurally (`if chromeVisible` above) rather than
    /// held in the tree at `.opacity(0)`: a Liquid Glass container whose opacity was
    /// animated 0→1 swallowed the first tap on its buttons (reveal → tap Next did
    /// nothing — live-smoke bug), while a freshly composed container (the pinned
    /// `--uitest-chrome` path) never did. Insertion recomposes the glass fresh on every
    /// reveal; the `.transition(.opacity)` keeps the same fade.
    @ViewBuilder
    private var chromeOverlay: some View {
        SlideshowChrome(
            viewModel: viewModel,
            // Photo info reads the engine's neutral metadata (T032) — every backend gets
            // it; the album browser stays Immich-backed and hides for a Photos source
            // until T031-adjacent parity.
            onInfo: { showInfo.toggle(); scheduleAutoHide() },
            onAlbums: api == nil ? nil : { showAlbumBrowser = true },
            onSettings: { showSettings = true },
            onInteraction: { scheduleAutoHide() }
        ) {
            if showInfo, let assetID = viewModel.currentAssetID {
                PhotoInfoView(
                    fetchMetadata: { [viewModel] in try? await viewModel.metadata(for: $0) },
                    assetID: assetID
                )
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
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

    /// The decode-ahead bitmap when it already landed (1000 Ken Burns: no lazy
    /// first-render decode mid-swap); reading the store in body re-renders once
    /// a prepared instance arrives. `UIImage(data:)` stays the fallback below.
    private var preparedImage: UIImage? {
        guard let id = viewModel.currentAssetID else { return nil }
        return (viewModel.preparer as? DecodedImageStore<UIImage>)?.image(for: id)
    }

    @ViewBuilder
    private var currentImage: some View {
        if let data = viewModel.currentImageData, let image = preparedImage ?? UIImage(data: data) {
            SlidePhotoView(
                image: image,
                fillsScreen: fillsScreen,
                kenBurnsActive: kenBurnsActive,
                kenBurnsPan: kenBurnsPan,
                durationSeconds: photoDurationSeconds
            )
            .id(viewModel.currentAssetID)
            .transition(imageTransition)
            // Keep both the outgoing and incoming photo above the opaque black backdrop
            // during the swap: without an explicit zIndex, SwiftUI drops the removed view
            // behind the `Color.black` sibling, turning every transition into a hard cut
            // to black followed by a fade-in from black (pre-release transition bug).
            .zIndex(1)
        } else {
            Color.black
        }
    }

    // MARK: - Render-time settings (008)

    // MARK: - The ambience gate (1100)

    /// Whether the frame currently owns the Supporter Unlock, read live.
    private var isUnlocked: Bool {
        entitlements?.current.contains(.supporter) ?? false
    }

    /// The latch in force right now. Before the first boundary it mirrors the live
    /// entitlement, so a launch is never a frame behind.
    private var ambience: AmbienceGate {
        latchedAmbience ?? AmbienceGate(entitled: isUnlocked)
    }

    /// Ken Burns as it should actually render: the user's stored setting, minus the gate.
    ///
    /// Every Ken Burns decision in this view goes through here rather than reading
    /// `themeStore.settings.kenBurns` directly. Gating only the motion would leave an
    /// unentitled frame with Ken Burns' *framing* (fill) and its transition degradation but
    /// no movement — a visibly broken state rather than a clean free tier.
    private var effectiveKenBurns: Bool {
        ambience.effectiveKenBurns(setting: themeStore.settings.kenBurns)
    }

    /// The clock's participation, gated the same way. The stored setting is untouched, so the
    /// settings row and the HA state topic keep reporting what the user chose (FR-1100-14).
    private var effectiveClock: Bool {
        ambience.effectiveClock(setting: themeStore.settings.clock.isOn)
    }

    /// Adopts the live entitlement at a boundary — a photo advance or a return to the
    /// foreground. Never called mid-photo: that is the whole point of the latch.
    private func relatchAmbience() {
        var gate = ambience
        gate.relatch(entitled: isUnlocked)
        latchedAmbience = gate
    }

    // MARK: - Render-time settings (008)

    /// Fill framing only when the user chose Fill. Ken Burns no longer forces fill: with Fit,
    /// the pan is suppressed and the zoom stays centered, so a fitted photo stays letterboxed
    /// (FR-500-20 / SC-500-09). Decision extracted to `KenBurnsFraming` for host testing.
    private var fillsScreen: Bool {
        KenBurnsFraming.fillsScreen(fit: themeStore.settings.fit)
    }

    /// The Ken Burns pan magnitude, fit-aware: the iPad base pan (16 pt) under Fill, `0` under
    /// Fit (centered zoom, no revealed background).
    private var kenBurnsPan: CGFloat {
        KenBurnsFraming.pan(fit: themeStore.settings.fit, basePan: 16)
    }

    private var kenBurnsActive: Bool {
        effectiveKenBurns && viewModel.phase == .playing && !viewModel.isPaused
    }

    private var photoDurationSeconds: Double {
        Double(themeStore.settings.duration.components.seconds)
    }

    // MARK: - Clock overlay (510)

    private var clockIdiom: ClockIdiom {
        UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
    }

    /// The place the clock renders at: the fixed setting directly, or the picker's
    /// current resolution when the user chose Random.
    private var clockRenderPlace: ClockPlace {
        themeStore.settings.clock.place == .random ? resolvedRandomPlace : themeStore.settings.clock.place
    }

    /// Relocate a Random clock, but only on a photo-advance and at most once per the
    /// picker's cadence; a fixed place is a no-op (FR-510-03). The caption exclusion
    /// follows `showInfo`: while details are enabled, the caption will occupy its place
    /// whenever the chrome is revealed, so the clock must not sit there (issue #26).
    private func relocateRandomClockIfNeeded() {
        guard themeStore.settings.clock.isOn, themeStore.settings.clock.place == .random else { return }
        let now = ContinuousClock().now - clockEpoch
        let current: ClockPlace? = randomResolved ? resolvedRandomPlace : nil
        resolvedRandomPlace = clockRelocation.place(now: now, current: current, detailsEnabled: showInfo)
        randomResolved = true
    }

    /// Fading both photos at once lets the black backdrop bleed through at the midpoint
    /// (a visible dark pulse on every swap), so crossfade/dissolve sequence the fades:
    /// the incoming photo fades in over the still fully opaque outgoing one, which only
    /// fades away afterwards. That keeps at least one photo fully opaque at every moment,
    /// so the swap never dips toward black — regardless of which of the two transitioning
    /// views SwiftUI stacks on top. Slide is a plain opaque push for the same reason.
    private var imageTransition: AnyTransition {
        // While Ken Burns is on, dissolve degrades to the opacity-only crossfade
        // (effectiveStyle): its built-in scale would stack a second, eased zoom on the
        // drift — a fast "catch-up" that breaks the continuous motion.
        switch themeStore.settings.transition.descriptor.effectiveStyle(kenBurns: effectiveKenBurns) {
        case .crossfade:
            return .asymmetric(
                insertion: .opacity.animation(.easeInOut(duration: 0.35)),
                removal: .opacity.animation(.easeInOut(duration: 0.35).delay(0.35))
            )
        case .slide:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .dissolve:
            return .asymmetric(
                insertion: .scale(scale: 1.08).combined(with: .opacity)
                    .animation(.easeInOut(duration: 0.35)),
                removal: .scale(scale: 1.08).combined(with: .opacity)
                    .animation(.easeInOut(duration: 0.35).delay(0.35))
            )
        case .none:
            return .identity
        }
    }

    private var swapAnimation: Animation? {
        themeStore.settings.transition.descriptor.animates ? .easeInOut(duration: 0.6) : nil
    }
}

/// The transitioning slide content. Deliberately a value-props child with no direct
/// view-model reads: while its Ken Burns drift is in flight, a transitioning-out view
/// keeps re-rendering, and if it read the live view model it would pick up the *next*
/// photo's data mid-removal — swapping its own content (and inner identity) inside the
/// removal, which collapses the swap into a hard cut to black and freezes the incoming
/// fade halfway. Frozen value props make the outgoing view a stable snapshot of the old
/// photo that keeps drifting while it fades away.
private struct SlidePhotoView: View {
    let image: UIImage
    let fillsScreen: Bool
    let kenBurnsActive: Bool
    /// Fit-aware pan magnitude: the iPad base pan under Fill, `0` under Fit (centered zoom).
    let kenBurnsPan: CGFloat
    let durationSeconds: Double

    var body: some View {
        // Fit (letterbox) the image into the full screen and center it. Applying
        // `.ignoresSafeArea()` directly to a `scaledToFit` image expands its frame
        // asymmetrically by the safe-area insets, which pushed the picture off-center
        // in landscape; instead the whole ZStack ignores the safe area and the image
        // fills + centers within it. Fill crops to fill with no bars; Fit stays
        // letterboxed even with Ken Burns on, which then suppresses the pan (`kenBurnsPan`
        // is 0) so the centered zoom reveals no background beyond the letterbox.
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
        .kenBurnsMotion(isActive: kenBurnsActive, durationSeconds: durationSeconds, pan: kenBurnsPan)
    }
}
