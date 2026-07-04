//
//  SlideshowRemoteControlAdapter.swift
//  Immich Slideshow
//

import HAControlKit
import ImmichClient
import Observation
import PowerKit
import SlideshowKit
import ThemeKit

/// Bridges Home-Assistant remote control onto the running app: pause/play onto the
/// `SlideshowViewModel`, brightness onto the foreground-gated `PowerManager`, and
/// album selection onto the slideshow's runtime album switch. Also mirrors the
/// full `ThemeSettings` surface to HA (`SettingsControlling`): remote applies are
/// written through the theme store with the local-change callback suppressed, so
/// only genuinely local edits echo back (FR-710-12/20).
@MainActor
public final class SlideshowRemoteControlAdapter: PlaybackControlling {
    private let slideshow: SlideshowViewModel
    private let powerManager: PowerManager
    private let albums: [Album]
    private let themeStore: (any ThemeSettingsStore)?
    private var suppressSettingsCallback = false

    public private(set) var playbackState: PlaybackState = .playing
    // Current target brightness (0.0–1.0). The PowerManager itself owns the actual
    // screen and only applies it in the foreground (Konstitution V); we mirror the
    // requested target so HA echoes a stable value.
    public private(set) var brightness: Double
    public var albumOptions: [String] { albums.map(\.name) }
    public private(set) var currentAlbum: String?
    public var onLocalChange: (@MainActor () -> Void)?
    public var onSettingsChange: (@MainActor () -> Void)?

    public init(
        slideshow: SlideshowViewModel,
        powerManager: PowerManager,
        albums: [Album] = [],
        currentAlbumID: String? = nil,
        initialBrightness: Double = 1.0,
        themeStore: (any ThemeSettingsStore)? = nil
    ) {
        self.slideshow = slideshow
        self.powerManager = powerManager
        self.albums = albums
        self.brightness = min(max(initialBrightness, 0), 1)
        self.currentAlbum = albums.first { $0.id == currentAlbumID }?.name
        self.themeStore = themeStore
        observeThemeSettings()
    }

    public func pause() {
        slideshow.pause()
        playbackState = .paused
        onLocalChange?()
    }

    public func resume() {
        slideshow.resume()
        playbackState = .playing
        onLocalChange?()
    }

    public func setBrightness(_ value: Double) async {
        let clamped = min(max(value, 0), 1)
        brightness = clamped
        await powerManager.setBrightness(clamped, animated: true)
    }

    public func selectAlbum(_ name: String) {
        guard let album = albums.first(where: { $0.name == name }) else { return }
        currentAlbum = name
        Task { await slideshow.switchAlbum(album.id) }
        onLocalChange?()
    }

    // MARK: - Settings observation

    /// Re-armed observation of the theme store. `onChange` fires synchronously at
    /// willSet on the main actor, so the suppress flag must be read THERE — a
    /// remote `apply(_:)` resets it before any deferred task would run.
    private func observeThemeSettings() {
        guard let themeStore else { return }
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
}

// MARK: - SettingsControlling

extension SlideshowRemoteControlAdapter: SettingsControlling {
    public var themeSettings: ThemeSettingsSnapshot {
        Self.snapshot(from: themeStore?.settings ?? ThemeSettings())
    }

    public func apply(_ settings: ThemeSettingsSnapshot) {
        guard let themeStore else { return }
        suppressSettingsCallback = true
        defer { suppressSettingsCallback = false }
        themeStore.settings = Self.themeSettings(from: settings)
    }

    // The 9-field mapping bridges via raw values so HAControlKit stays free of a
    // ThemeKit dependency (Modular Isolation); the fallbacks are unreachable as
    // long as both enums list identical cases.
    private static func snapshot(from settings: ThemeSettings) -> ThemeSettingsSnapshot {
        ThemeSettingsSnapshot(
            order: PlayOrderSetting(rawValue: settings.order.rawValue) ?? .shuffle,
            durationSeconds: Int(settings.duration.components.seconds),
            transition: TransitionSetting(rawValue: settings.transition.rawValue) ?? .crossfade,
            kenBurns: settings.kenBurns,
            fit: FitSetting(rawValue: settings.fit.rawValue) ?? .fit,
            quality: QualitySetting(rawValue: settings.quality.rawValue) ?? .preview,
            clockOn: settings.clock.isOn,
            clockCorner: ClockCornerSetting(rawValue: settings.clock.corner.rawValue) ?? .bottomTrailing,
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
                corner: ClockCorner(rawValue: snapshot.clockCorner.rawValue) ?? .bottomTrailing,
                showDate: snapshot.clockDate
            )
        )
    }
}
