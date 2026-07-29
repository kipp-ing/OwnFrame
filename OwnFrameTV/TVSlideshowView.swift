//
//  TVSlideshowView.swift
//  OwnFrameTV
//
//  Topic 1000 (US1) — the Apple TV slideshow host. Reuses the shared `SlideshowViewModel`
//  engine unchanged; this layer is purely the tvOS view + Siri-Remote wiring:
//
//  - Full-screen current photo honoring the theme's fit + transition settings (parity with
//    the iOS renderer and the HA select entities that mirror them), with an optional Ken
//    Burns drift.
//  - A software-dim overlay (tvOS has no panel brightness) painted above the photo, below
//    the chrome, driven by `SoftwareDimScreenController.dimOverlayOpacity` (FR-1000-07).
//  - Siri-Remote transport: left/right steps, play/pause toggles, and a Menu button that
//    hides the chrome first and only exits to Home from the naked slideshow (FR-1000-03),
//    decided by the tested `TVChromeModel`.
//
//  The HA coordinator and keep-awake lifecycles live on `TVAppModel` (start/stop closures
//  here): the model sequences old-coordinator teardown BEFORE the next one starts on a
//  source switch, so retained availability can never end "offline" while playing (US4).
//

import HAControlKit
import PowerKit
import PurchaseKit
import SlideshowKit
import SwiftUI
import ThemeKit
import UIKit

struct TVSlideshowView: View {
    let viewModel: SlideshowViewModel
    let screen: SoftwareDimScreenController
    let powerManager: PowerManager
    /// Needed for the live fit/transition/Ken Burns/duration settings (the engine keeps its
    /// store private).
    let themeStore: UserDefaultsThemeStore
    /// Start/stop the app-owned HA coordinator for this run (US4). Idempotent on the model.
    var startHA: () async -> Void = {}
    var stopHA: () async -> Void = {}
    /// Whether this view still hosts the app's CURRENT slideshow generation. On an
    /// HA-driven source switch SwiftUI `.id`-swaps the view; the outgoing generation must
    /// NOT tear down the shared PowerManager / the successor's HA coordinator (its
    /// replacement has already taken over).
    var isCurrentGeneration: () -> Bool = { true }
    /// Whether the presenting layer currently covers this view with an in-app modal
    /// (the settings `fullScreenCover`). On tvOS the cover REMOVES this view — its
    /// `onDisappear` fires — so the disappearance alone cannot mean "leaving the
    /// slideshow"; this closure supplies the *why* (FR-700-23).
    var isModalPresented: () -> Bool = { false }
    /// Opens the tvOS settings surface (Home Assistant / MQTT broker).
    var onSettings: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    // 1100: optional so previews/hosts without the app environment still render; absent means
    // unentitled, so the gate fails closed. Mirrors the iOS renderer.
    @Environment(EntitlementStore.self) private var entitlements: EntitlementStore?
    // The per-photo ambience latch (FR-1100-12); nil until the first boundary.
    @State private var latchedAmbience: AmbienceGate?
    /// `.task` re-fires when the settings `fullScreenCover` is dismissed (the covered view
    /// re-appears); the engine must start once per generation or every settings round-trip
    /// would reset pause/order/photo.
    @State private var hasStartedEngine = false

    /// The tested chrome state machine — the single source of truth for chrome visibility and
    /// the Menu-button decision. Time is fed in as a monotonic reading relative to `epoch`.
    @State private var chrome = TVChromeModel()
    @State private var autoHideTask: Task<Void, Never>?
    /// Monotonic origin: `elapsed()` = now - epoch, the `Duration` the chrome model consumes.
    @State private var epoch = ContinuousClock().now

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = viewModel.currentImageData, let image = preparedImage ?? UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fillsScreen ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .kenBurnsMotion(isActive: kenBurnsActive, durationSeconds: durationSeconds, pan: kenBurnsPan)
                    .clipped()
                    .id(viewModel.currentAssetID)
                    .transition(imageTransition)
                    // Keep both the outgoing and incoming photo above the opaque black
                    // backdrop during the swap: without an explicit zIndex, SwiftUI drops
                    // the removed view behind the `Color.black` sibling, turning every
                    // transition into a hard cut to black followed by a fade-in from black
                    // (the pre-release iOS transition bug, fixed there in 05afa82).
                    .zIndex(1)
            }

            // Software dim: above the photo, below the chrome. Non-interactive so it never
            // steals focus/clicks from the transport controls.
            Color.black
                .opacity(screen.dimOverlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if chrome.isVisible {
                TVSlideshowChrome(
                    isPaused: viewModel.isPaused,
                    onPrevious: {
                        reveal()
                        Task { await viewModel.showPrevious() }
                    },
                    onPlayPause: {
                        reveal()
                        viewModel.togglePause()
                    },
                    onNext: {
                        reveal()
                        Task { await viewModel.showNext() }
                    },
                    onSettings: {
                        reveal()
                        onSettings()
                    }
                )
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        // The image swap is animated per the chosen transition; "none" disables the
        // animation entirely so there is no residual fade (mirrors iOS, 008/US2 R5).
        .animation(swapAnimation, value: viewModel.currentAssetID)
        .animation(.easeInOut(duration: 0.3), value: chrome.isVisible)
        .focusable()
        .onMoveCommand { direction in
            reveal()
            switch direction {
            case .left:
                Task { await viewModel.showPrevious() }
            case .right:
                Task { await viewModel.showNext() }
            default:
                break
            }
        }
        .onPlayPauseCommand {
            reveal()
            viewModel.togglePause()
        }
        // FR-1000-03: attach the Menu handler ONLY while the chrome is visible, so a Menu
        // press from the naked slideshow falls through to the tvOS Home screen (never
        // trapped). `TVChromeModel.menuPressed()` returns true here (chrome is visible) and
        // hides it.
        .onExitCommand(perform: exitHandler)
        .task {
            powerManager.activate()
            if !hasStartedEngine {
                hasStartedEngine = true
                await viewModel.start()
            }
            await startHA()
        }
        .onDisappear {
            autoHideTask?.cancel()
            autoHideTask = nil
            // Outgoing generation after a source switch: the successor already owns the
            // shared PowerManager and HA lifecycle — tearing them down here would kill them.
            guard isCurrentGeneration() else { return }
            // FR-700-23: the settings fullScreenCover removes this view, so onDisappear
            // fires for a mere cover too. A cover keeps the broker session (availability
            // stays online, SC-700-15) and the keep-awake hold (FR-400-01); the covered
            // surface is reported via frame_status instead (FR-710-24, signalled by the
            // presenting layer). A genuine exit tears down exactly as before.
            switch SlideshowSurfaceLifecycle.decision(for: .viewDisappeared, isModalPresented: isModalPresented()) {
            case .keepAlive:
                break
            case .tearDown:
                powerManager.deactivate()
                Task { await stopHA() }
            }
        }
        .onChange(of: viewModel.currentAssetID) { _, _ in
            // Photo-advance boundary — the only moment the ambience gate may change what
            // renders, so a revocation never freezes a pan mid-photo (FR-1100-12).
            relatchAmbience()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Foreground-only effects (constitution V): tvOS reclaims control in the
            // background, so pause the auto-advance and release keep-awake, then resume and
            // re-acquire on return. Mirrors the iOS SlideshowView scenePhase handling. The HA
            // coordinator follows the same build-fresh / full-teardown lifecycle (US4).
            guard isCurrentGeneration() else { return }
            switch newPhase {
            case .active:
                powerManager.willEnterForeground()
                viewModel.resume()
                // Latch boundary (FR-1100-12): adopt any entitlement change that landed
                // while backgrounded, rather than mid-photo.
                relatchAmbience()
                Task { await startHA() }
            default:
                viewModel.pause()
                // Leaving the foreground is a real connectivity loss (FR-700-23) and
                // always releases the keep-awake (FR-400-03) — never a keepAlive case.
                if SlideshowSurfaceLifecycle.decision(for: .leftForeground, isModalPresented: isModalPresented()) == .tearDown {
                    powerManager.didEnterBackground()
                    Task { await stopHA() }
                }
            }
        }
    }

    // MARK: - Derived settings

    /// The decode-ahead bitmap when it already landed (1000 Ken Burns: no lazy
    /// first-render decode mid-swap); `UIImage(data:)` stays the fallback in
    /// body. Mirrors the iOS renderer.
    private var preparedImage: UIImage? {
        guard let id = viewModel.currentAssetID else { return nil }
        return (viewModel.preparer as? DecodedImageStore<UIImage>)?.image(for: id)
    }

    // MARK: - The ambience gate (1100)

    /// Whether the frame owns the Supporter Unlock, read live. Universal purchase means this is
    /// normally the same answer the iPad gives.
    private var isUnlocked: Bool {
        entitlements?.current.contains(.supporter) ?? false
    }

    /// The latch in force right now; mirrors the live entitlement until the first boundary.
    private var ambience: AmbienceGate {
        latchedAmbience ?? AmbienceGate(entitled: isUnlocked)
    }

    /// Ken Burns as it should actually render. Both call sites below go through this, so an
    /// unentitled frame never gets Ken Burns' fill framing without its motion.
    private var effectiveKenBurns: Bool {
        ambience.effectiveKenBurns(setting: themeStore.settings.kenBurns)
    }

    /// Adopts the live entitlement at a photo advance or a return to the foreground.
    /// (There is no clock to gate on tvOS yet — that is a known 1000 leftover.)
    private func relatchAmbience() {
        var gate = ambience
        gate.relatch(entitled: isUnlocked)
        latchedAmbience = gate
    }

    /// Fill framing only when the user chose Fill. Ken Burns no longer forces fill: with Fit,
    /// the pan is suppressed and the zoom stays centered, so a fitted photo stays letterboxed
    /// (FR-500-20 / SC-500-09). Mirrors the iOS renderer via the shared `KenBurnsFraming`.
    private var fillsScreen: Bool {
        KenBurnsFraming.fillsScreen(fit: themeStore.settings.fit)
    }

    /// The Ken Burns pan magnitude, fit-aware: the tvOS base pan (24 pt) under Fill, `0` under
    /// Fit (centered zoom, no revealed background). Mirrors the iOS renderer.
    private var kenBurnsPan: CGFloat {
        KenBurnsFraming.pan(fit: themeStore.settings.fit, basePan: 24)
    }

    /// Ken Burns runs only when enabled AND the show is actively playing and not paused.
    private var kenBurnsActive: Bool {
        effectiveKenBurns && viewModel.phase == .playing && !viewModel.isPaused
    }

    /// Live per-photo duration (seconds) from the theme store — drives the Ken Burns rate.
    private var durationSeconds: Double {
        Double(themeStore.settings.duration.components.seconds)
    }

    /// Fading both photos at once lets the black backdrop bleed through at the midpoint
    /// (a visible dark pulse on every swap), so crossfade/dissolve sequence the fades:
    /// the incoming photo fades in over the still fully opaque outgoing one, which only
    /// fades away afterwards. That keeps at least one photo fully opaque at every moment,
    /// so the swap never dips toward black. Slide is a plain opaque push for the same
    /// reason. Ported verbatim from the iOS renderer (05afa82).
    private var imageTransition: AnyTransition {
        switch themeStore.settings.transition.descriptor.style {
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

    // MARK: - Chrome reveal + auto-hide

    /// Monotonic reading the `TVChromeModel` consumes.
    private func elapsed() -> Duration {
        ContinuousClock().now - epoch
    }

    /// Any remote activity reveals the chrome and (re)arms the auto-hide countdown, exactly
    /// as the tested model prescribes.
    private func reveal() {
        chrome.remoteActivity(now: elapsed())
        scheduleAutoHide()
    }

    /// (Re)arm the idle countdown that hides the chrome again. Sleeps `TVChromeModel.autoHide`
    /// then feeds a fresh clock reading into `tick(now:)` — which hides the chrome once the
    /// deadline has passed. Any interleaving `reveal()` cancels and reschedules, pushing the
    /// deadline out (the model handles that in `remoteActivity`).
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: TVChromeModel.autoHide)
            guard !Task.isCancelled else { return }
            chrome.tick(now: elapsed())
        }
    }

    /// The Menu-button handler, present only while the chrome is visible. Consumes the press
    /// by hiding the chrome (model returns true) and stops the pending auto-hide. When the
    /// chrome is hidden this is `nil`, so the system's default Menu behavior (exit to Home)
    /// applies — the user is never trapped in the slideshow.
    private var exitHandler: (() -> Void)? {
        guard chrome.isVisible else { return nil }
        return {
            _ = chrome.menuPressed()
            autoHideTask?.cancel()
            autoHideTask = nil
        }
    }
}
