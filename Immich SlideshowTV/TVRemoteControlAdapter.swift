//
//  TVRemoteControlAdapter.swift
//  Immich SlideshowTV
//
//  tvOS sibling of the iOS `SlideshowRemoteControlAdapter` (topic 1000, US4). Bridges
//  Home-Assistant remote control onto the running Apple TV app: pause/play onto the
//  `SlideshowViewModel`, brightness onto the `PowerManager` (whose tvOS seam drives the
//  software dim, not a physical panel — FR-1000-07), and the album select onto the
//  app-level source switch. It also mirrors the full `ThemeSettings` surface to HA
//  (`SettingsControlling`) exactly as the iOS adapter does.
//
//  The ONLY iOS-flavored part of the reference — image publishing (UIKit downscale,
//  `imageData`) — is omitted here: this adapter stays UIKit-free. `PhotoReporting` is
//  still provided, but every report carries `imageData = nil` and no EXIF/place metadata
//  (there is no tvOS metadata source wired into HA), reporting only the asset ID, phase,
//  active album label, and photo count straight from the engine.
//

import Foundation
import HAControlKit
import Observation
import OnboardingKit
import PowerKit
import SlideshowKit
import ThemeKit

@MainActor
final class TVRemoteControlAdapter: PlaybackControlling, SettingsControlling {
    private let slideshow: SlideshowViewModel
    private let powerManager: PowerManager
    private let themeStore: any ThemeSettingsStore
    /// The saved source library: the select's options and the source of the active label.
    private let sources: [Source]
    /// The app owns the cross-backend rebuild; the adapter only hands it a source id.
    private let onSelectSource: @MainActor (String) -> Void
    private var suppressSettingsCallback = false

    // Single source of truth is the ViewModel's own `isPaused` (see `observePlayback`)
    // so chrome-driven and HA-driven pauses can never drift apart.
    var playbackState: PlaybackState { slideshow.isPaused ? .paused : .playing }
    // Current target brightness (0.0–1.0). The PowerManager owns the actual screen (the
    // software-dim overlay on tvOS) and only applies it in the foreground; we mirror the
    // requested target so HA echoes a stable value.
    private(set) var brightness: Double
    var albumOptions: [String] { sources.map(\.label) }
    private(set) var currentAlbum: String?
    var onLocalChange: (@MainActor () -> Void)?
    var onSettingsChange: (@MainActor () -> Void)?
    var onPhotoChange: (@MainActor (PhotoReport) -> Void)?

    private var _currentPhotoReport: PhotoReport

    init(
        slideshow: SlideshowViewModel,
        powerManager: PowerManager,
        themeStore: any ThemeSettingsStore,
        sources: [Source],
        activeSourceID: String?,
        onSelectSource: @escaping @MainActor (String) -> Void,
        initialBrightness: Double = 1.0
    ) {
        self.slideshow = slideshow
        self.powerManager = powerManager
        self.themeStore = themeStore
        self.sources = sources
        self.onSelectSource = onSelectSource
        self.brightness = min(max(initialBrightness, 0), 1)
        self.currentAlbum = sources.first { $0.id == activeSourceID }?.label
        self._currentPhotoReport = PhotoReport(
            assetID: slideshow.currentAssetID,
            imageData: nil,
            takenAt: nil, city: nil, state: nil, country: nil,
            albumID: slideshow.albumID,
            albumName: sources.first { $0.id == activeSourceID }?.label,
            phase: Self.mapPhase(slideshow.phase),
            photoCount: slideshow.photoCount
        )
        observeThemeSettings()
        observeCurrentPhoto()
        observePlayback()
    }

    // MARK: - PlaybackControlling

    // The chrome play/pause button calls `slideshow.togglePause()` directly, never these
    // methods — so a remote (HA) pause/resume must go through the same `isPaused` flag the
    // chrome uses (via `togglePause()`, guarded so it doesn't flip the wrong way) rather
    // than the ticker-only `pause()/resume()`. Both origins then update one source of
    // truth, and `observePlayback()` is the single place that reports the change to HA.
    func pause() {
        guard !slideshow.isPaused else { return }
        slideshow.togglePause()
    }

    func resume() {
        guard slideshow.isPaused else { return }
        slideshow.togglePause()
    }

    func setBrightness(_ value: Double) async {
        let clamped = min(max(value, 0), 1)
        brightness = clamped
        await powerManager.setBrightness(clamped, animated: true)
    }

    func selectAlbum(_ name: String) {
        // The option is a source LABEL; the switch goes through the app (it owns the
        // cross-backend rebuild strategy). An unknown option changes nothing.
        guard let source = sources.first(where: { $0.label == name }) else { return }
        currentAlbum = name
        onSelectSource(source.id)
        onLocalChange?()
    }

    // MARK: - Settings observation

    /// Re-armed observation of the theme store. `onChange` fires synchronously at willSet
    /// on the main actor, so the suppress flag must be read THERE — a remote `apply(_:)`
    /// resets it before any deferred task would run.
    private func observeThemeSettings() {
        withObservationTracking {
            _ = themeStore.settings
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let suppressed = self.suppressSettingsCallback
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.observeThemeSettings()
                    if !suppressed {
                        self.onSettingsChange?()
                    }
                }
            }
        }
    }

    /// Re-armed observation of `slideshow.isPaused` — the single source of truth for
    /// `playbackState` — so a chrome-driven pause (which never calls `pause()`/`resume()`
    /// above) still reaches HA.
    private func observePlayback() {
        withObservationTracking {
            _ = slideshow.isPaused
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.observePlayback()
                    self.onLocalChange?()
                }
            }
        }
    }

    // MARK: - Photo reporting

    /// Re-armed observation of the running slideshow's current asset + phase. The report
    /// is rebuilt from engine state only — no image bytes, no EXIF/place metadata on tvOS.
    private func observeCurrentPhoto() {
        withObservationTracking {
            _ = slideshow.currentAssetID
            _ = slideshow.phase
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.observeCurrentPhoto()
                    let report = self.makePhotoReport()
                    self._currentPhotoReport = report
                    self.onPhotoChange?(report)
                }
            }
        }
    }

    private func makePhotoReport() -> PhotoReport {
        PhotoReport(
            assetID: slideshow.currentAssetID,
            imageData: nil,
            takenAt: nil, city: nil, state: nil, country: nil,
            albumID: slideshow.albumID,
            albumName: currentAlbum,
            phase: Self.mapPhase(slideshow.phase),
            photoCount: slideshow.photoCount
        )
    }

    private static func mapPhase(_ phase: SlideshowPhase) -> SlideshowPhaseReport {
        switch phase {
        case .loading: return .loading
        case .playing: return .playing
        case .empty: return .empty
        case .failed: return .failed
        }
    }
}

// MARK: - PhotoReporting

extension TVRemoteControlAdapter: PhotoReporting {
    var currentPhotoReport: PhotoReport { _currentPhotoReport }

    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    func showNext() async {
        await slideshow.showNext()
    }

    func showPrevious() async {
        await slideshow.showPrevious()
    }
}

// MARK: - SettingsControlling

extension TVRemoteControlAdapter {
    var themeSettings: ThemeSettingsSnapshot {
        Self.snapshot(from: themeStore.settings)
    }

    func apply(_ settings: ThemeSettingsSnapshot) {
        suppressSettingsCallback = true
        defer { suppressSettingsCallback = false }
        themeStore.settings = Self.themeSettings(from: settings)
    }

    // The 11-field mapping bridges via raw values so HAControlKit stays free of a ThemeKit
    // dependency (Modular Isolation); the fallbacks are unreachable as long as both enums
    // list identical cases.
    private static func snapshot(from settings: ThemeSettings) -> ThemeSettingsSnapshot {
        ThemeSettingsSnapshot(
            order: PlayOrderSetting(rawValue: settings.order.rawValue) ?? .shuffle,
            durationSeconds: Int(settings.duration.components.seconds),
            transition: TransitionSetting(rawValue: settings.transition.rawValue) ?? .crossfade,
            kenBurns: settings.kenBurns,
            fit: FitSetting(rawValue: settings.fit.rawValue) ?? .fit,
            quality: QualitySetting(rawValue: settings.quality.rawValue) ?? .preview,
            clockOn: settings.clock.isOn,
            clockPlace: ClockCornerSetting(rawValue: settings.clock.place.rawValue) ?? .bottomTrailing,
            clockStyle: ClockStyleSetting(rawValue: settings.clock.style.rawValue) ?? .digits,
            clockSize: ClockSizeSetting(rawValue: settings.clock.size.rawValue) ?? .room,
            clockDate: settings.clock.showDate
        )
    }

    private static func themeSettings(from snapshot: ThemeSettingsSnapshot) -> ThemeSettings {
        ThemeSettings(
            order: PlayOrder(rawValue: snapshot.order.rawValue) ?? .shuffle,
            duration: .seconds(snapshot.durationSeconds),
            transition: Transition(rawValue: snapshot.transition.rawValue) ?? .crossfade,
            kenBurns: snapshot.kenBurns,
            fit: ImageFit(rawValue: snapshot.fit.rawValue) ?? .fit,
            quality: ImageQuality(rawValue: snapshot.quality.rawValue) ?? .preview,
            clock: ClockSettings(
                isOn: snapshot.clockOn,
                style: ClockStyle(rawValue: snapshot.clockStyle.rawValue) ?? .digits,
                place: ClockPlace(rawValue: snapshot.clockPlace.rawValue) ?? .bottomTrailing,
                size: ClockSize(rawValue: snapshot.clockSize.rawValue) ?? .room,
                showDate: snapshot.clockDate
            )
        )
    }
}
