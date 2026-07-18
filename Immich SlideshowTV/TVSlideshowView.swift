//
//  TVSlideshowView.swift
//  Immich SlideshowTV
//
//  Topic 1000 (US1) — the Apple TV slideshow host. Reuses the shared `SlideshowViewModel`
//  engine unchanged; this layer is purely the tvOS view + Siri-Remote wiring:
//
//  - Full-screen current photo with a cross-fade on asset change and an optional Ken Burns
//    drift (mirrors iOS).
//  - A software-dim overlay (tvOS has no panel brightness) painted above the photo, below
//    the chrome, driven by `SoftwareDimScreenController.dimOverlayOpacity` (FR-1000-07).
//  - Siri-Remote transport: left/right steps, play/pause toggles, and a Menu button that
//    hides the chrome first and only exits to Home from the naked slideshow (FR-1000-03),
//    decided by the tested `TVChromeModel`.
//

import HAControlKit
import PowerKit
import SlideshowKit
import SwiftUI
import ThemeKit
import UIKit

struct TVSlideshowView: View {
    let viewModel: SlideshowViewModel
    let screen: SoftwareDimScreenController
    let powerManager: PowerManager
    /// Needed for the live Ken Burns + duration settings (the engine keeps its store private).
    let themeStore: UserDefaultsThemeStore
    /// Builds a fresh HA coordinator for this run — nil without broker credentials (US4).
    var makeCoordinator: (SlideshowViewModel) async -> HAControlCoordinator? = { _ in nil }
    /// Opens the tvOS settings surface (Home Assistant / MQTT broker).
    var onSettings: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: HAControlCoordinator?
    @State private var isStartingCoordinator = false

    /// The tested chrome state machine — the single source of truth for chrome visibility and
    /// the Menu-button decision. Time is fed in as a monotonic reading relative to `epoch`.
    @State private var chrome = TVChromeModel()
    @State private var autoHideTask: Task<Void, Never>?
    /// Monotonic origin: `elapsed()` = now - epoch, the `Duration` the chrome model consumes.
    @State private var epoch = ContinuousClock().now

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = viewModel.currentImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tvKenBurns(isActive: kenBurnsActive, durationSeconds: durationSeconds)
                    .clipped()
                    .id(viewModel.currentAssetID)
                    .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.7), value: viewModel.currentAssetID)
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
            await viewModel.start()
            await startCoordinator()
        }
        .onDisappear {
            powerManager.deactivate()
            autoHideTask?.cancel()
            autoHideTask = nil
            Task { await stopCoordinator() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Foreground-only effects (constitution V): tvOS reclaims control in the
            // background, so pause the auto-advance and release keep-awake, then resume and
            // re-acquire on return. Mirrors the iOS SlideshowView scenePhase handling. The HA
            // coordinator follows the same build-fresh / full-teardown lifecycle (US4).
            switch newPhase {
            case .active:
                powerManager.willEnterForeground()
                viewModel.resume()
                Task { await startCoordinator() }
            default:
                viewModel.pause()
                powerManager.didEnterBackground()
                Task { await stopCoordinator() }
            }
        }
    }

    // MARK: - HA coordinator lifecycle (US4)

    /// Build a fresh coordinator per run and start it; release it immediately if the connect
    /// failed so a later foreground retries. Mirrors iOS `SlideshowView.startCoordinator`.
    private func startCoordinator() async {
        guard coordinator == nil, !isStartingCoordinator else { return }
        isStartingCoordinator = true
        defer { isStartingCoordinator = false }
        guard let coordinator = await makeCoordinator(viewModel) else { return }
        self.coordinator = coordinator
        await coordinator.start()
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

    // MARK: - Derived settings

    /// Ken Burns runs only when enabled AND the show is actively playing and not paused.
    private var kenBurnsActive: Bool {
        themeStore.settings.kenBurns && viewModel.phase == .playing && !viewModel.isPaused
    }

    /// Live per-photo duration (seconds) from the theme store — drives the Ken Burns rate.
    private var durationSeconds: Double {
        let components = themeStore.settings.duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
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
